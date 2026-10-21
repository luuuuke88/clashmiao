package build

import (
	"fmt"
	"sort"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 预置 / 保留 tag（旧内核的隐式契约，Kotlin / Dart 的测试也依赖它们）。
const (
	TagSelect         = "select"
	TagAuto           = "auto"
	TagDirect         = "direct"
	TagDirectFragment = "direct-fragment"
	TagBypass         = "bypass"
	TagBlock          = "block" // 不再生成 block 出站，但 tag 仍保留，订阅节点不得占用
	TagWarp           = "warp"  // 内部 WARP 端点（U13）
)

// 订阅节点里的标记（Dart 侧约定）。
const (
	hideMarker    = "§hide§"
	defaultMarker = "§default§"
)

var reservedTags = map[string]bool{
	TagSelect: true, TagAuto: true, TagDirect: true, TagDirectFragment: true,
	TagBypass: true, TagBlock: true, TagWarp: true,
}

// ReservedTags 返回预置 / 保留 tag 清单（测试用：钉住它与 legacy.ReservedTags 一致）。
func ReservedTags() []string {
	out := make([]string, 0, len(reservedTags))
	for t := range reservedTags {
		out = append(out, t)
	}
	sort.Strings(out)
	return out
}

// droppedType：订阅自带的分组 / 直连 / 屏蔽 / dns 出站一律丢弃（与 Dart 的 isCandidateLeafType 同一口径）。
func droppedType(t string) bool {
	switch strings.ToLower(strings.NewReplacer("-", "", "_", "").Replace(strings.TrimSpace(t))) {
	case "direct", "block", "dns", "selector", "select", "urltest", "custom":
		return true
	}
	return false
}

// assembled 是出站装配的结果。
type assembled struct {
	Outbounds []cfg.Outbound
	Endpoints []cfg.Endpoint
	// Entities 是订阅节点与订阅端点（不含预置出站与 warp），按配置顺序；DNS 直连域名与 mux / 分片都只看它们。
	Entities []map[string]any
}

// assembleOutbounds 装配出站（spec §5.2）：
//
//	select = [auto, …非隐藏订阅节点, …非隐藏订阅端点]，默认 = 含 §default§ 的节点 / 端点的真实 tag，否则 auto；
//	auto   = urltest，成员同 select 去掉 auto；
//	预置   = direct、direct-fragment、bypass。
//
// 没有可用节点（出站与端点都为空，或只剩隐藏节点）→ `no-outbounds:`。端点独占的订阅合法。
func assembleOutbounds(p Profile, o *options.Options, warnings *[]string) (*assembled, error) {
	nodes, endpoints, err := normalizeEntities(p, !warpTerminates(o), warnings)
	if err != nil {
		return nil, err
	}
	if len(nodes)+len(endpoints) == 0 {
		return nil, fmt.Errorf("%s profile has no usable outbound", PrefixNoOutbounds)
	}
	if err := ValidateDetours(nodes, endpoints); err != nil {
		return nil, err
	}

	applyTLSTricks(o, nodes, warnings)
	applyMux(o, nodes)

	var members []string
	def := ""
	note := func(tag string) {
		if strings.Contains(tag, hideMarker) {
			return
		}
		members = append(members, tag)
		if def == "" && strings.Contains(tag, defaultMarker) {
			def = tag
		}
	}
	for _, n := range nodes {
		note(n.Tag())
	}
	for _, e := range endpoints {
		note(e.Tag())
	}
	if len(members) == 0 {
		return nil, fmt.Errorf("%s profile has no usable outbound (every node is hidden)", PrefixNoOutbounds)
	}
	if def == "" {
		def = TagAuto
	}

	out := &assembled{}
	out.Outbounds = append(out.Outbounds,
		cfg.Outbound{"type": "selector", "tag": TagSelect, "outbounds": append([]string{TagAuto}, members...), "default": def},
		cfg.Outbound{"type": "urltest", "tag": TagAuto, "outbounds": members, "url": o.ConnectionTestURL,
			"interval": fmt.Sprintf("%ds", o.URLTestInterval), "idle_timeout": fmt.Sprintf("%ds", o.URLTestInterval*10)},
	)
	out.Outbounds = append(out.Outbounds, nodes...)
	out.Outbounds = append(out.Outbounds,
		cfg.Outbound{"type": "direct", "tag": TagDirect},
		// 带一个选项：空 direct 作 detour 目标会被 Start 拒绝；udp_fragment 是无副作用的非空选项。
		cfg.Outbound{"type": "direct", "tag": TagDirectFragment, "udp_fragment": true},
		cfg.Outbound{"type": "direct", "tag": TagBypass},
	)
	out.Endpoints = endpoints
	for _, n := range nodes {
		out.Entities = append(out.Entities, n)
	}
	for _, e := range endpoints {
		out.Entities = append(out.Entities, e)
	}
	return out, nil
}

// normalizeEntities 丢弃订阅自带的分组 / 直连类，给与预置 tag 冲突或重复的节点改名，并同步改写别的节点对它的 detour 引用。
func normalizeEntities(p Profile, dropEmptyDirectDetour bool, warnings *[]string) ([]cfg.Outbound, []cfg.Endpoint, error) {
	type item struct {
		m        map[string]any
		endpoint bool
	}
	var items []item
	for _, n := range p.Outbounds {
		if t, _ := n["type"].(string); droppedType(t) {
			continue
		}
		items = append(items, item{m: copyMap(n)})
	}
	for _, e := range p.Endpoints {
		items = append(items, item{m: copyMap(e), endpoint: true})
	}

	used := map[string]bool{}
	for t := range reservedTags {
		used[t] = true
	}
	// 订阅里原有的 tag 先全部占位，改名时不会撞上后面的节点。
	original := map[string]int{}
	for _, it := range items {
		original[tagOf(it.m)]++
	}
	unique := func(base string) string {
		for i := 2; ; i++ {
			cand := fmt.Sprintf("%s (%d)", base, i)
			if !used[cand] && original[cand] == 0 {
				return cand
			}
		}
	}

	reservedRename := map[string]string{} // 与预置 tag 冲突 → 新名字（别的节点对它的引用同步改写）
	seen := map[string]bool{}
	for i := range items {
		tag := tagOf(items[i].m)
		switch {
		case tag == "":
			return nil, nil, fmt.Errorf("%s a node has no tag", PrefixBuildFailed)
		case reservedTags[tag]:
			nt := unique(tag)
			reservedRename[tag] = nt
			used[nt] = true
			seen[nt] = true
			items[i].m["tag"] = nt
			*warnings = append(*warnings, fmt.Sprintf("tag-renamed: %q conflicts with a built-in tag, renamed to %q", tag, nt))
		case seen[tag]:
			nt := unique(tag)
			used[nt] = true
			seen[nt] = true
			items[i].m["tag"] = nt
			*warnings = append(*warnings, fmt.Sprintf("tag-renamed: duplicate tag %q renamed to %q", tag, nt))
		default:
			seen[tag] = true
			used[tag] = true
		}
	}
	if len(reservedRename) > 0 {
		for _, it := range items {
			if d, _ := it.m["detour"].(string); d != "" {
				if nt, ok := reservedRename[d]; ok {
					it.m["detour"] = nt
				}
			}
		}
	}

	// detour 指向预置的空 direct（direct / bypass）等价于没有 detour，而新内核在启动时拒绝「detour 指向空 direct」
	// （CheckConfig 放行）。旧订阅清洗后常有这种引用（订阅自带的 direct 被丢弃后重映射到 direct），这里去掉它。
	// direct-fragment 带选项，不是空 direct，保留。
	// proxy_over_warp 例外：那里整条链都要改写到 warp，指向预置直连类的 detour 由 RedirectToWarp 替换并记 warning。
	if dropEmptyDirectDetour {
		for _, it := range items {
			if d, _ := it.m["detour"].(string); d == TagDirect || d == TagBypass {
				delete(it.m, "detour")
			}
		}
	}

	var nodes []cfg.Outbound
	var endpoints []cfg.Endpoint
	for _, it := range items {
		if it.endpoint {
			endpoints = append(endpoints, cfg.Endpoint(it.m))
		} else {
			nodes = append(nodes, cfg.Outbound(it.m))
		}
	}
	return nodes, endpoints, nil
}

func tagOf(m map[string]any) string { s, _ := m["tag"].(string); return s }

// copyMap 做一层深拷贝（节点里有嵌套 map / slice；我们要改 tls / multiplex，不能改到调用方的 profile）。
func copyMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = copyValue(v)
	}
	return out
}

func copyValue(v any) any {
	switch t := v.(type) {
	case map[string]any:
		return copyMap(t)
	case []any:
		out := make([]any, len(t))
		for i, e := range t {
			out[i] = copyValue(e)
		}
		return out
	}
	return v
}
