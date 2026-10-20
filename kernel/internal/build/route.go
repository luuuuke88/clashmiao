package build

import (
	"fmt"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// BuildRoute 生成 route 块（spec §3.4 第 7 行、§5.2）。
//
// 规则顺序固定：
//
//	sniff → [resolve] → protocol:dns → hijack-dns → inbound:dns-in → hijack-dns → port:53 → hijack-dns
//	→ bypass-lan（ip_is_private → bypass）→ 用户规则 → final
//
// sniff 必须在 hijack-dns 之前（hijack-dns 靠嗅探出的协议命中）；resolve 只在 resolve-destination 为真时出现。
// default_domain_resolver 带上 ipv6-mode 作 strategy：出站拨号域名时才会按它排序候选地址。
// final 与 proxy 规则的目标都取同一个 egress 变量（常态 select；warp_over_proxy 时是 warp，由 U13 注入），
// 所以两处不会分叉。block-ads 不生成任何规则集（不引用远程资源），只给警告。
func BuildRoute(o *options.Options, env Env, egress string, warnings *[]string) (*cfg.Route, error) {
	if egress == "" {
		return nil, fmt.Errorf("%s route: empty egress", PrefixBuildFailed)
	}
	rules := []cfg.RouteRule{{Action: "sniff"}}
	if o.ResolveDestination {
		rules = append(rules, cfg.RouteRule{Action: "resolve", Strategy: o.IPv6Mode})
	}
	rules = append(rules, cfg.RouteRule{Protocol: []string{"dns"}, Action: "hijack-dns"})
	if o.LocalDNSPort != 0 {
		rules = append(rules, cfg.RouteRule{Inbound: []string{TagDNSIn}, Action: "hijack-dns"})
	}
	rules = append(rules, cfg.RouteRule{Port: []uint16{53}, Action: "hijack-dns"})

	if o.BypassLAN {
		rules = append(rules, cfg.RouteRule{IPIsPrivate: true, Action: "route", Outbound: TagBypass})
	}

	for i, r := range o.Rules {
		rule, ok, err := userRule(r, egress)
		if err != nil {
			return nil, wrapRuleError(i, err)
		}
		if !ok {
			*warnings = append(*warnings, fmt.Sprintf("rule-empty: rules[%d] has no matchers and was ignored", i))
			continue
		}
		rules = append(rules, rule)
	}

	if o.BlockAds {
		*warnings = append(*warnings, "block-ads-unsupported: no ad rule sets are bundled, block-ads has no effect")
	}

	return &cfg.Route{
		Rules:                 rules,
		Final:                 egress,
		AutoDetectInterface:   true,
		OverrideAndroidVPN:    env.GOOS == "android",
		DefaultDomainResolver: &cfg.DomainResolver{Server: TagDNSDirect, Strategy: o.IPv6Mode},
	}, nil
}

// wrapRuleError 给规则错误加上下标；选项错误保持 option-invalid 前缀。
func wrapRuleError(i int, err error) error {
	if oe, ok := err.(*options.Error); ok {
		return &options.Error{Msg: fmt.Sprintf("rules[%d]: %s", i, oe.Msg)}
	}
	return err
}
