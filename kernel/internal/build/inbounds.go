package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 入站与 DNS 相关的固定 tag（旧内核的隐式契约，Kotlin / Dart 的测试也依赖它们）。
const (
	TagTunIn   = "tun-in"
	TagMixedIn = "mixed-in"
	TagDNSIn   = "dns-in"
)

const (
	tunAddressV4 = "172.19.0.1/28"
	tunAddressV6 = "fdfe:dcba:9876::1/126"
)

// buildInbounds 生成 tun-in / mixed-in / dns-in。
//
//   - tun-in 仅 enable-tun 时生成；「仅线路」模式没有 tun-in，也就不会有任何引用它的东西；
//   - IPv6 开关控制 TUN 的 address 与监听地址族；
//   - allow-connection-from-lan 控制 mixed-in / dns-in 的监听地址；
//   - 不再写 sniff / domain_strategy（1.13 起入站上的这些字段已移除，嗅探改为路由动作）。
func buildInbounds(o *options.Options, env Env) []cfg.Inbound {
	v6 := ipv6Enabled(o, env)
	var inbounds []cfg.Inbound

	if o.EnableTun {
		addr := []string{tunAddressV4}
		if v6 {
			addr = append(addr, tunAddressV6)
		}
		tun := cfg.Inbound{
			Type:        "tun",
			Tag:         TagTunIn,
			Address:     addr,
			MTU:         o.MTU,
			AutoRoute:   true,
			StrictRoute: o.StrictRoute,
			Stack:       o.TunImplementation,
		}
		// endpoint-independent NAT 只有带用户态协议栈的实现支持（system 栈不支持）。
		if o.TunImplementation != "system" {
			tun.EndpointIndependentNAT = true
		}
		inbounds = append(inbounds, tun)
	}

	listen := "127.0.0.1"
	if o.AllowConnectionFromLAN {
		listen = "0.0.0.0"
		if v6 {
			listen = "::"
		}
	}
	inbounds = append(inbounds, cfg.Inbound{Type: "mixed", Tag: TagMixedIn, Listen: listen, ListenPort: o.MixedPort})

	if o.LocalDNSPort != 0 {
		inbounds = append(inbounds, cfg.Inbound{Type: "direct", Tag: TagDNSIn, Listen: listen, ListenPort: o.LocalDNSPort})
	}
	return inbounds
}
