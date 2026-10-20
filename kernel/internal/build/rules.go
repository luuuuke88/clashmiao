package build

import (
	"fmt"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// userRule 把一条用户规则（选项里的 rules[i]）翻译成路由规则。
//
//	bypass → 路由到 bypass 出站（直连，且是带名字的 direct）
//	block  → action: reject
//	proxy  → 路由到业务出口 egress（常态 select；warp_over_proxy 为 warp）
//
// 返回 ok=false 表示这条规则没有任何匹配项（只有目标）：直接生成会变成「匹配一切」，
// 所以丢弃并由调用方给出警告。匹配项之间是「与」的关系（sing-box 语义）：同一条规则里写了域名又写了 IP，
// 要两者同时满足才命中——智能分流注入的规则是各自独立的两条，不受影响。
func userRule(r options.Rule, egress string) (rule cfg.RouteRule, ok bool, err error) {
	m, err := r.Matchers()
	if err != nil {
		return cfg.RouteRule{}, false, err
	}
	if m.Empty() {
		return cfg.RouteRule{}, false, nil
	}
	rule = cfg.RouteRule{
		Domain: m.Domain, DomainSuffix: m.DomainSuffix, DomainRegex: m.DomainRegex, DomainKeyword: m.DomainKeyword,
		IPCIDR: m.IPCIDR, Port: m.Port, PortRange: m.PortRange, Network: m.Network, Protocol: m.Protocol,
	}
	switch r.Target() {
	case options.TargetBypass:
		rule.Action, rule.Outbound = "route", TagBypass
	case options.TargetBlock:
		rule.Action = "reject"
	case options.TargetProxy:
		rule.Action, rule.Outbound = "route", egress
	default:
		return cfg.RouteRule{}, false, fmt.Errorf("%s unreachable rule target %q", PrefixBuildFailed, r.Target())
	}
	return rule, true, nil
}
