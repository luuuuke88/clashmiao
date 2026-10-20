package build

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// NodeDial 说明订阅节点（含订阅端点）的拨号链在该 WARP 模式下怎么处理。
type NodeDial int

const (
	// NodeDialKeep：订阅原样保留（含既有 detour 链；载体链以直连类终止也合法）。
	NodeDialKeep NodeDial = iota
	// NodeDialTerminateAtWarp：每个节点 / 端点的拨号链终点必须是 warp。
	NodeDialTerminateAtWarp
)

// WarpPolicy 是 spec §5.2.2 那张「装配规则与图断言同出一表」的代码形态：
// ApplyWarp 与 CheckWarpGraph（图断言，单元测试与闸门不变量都读它）都只读这一张表，不允许各写一份。
type WarpPolicy struct {
	Mode string
	// Egress 是业务出口 tag：route.final、规则里的 proxy 目标、dns-remote 的 detour 都指向它。
	Egress string
	// WarpDetour 是 warp 端点自己的 detour（空 = 直连）。
	WarpDetour string
	NodeDial   NodeDial
}

var warpPolicies = map[string]WarpPolicy{
	options.WarpWarpOverProxy: {Mode: options.WarpWarpOverProxy, Egress: TagWarp, WarpDetour: TagSelect, NodeDial: NodeDialKeep},
	options.WarpProxyOverWarp: {Mode: options.WarpProxyOverWarp, Egress: TagSelect, WarpDetour: "", NodeDial: NodeDialTerminateAtWarp},
}

// PolicyFor 返回选项对应的 WARP 策略；WARP 未启用（或模式未知）返回 false。
func PolicyFor(o *options.Options) (WarpPolicy, bool) {
	if o == nil || !o.Warp.Enable {
		return WarpPolicy{}, false
	}
	p, ok := warpPolicies[o.Warp.Mode]
	return p, ok
}

// directClass 判断一个 tag 是否是预置的直连类出站（direct / direct-fragment / bypass）。
func directClass(tag string) bool {
	return tag == TagDirect || tag == TagDirectFragment || tag == TagBypass
}

type graphJSON struct {
	Outbounds []map[string]any `json:"outbounds"`
	Endpoints []map[string]any `json:"endpoints"`
	DNS       struct {
		Servers []map[string]any `json:"servers"`
	} `json:"dns"`
	Route struct {
		Final string           `json:"final"`
		Rules []map[string]any `json:"rules"`
	} `json:"route"`
}

// CheckWarpGraph 对**最终配置 JSON**按模式逐条断言 WARP 的出站图（spec §5.2.2 的断言 A / B / C），返回违规描述。
// 它只读 p（同一张表），所以装配逻辑与断言不会各写一份、悄悄分叉。
func CheckWarpGraph(raw []byte, p WarpPolicy) ([]string, error) {
	var g graphJSON
	if err := json.Unmarshal(raw, &g); err != nil {
		return nil, err
	}
	nodes := map[string]map[string]any{}
	for _, o := range g.Outbounds {
		nodes[strVal(o["tag"])] = o
	}
	for _, e := range g.Endpoints {
		nodes[strVal(e["tag"])] = e
	}
	var v []string
	add := func(format string, args ...any) { v = append(v, fmt.Sprintf(format, args...)) }

	warpEp, ok := nodes[TagWarp]
	if !ok {
		add("启用了 WARP 但配置里没有 warp 端点")
		return v, nil
	}

	// 断言 C（两种模式共有）：warp 不是 select / auto 的成员；无环（悬空由 ValidateGraph 另管）。
	for _, grp := range []string{TagSelect, TagAuto} {
		if m, ok := nodes[grp]; ok && containsStr(toStrings(m["outbounds"]), TagWarp) {
			add("warp 不得是 %s 的成员（路径：%s -> warp -> ... -> %s）", grp, grp, grp)
		}
	}
	// 沿 detour 走一遍，返回路径与是否成环。
	chain := func(start string) (path []string, cyclic bool) {
		seen := map[string]bool{}
		for cur := start; cur != ""; cur = strVal(nodes[cur]["detour"]) {
			path = append(path, cur)
			if seen[cur] {
				return path, true
			}
			seen[cur] = true
			if _, ok := nodes[cur]; !ok {
				break // 预置出站或悬空：链到此为止
			}
		}
		return path, false
	}
	for tag := range nodes {
		if path, cyc := chain(tag); cyc {
			add("detour 成环：%s", strings.Join(path, " -> "))
		}
	}

	// 业务入口：route.final、目标不是直连类 / block 的路由规则、dns-remote.detour。
	var entries []string
	if g.Route.Final != "" {
		entries = append(entries, "route.final="+g.Route.Final)
	}
	for i, r := range g.Route.Rules {
		if out := strVal(r["outbound"]); out != "" && !directClass(out) && out != TagBlock {
			entries = append(entries, fmt.Sprintf("route.rules[%d]=%s", i, out))
		}
	}
	for _, s := range g.DNS.Servers {
		if strVal(s["tag"]) == TagDNSRemote {
			entries = append(entries, "dns-remote.detour="+strVal(s["detour"]))
		}
	}
	target := func(entry string) string { return entry[strings.LastIndex(entry, "=")+1:] }

	members := toStrings(nodes[TagSelect]["outbounds"])
	switch p.Mode {
	case options.WarpWarpOverProxy:
		// A：每个业务入口的第一跳是 warp。
		for _, e := range entries {
			if target(e) != TagWarp {
				add("%s 的第一跳应是 warp（业务流量不得不经 warp 直接出去）", e)
			}
		}
		// B：warp → select → 载体链；载体链允许以直连类终止，所以这里不查节点的链尾。
		if d := strVal(warpEp["detour"]); d != p.WarpDetour {
			add("warp.detour = %q，期望 %q", d, p.WarpDetour)
		}
	case options.WarpProxyOverWarp:
		for _, e := range entries {
			if target(e) == TagWarp {
				add("%s 不该指向 warp：本模式的业务出口是 %s", e, p.Egress)
			}
		}
		// A：select 的每个成员，拨号链的最后一跳是 warp。
		for _, m := range members {
			if m == TagAuto {
				continue
			}
			path, _ := chain(m)
			if len(path) == 0 || path[len(path)-1] != TagWarp {
				add("成员 %s 的拨号链未终止于 warp：%s", m, strings.Join(append(path, "(无)"), " -> "))
			}
			// B：链里没有直连类出站（已被替换为 warp）。
			for _, hop := range path {
				if directClass(hop) {
					add("成员 %s 的拨号链经过直连类出站 %s：%s", m, hop, strings.Join(path, " -> "))
				}
			}
		}
		// B：warp 自身无 detour。
		if d := strVal(warpEp["detour"]); d != p.WarpDetour {
			add("warp.detour = %q，期望无 detour", d)
		}
	}
	sort.Strings(v)
	return v, nil
}
