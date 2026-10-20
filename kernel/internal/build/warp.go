package build

import (
	"fmt"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
	"github.com/luuuuke88/clashmiao/kernel/internal/warp"
)

// ApplyWarp 把 WARP 接进出站图（spec §5.2.2），装配规则全部读 warpPolicies 这一张表：
//
//	warp_over_proxy：warp.detour = select；egress = warp；订阅节点的拨号链原样保留。
//	proxy_over_warp：warp 无 detour；egress = select；每个订阅节点 / 端点的拨号链终点改写为 warp。
//
// warp 端点追加在订阅端点之后，永不进入 select / auto 的成员。返回业务出口 tag 与 warp 端点（未启用时为 nil）。
func ApplyWarp(a *assembled, o *options.Options, warnings *[]string) (string, cfg.Endpoint, error) {
	p, on := PolicyFor(o)
	if !on {
		if o.Warp.Enable {
			return "", nil, fmt.Errorf("%s warp.mode %q is not supported", PrefixBuildFailed, o.Warp.Mode)
		}
		return TagSelect, nil, nil
	}
	conf, err := warp.ParseConfig(o.Warp.WireguardConfig)
	if err != nil {
		return "", nil, fmt.Errorf("%s %w", PrefixBuildFailed, err)
	}
	ep, err := warp.Endpoint(conf, o.Warp, p.WarpDetour)
	if err != nil {
		return "", nil, fmt.Errorf("%s %w", PrefixBuildFailed, err)
	}
	*warnings = append(*warnings, warp.NoiseWarnings(o.Warp, options.Default().Warp)...)
	if o.Warp2.Enable {
		*warnings = append(*warnings, "warp2-unsupported: the second WARP (warp2) is not supported and was ignored")
	}

	if p.NodeDial == NodeDialTerminateAtWarp {
		ws, err := RedirectToWarp(a.Entities)
		if err != nil {
			return "", nil, err
		}
		*warnings = append(*warnings, ws...)
	}
	w := cfg.Endpoint(ep)
	a.Endpoints = append(a.Endpoints, w)
	return p.Egress, w, nil
}

// warpTerminates 说明本次构建是否要把节点拨号链改写到 warp（决定归一化阶段要不要保留指向预置直连类的 detour，
// 以及读时清洗的重映射目标）。
func warpTerminates(o *options.Options) bool {
	p, on := PolicyFor(o)
	return on && p.NodeDial == NodeDialTerminateAtWarp
}

// RedirectToWarp 在**完整实体集合**（所有订阅出站与端点）上，把每条拨号链的终点改写为 warp（proxy_over_warp）：
//
//	无 detour 的节点本身       → detour = warp（不是「既有链」，不记 warning）
//	末端是代理类（最后一个代理）→ 该代理的 detour = warp
//	末端是预置直连类           → 指向它的那一跳的 detour 替换为 warp（预置出站本身不动；direct-fragment 注明「分片被丢弃」）
//	末端已是 warp              → 不变
//	成环 → ErrDetourCycle；悬空 → ErrDetourDangling（均以 build-failed: 开头，不产出配置）
//
// 每个「既有链被改写」的节点记一条 warning（无既有 detour 的不记）；共享的代理末端只改一次；重复调用是幂等的。
// 实体 map 原地修改。
func RedirectToWarp(entities []map[string]any) ([]string, error) {
	detour := map[string]string{}
	var order []string
	for _, e := range entities {
		tag := tagOf(e)
		detour[tag] = strVal(e["detour"])
		order = append(order, tag)
	}

	// 先在原始快照上算出每个节点的链终点与要做的改写，最后一起落地：共享末端因此只改一次，且不受遍历顺序影响。
	rewrite := map[string]string{} // 需要把 detour 设为 warp 的实体 tag
	var warnings []string
	for _, start := range order {
		path := []string{start}
		seen := map[string]bool{start: true}
		cur := start
		for {
			d := detour[cur]
			if d == "" { // cur 是链上最后一个实体，没有 detour
				rewrite[cur] = TagWarp
				if cur != start {
					warnings = append(warnings, rewriteWarning(start, cur, TagWarp, false))
				}
				break
			}
			if d == TagWarp {
				break
			}
			if directClass(d) { // 预置直连类：替换指向它的那一跳
				rewrite[cur] = TagWarp
				warnings = append(warnings, rewriteWarning(start, d, TagWarp, d == TagDirectFragment))
				break
			}
			if _, ok := detour[d]; !ok {
				return nil, fmt.Errorf("%s %w: %q detours to %q which does not exist", PrefixBuildFailed, ErrDetourDangling, cur, d)
			}
			path = append(path, d)
			if seen[d] {
				return nil, fmt.Errorf("%s %w: %s", PrefixBuildFailed, ErrDetourCycle, strings.Join(path, " -> "))
			}
			seen[d] = true
			cur = d
		}
	}
	for _, e := range entities {
		if _, ok := rewrite[tagOf(e)]; ok {
			e["detour"] = TagWarp
		}
	}
	return warnings, nil
}

func rewriteWarning(node, oldEnd, newEnd string, fragmentDropped bool) string {
	msg := fmt.Sprintf("warp-chain-rewritten: %q dial chain ended at %q, now ends at %q", node, oldEnd, newEnd)
	if fragmentDropped {
		msg += " (fragmentation dropped)"
	}
	return msg
}
