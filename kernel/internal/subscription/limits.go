package subscription

import (
	"gopkg.in/yaml.v3"
)

// 解析预算（spec §6.4）：订阅入口处理的是不可信的远程内容，输入、节点数、输出与嵌套深度都要有上界，
// 超出时以稳定码 `limit-exceeded:` 失败，不去尝试「尽量解析」。上界按真实订阅留足余量：
// 5000 个节点的 Clash YAML / sing-box JSON 约 2–5 MB，下列值是它的数倍。
const (
	// MaxInputBytes 是订阅文件（解码前）的字节上限。
	MaxInputBytes = 16 << 20
	// MaxNodes 是解析前的节点条目数上限（出站 + 端点 / Clash proxies / 链接行数）。
	MaxNodes = 20000
	// MaxOutputBytes 是写出的 {"outbounds","endpoints"} JSON 的字节上限。
	MaxOutputBytes = 32 << 20
	// MaxNestingDepth 是 JSON / YAML 的嵌套深度上限（真实节点最深约 6 层）。
	MaxNestingDepth = 100
	// MaxYAMLExpandedNodes 是 YAML 展开别名之后的节点总数上限，挡「别名炸弹」。
	MaxYAMLExpandedNodes = 2_000_000
)

// maxOutputBytes 是 MaxOutputBytes 的可替换副本（只给测试缩小用）。
var maxOutputBytes = MaxOutputBytes

// jsonDepthWithinLimit 在不解码的前提下扫一遍括号深度（跳过字符串里的括号）。
func jsonDepthWithinLimit(in []byte) bool {
	depth := 0
	inString, escaped := false, false
	for _, b := range in {
		if inString {
			switch {
			case escaped:
				escaped = false
			case b == '\\':
				escaped = true
			case b == '"':
				inString = false
			}
			continue
		}
		switch b {
		case '"':
			inString = true
		case '[', '{':
			depth++
			if depth > MaxNestingDepth {
				return false
			}
		case ']', '}':
			if depth > 0 {
				depth--
			}
		}
	}
	return true
}

// checkYAMLBudget 先解成 yaml.Node（不展开别名），在节点树上量深度与展开后的规模，通过了才允许真正解码。
// 语法错误按 format-unknown 报（与原来一致）；超限报 limit-exceeded。
func checkYAMLBudget(in []byte) error {
	var doc yaml.Node
	if err := yaml.Unmarshal(in, &doc); err != nil {
		return fail(CodeFormatUnknown, "invalid Clash YAML: %v", err)
	}
	type stat struct{ size, depth int }
	memo := map[*yaml.Node]stat{}
	inProgress := map[*yaml.Node]bool{}
	var walk func(n *yaml.Node) (stat, bool)
	walk = func(n *yaml.Node) (stat, bool) {
		if s, ok := memo[n]; ok {
			return s, true
		}
		if inProgress[n] {
			return stat{}, false // 别名指回自己的祖先：循环引用
		}
		inProgress[n] = true
		defer delete(inProgress, n)
		var s stat
		if n.Kind == yaml.AliasNode && n.Alias != nil {
			t, ok := walk(n.Alias)
			if !ok {
				return stat{}, false
			}
			s = stat{size: 1 + t.size, depth: 1 + t.depth}
		} else {
			s = stat{size: 1, depth: 1}
			for _, c := range n.Content {
				cs, ok := walk(c)
				if !ok {
					return stat{}, false
				}
				s.size += cs.size
				if cs.depth+1 > s.depth {
					s.depth = cs.depth + 1
				}
				if s.size > MaxYAMLExpandedNodes || s.depth > MaxNestingDepth {
					return s, true // 已经超限，不必继续展开
				}
			}
		}
		memo[n] = s
		return s, true
	}
	s, ok := walk(&doc)
	if !ok {
		return fail(CodeLimitExceeded, "the YAML has a cyclic alias reference")
	}
	if s.depth > MaxNestingDepth {
		return fail(CodeLimitExceeded, "the YAML is nested deeper than %d levels", MaxNestingDepth)
	}
	if s.size > MaxYAMLExpandedNodes {
		return fail(CodeLimitExceeded, "the YAML expands to more than %d nodes (alias bomb?)", MaxYAMLExpandedNodes)
	}
	return nil
}
