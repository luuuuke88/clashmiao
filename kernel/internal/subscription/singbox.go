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
	var top any
	if err := json.Unmarshal(clean, &top); err != nil {
		return Profile{}, nil, fail(CodeFormatUnknown, "invalid JSON: %v", err)
	}
	var outbounds, endpoints []map[string]any
	var warnings Warnings

	switch t := top.(type) {
	case []any:
		outbounds = objects(t, "outbounds", &warnings)
		if len(outbounds) == 0 {
			return Profile{}, warnings, fail(CodeNoOutbounds, "the JSON array has no outbound objects")
		}
	case map[string]any:
		_, hasOut := t["outbounds"]
		_, hasEP := t["endpoints"]
		switch {
		case hasOut || hasEP:
			outbounds = objects(asList(t["outbounds"]), "outbounds", &warnings)
			endpoints = objects(asList(t["endpoints"]), "endpoints", &warnings)
		case t["proxies"] != nil:
			return parseClash(clean)
		case isString(t["type"]):
			outbounds = []map[string]any{t}
		default:
			return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format (JSON object has no outbounds, endpoints, proxies or type)")
		}
	default:
		return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format")
	}

	res := legacy.Clean(outbounds, endpoints, legacy.CleanOptions{RemapTarget: "direct"})
	for _, w := range res.Warnings {
		warnings = append(warnings, w)
	}
	return finalize(res.Outbounds, res.Endpoints, warnings, "profile has no usable outbound")
}

func asList(x any) []any { l, _ := x.([]any); return l }

func isString(x any) bool { s, ok := x.(string); return ok && s != "" }

// objects 取数组里的对象；非对象的项记警告并跳过。
func objects(list []any, what string, w *Warnings) []map[string]any {
	var out []map[string]any
	for i, e := range list {
		if m, ok := e.(map[string]any); ok {
			out = append(out, m)
		} else {
			*w = append(*w, fmt.Sprintf("entry-skipped: %s[%d] is not an object", what, i))
		}
	}
	return out
}
