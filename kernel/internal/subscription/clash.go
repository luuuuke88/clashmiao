package subscription

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/xmdhs/clash2singbox/convert"
	"github.com/xmdhs/clash2singbox/model"
	"github.com/xmdhs/clash2singbox/model/clash"
	"gopkg.in/yaml.v3"

	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
)

// parseClash：Clash YAML 交给 clash2singbox（MIT，纯转换库，不依赖 sing-box；不引入它的 Patch 模板）。
// proxy-groups 与 rules 一律忽略（构建器重建分组与路由；分组在转换前就去掉，relay 不会被展开成额外节点）；单个节点失败只记警告，全部失败才报错并带首个原因。
func parseClash(in []byte) (Profile, Warnings, error) {
	if err := checkYAMLBudget(in); err != nil {
		return Profile{}, nil, err
	}
	var c clash.Clash
	if err := yaml.Unmarshal(in, &c); err != nil {
		return Profile{}, nil, fail(CodeFormatUnknown, "invalid Clash YAML: %v", err)
	}
	if len(c.Proxies) == 0 {
		return Profile{}, nil, fail(CodeNoOutbounds, "the Clash config has no proxies")
	}
	if len(c.Proxies) > MaxNodes {
		return Profile{}, nil, fail(CodeLimitExceeded, "the Clash config has %d proxies, more than the limit %d", len(c.Proxies), MaxNodes)
	}
	// 订阅自带的分组一律不要（构建器重建分组）：Clash2sing 会把 relay 分组展开成额外代理与 detour 链，
	// 它们会混进候选节点，所以转换之前就去掉。
	c.ProxyGroup = nil
	outs, eps, err := convert.Clash2sing(c, model.SINGLATEST)

	var warnings Warnings
	var firstReason string
	for _, e := range unwrapAll(err) {
		if firstReason == "" {
			firstReason = e.Error()
		}
		warnings = append(warnings, "node-skipped: "+e.Error())
	}

	outbounds, err1 := toMaps(outs)
	var endpointMaps []map[string]any
	var err2 error
	if err1 == nil {
		endpointMaps, err2 = toMaps(eps)
	}
	if err1 != nil || err2 != nil {
		return Profile{}, warnings, fail(CodeBuildFailed, "convert result: %v", errors.Join(err1, err2))
	}

	res := legacy.Clean(outbounds, endpointMaps, legacy.CleanOptions{RemapTarget: "direct"})
	warnings = append(warnings, res.Warnings...)
	reason := fmt.Sprintf("none of the %d proxies could be converted", len(c.Proxies))
	if firstReason != "" {
		reason += ": " + firstReason
	}
	return finalize(res.Outbounds, res.Endpoints, warnings, reason)
}

// unwrapAll 把 errors.Join 的结果拆成逐个节点的错误。
func unwrapAll(err error) []error {
	if err == nil {
		return nil
	}
	if j, ok := err.(interface{ Unwrap() []error }); ok {
		return j.Unwrap()
	}
	return []error{err}
}

// toMaps 经 JSON 往返把类型化的节点变成 map（保留库写出的全部字段，不替它猜）。
func toMaps(v any) ([]map[string]any, error) {
	raw, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	var out []map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	return out, nil
}
