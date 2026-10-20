package build

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
)

// 类型化错误：调用方用 errors.Is 区分；消息都以 build-failed: 开头。
var (
	ErrDetourCycle    = errors.New("detour cycle")
	ErrDetourDangling = errors.New("dangling detour")
)

// presetDetourTargets 是订阅节点的 detour 允许指向的预置出站（warp 在 WARP 未启用时由 ValidateGraph 兜底拒绝）。
var presetDetourTargets = []string{TagDirect, TagDirectFragment, TagBypass, TagWarp}

// ValidateDetours 检查订阅节点与端点的 detour 链：所有模式都检查。
// 有效目标 = 剩余实体 ∪ 预置 direct / direct-fragment / bypass / warp；指向被丢弃的 selector / urltest / block / dns
// 或从未存在的 tag 都算悬空（指向订阅自带直连类的引用在归一化阶段已重映射，不会走到这里）。
func ValidateDetours(nodes []cfg.Outbound, endpoints []cfg.Endpoint) error {
	detour := map[string]string{}
	for _, n := range nodes {
		detour[n.Tag()] = strVal(n["detour"])
	}
	for _, e := range endpoints {
		detour[e.Tag()] = strVal(e["detour"])
	}
	valid := map[string]bool{}
	for tag := range detour {
		valid[tag] = true
	}
	for _, t := range presetDetourTargets {
		valid[t] = true
	}

	tags := make([]string, 0, len(detour))
	for t := range detour {
		tags = append(tags, t)
	}
	sort.Strings(tags)
	for _, tag := range tags {
		if d := detour[tag]; d != "" && !valid[d] {
			return fmt.Errorf("%s %w: %q detours to %q which does not exist", PrefixBuildFailed, ErrDetourDangling, tag, d)
		}
	}
	for _, start := range tags {
		path := []string{start}
		seen := map[string]bool{start: true}
		for cur := detour[start]; cur != ""; cur = detour[cur] {
			path = append(path, cur)
			if seen[cur] {
				return fmt.Errorf("%s %w: %s", PrefixBuildFailed, ErrDetourCycle, strings.Join(path, " -> "))
			}
			seen[cur] = true
			if _, ok := detour[cur]; !ok {
				break // 预置出站：链到此为止
			}
		}
	}
	return nil
}

func strVal(x any) string { s, _ := x.(string); return s }

// ValidateGraph 检查最终配置的标签图：tag 唯一、所有引用存在、selector default ∈ 成员、
// detour 无环、DNS / 路由引用的出站存在。U4 的不变量复用它；任何一条被破坏都返回 build-failed。
func ValidateGraph(c *cfg.Config) error {
	tags := map[string]map[string]any{}
	add := func(m map[string]any) error {
		tag := strVal(m["tag"])
		if tag == "" {
			return fmt.Errorf("%s an outbound or endpoint has no tag", PrefixBuildFailed)
		}
		if _, dup := tags[tag]; dup {
			return fmt.Errorf("%s duplicate tag %q", PrefixBuildFailed, tag)
		}
		tags[tag] = m
		return nil
	}
	for _, o := range c.Outbounds {
		if err := add(o); err != nil {
			return err
		}
	}
	for _, e := range c.Endpoints {
		if err := add(e); err != nil {
			return err
		}
	}
	names := make([]string, 0, len(tags))
	for t := range tags {
		names = append(names, t)
	}
	sort.Strings(names)

	for _, tag := range names {
		m := tags[tag]
		if t := strVal(m["type"]); t == "selector" || t == "urltest" {
			members := toStrings(m["outbounds"])
			for _, mem := range members {
				if _, ok := tags[mem]; !ok {
					return fmt.Errorf("%s %s has member %q which does not exist", PrefixBuildFailed, tag, mem)
				}
			}
			if t == "selector" {
				if def := strVal(m["default"]); def != "" && !containsStr(members, def) {
					return fmt.Errorf("%s selector %s default %q is not a member", PrefixBuildFailed, tag, def)
				}
			}
		}
		if d := strVal(m["detour"]); d != "" {
			target, ok := tags[d]
			if !ok {
				return fmt.Errorf("%s %w: %q detours to %q which does not exist", PrefixBuildFailed, ErrDetourDangling, tag, d)
			}
			// 出站 / 端点的 detour 指向空 direct 同样在启动时被拒绝（CheckConfig 放行）。
			if isEmptyDirectOutbound(target) {
				return fmt.Errorf("%s %q detours to the empty direct outbound %q (rejected at start)", PrefixBuildFailed, tag, d)
			}
		}
	}
	for _, start := range names {
		seen := map[string]bool{start: true}
		path := []string{start}
		for cur := strVal(tags[start]["detour"]); cur != ""; cur = strVal(tags[cur]["detour"]) {
			path = append(path, cur)
			if seen[cur] {
				return fmt.Errorf("%s %w: %s", PrefixBuildFailed, ErrDetourCycle, strings.Join(path, " -> "))
			}
			seen[cur] = true
		}
	}
	if c.Route != nil {
		if c.Route.Final != "" {
			if _, ok := tags[c.Route.Final]; !ok {
				return fmt.Errorf("%s route.final %q does not exist", PrefixBuildFailed, c.Route.Final)
			}
		}
		for i, r := range c.Route.Rules {
			if r.Outbound != "" {
				if _, ok := tags[r.Outbound]; !ok {
					return fmt.Errorf("%s route.rules[%d] outbound %q does not exist", PrefixBuildFailed, i, r.Outbound)
				}
			}
		}
	}
	if c.DNS != nil {
		for _, s := range c.DNS.Servers {
			if s.Detour != "" {
				target, ok := tags[s.Detour]
				if !ok {
					return fmt.Errorf("%s dns server %s detours to %q which does not exist", PrefixBuildFailed, s.Tag, s.Detour)
				}
				// 空 direct（只有 type / tag）作 detour 目标：CheckConfig 放行、Start 拒绝。
				if isEmptyDirectOutbound(target) {
					return fmt.Errorf("%s dns server %s detours to the empty direct outbound %q (rejected at start)", PrefixBuildFailed, s.Tag, s.Detour)
				}
			}
		}
	}
	return nil
}

func isEmptyDirectOutbound(m map[string]any) bool {
	if strVal(m["type"]) != "direct" {
		return false
	}
	for k, v := range m {
		if k == "type" || k == "tag" {
			continue
		}
		switch t := v.(type) {
		case nil:
		case bool:
			if t {
				return false
			}
		case string:
			if t != "" {
				return false
			}
		case float64:
			if t != 0 {
				return false
			}
		case int:
			if t != 0 {
				return false
			}
		default:
			return false
		}
	}
	return true
}

func toStrings(x any) []string {
	switch t := x.(type) {
	case []string:
		return t
	case []any:
		var out []string
		for _, e := range t {
			if s, ok := e.(string); ok {
				out = append(out, s)
			}
		}
		return out
	}
	return nil
}

func containsStr(list []string, s string) bool {
	for _, e := range list {
		if e == s {
			return true
		}
	}
	return false
}
