package subscription

import (
	"encoding/json"
	"fmt"

	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
)

// parseJSON：sing-box JSON（容忍注释）。
//
//	对象含 outbounds / endpoints：取这两项；
//	对象含 proxies：它是 Clash 的 JSON 写法，交给 Clash 路径；
//	对象带 type：当作单个出站；
//	数组：每项当作一个出站（旧实现里这一支有类型断言 bug，会漏掉数组形式）。
//
// 随后过 legacy.Clean（RemapTarget = direct）；清洗后没有叶子节点 → no-outbounds。
func parseJSON(in []byte) (Profile, Warnings, error) {
	clean := stripJSONComments(in)
	if !jsonDepthWithinLimit(clean) {
		return Profile{}, nil, fail(CodeLimitExceeded, "the JSON is nested deeper than %d levels", MaxNestingDepth)
	}
	var top any
	if err := json.Unmarshal(clean, &top); err != nil {
		return Profile{}, nil, fail(CodeFormatUnknown, "invalid JSON: %v", err)
	}
	var outbounds, endpoints []map[string]any
	var warnings Warnings

	switch t := top.(type) {
	case []any:
		outbounds = objects(t, "outbounds", &warnings, false)
		if len(outbounds) == 0 {
			return Profile{}, warnings, fail(CodeNoOutbounds, "the JSON array has no usable outbound objects")
		}
	case map[string]any:
		_, hasOut := t["outbounds"]
		_, hasEP := t["endpoints"]
		switch {
		case hasOut || hasEP:
			outbounds = objects(asList(t["outbounds"]), "outbounds", &warnings, false)
			endpoints = objects(asList(t["endpoints"]), "endpoints", &warnings, true)
		case t["proxies"] != nil:
			return parseClash(clean)
		case isString(t["type"]):
			outbounds = objects([]any{t}, "outbounds", &warnings, false)
		default:
			return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format (JSON object has no outbounds, endpoints, proxies or type)")
		}
	default:
		return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format")
	}

	if n := len(outbounds) + len(endpoints); n > MaxNodes {
		return Profile{}, warnings, fail(CodeLimitExceeded, "the JSON has %d nodes, more than the limit %d", n, MaxNodes)
	}
	res := legacy.Clean(outbounds, endpoints, legacy.CleanOptions{RemapTarget: "direct"})
	for _, w := range res.Warnings {
		warnings = append(warnings, w)
	}
	return finalize(res.Outbounds, res.Endpoints, warnings, "profile has no usable outbound")
}

func asList(x any) []any { l, _ := x.([]any); return l }

func isString(x any) bool { s, ok := x.(string); return ok && s != "" }

// objects 取数组里的对象：非对象的项、基本字段 / 值域不合格的节点都记警告并跳过（单节点失败隔离），
// 合格的原样保留（含未知字段）。全部被跳过时由调用方按 no-outbounds 报错。
func objects(list []any, what string, w *Warnings, endpoint bool) []map[string]any {
	var out []map[string]any
	for i, e := range list {
		m, ok := e.(map[string]any)
		if !ok {
			*w = append(*w, fmt.Sprintf("entry-skipped: %s[%d] is not an object", what, i))
			continue
		}
		if reason := validateNode(m, endpoint); reason != "" {
			*w = append(*w, fmt.Sprintf("node-skipped: %s[%d]: %s", what, i, reason))
			continue
		}
		out = append(out, m)
	}
	return out
}
