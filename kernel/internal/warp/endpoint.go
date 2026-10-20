package warp

import (
	"fmt"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

const (
	// Tag 是 WARP 端点的固定 tag（保留 tag：订阅节点重名会被重命名）。
	Tag = "warp"

	// DefaultEntry 是默认的 Cloudflare WARP 入口：写成 IP，免去解析域名这一步
	// （engage.cloudflareclient.com 在部分网络里解析不稳定）。
	DefaultEntry     = "162.159.192.1"
	DefaultEntryPort = 2408

	mtuDirect  = 1330 // 直连拨对端时的 MTU（旧行为）
	mtuDetour  = 1280 // 对端拨号要再套一层代理时，留出外层开销（旧行为的 1330 - 50）
	cleanIPAut = "auto"
)

// Endpoint 生成内部 WARP 端点（type: wireguard，tag: warp）。
//
//	address        = 本地 v4/24（+ v6/128）
//	peers[0]       = 对端：clean-ip / clean-port（缺省用默认入口）、公钥、allowed_ips 全放行、reserved ← client-id 前 3 字节
//	mtu            = 直连 1330；有 detour（warp_over_proxy，对端的 UDP 要经所选节点）1280
//
// detour 非空时写入端点的 detour（外层 UDP 的拨号链）。噪声选项不生效，由调用方（装配层）给 warning。
func Endpoint(c WireguardConfig, o options.Warp, detour string) (map[string]any, error) {
	v4, err := prefixOf(c.LocalAddressIPv4, 4, 24)
	if err != nil {
		return nil, configError("local-address-ipv4: %v", err)
	}
	addrs := []any{v4}
	if c.LocalAddressIPv6 != "" {
		v6, err := prefixOf(c.LocalAddressIPv6, 6, 128)
		if err != nil {
			return nil, configError("local-address-ipv6: %v", err)
		}
		addrs = append(addrs, v6)
	}
	reserved, err := c.Reserved()
	if err != nil {
		return nil, configError("client-id: %v", err)
	}

	host, port := entry(o)
	peer := map[string]any{
		"address":     host,
		"port":        port,
		"public_key":  c.PeerPublicKey,
		"allowed_ips": []any{"0.0.0.0/0", "::/0"},
	}
	if reserved != nil {
		r := make([]any, len(reserved))
		for i, b := range reserved {
			r[i] = b
		}
		peer["reserved"] = r
	}

	mtu := mtuDirect
	if detour != "" {
		mtu = mtuDetour
	}
	ep := map[string]any{
		"type":        "wireguard",
		"tag":         Tag,
		"address":     addrs,
		"private_key": c.PrivateKey,
		"mtu":         mtu,
		"peers":       []any{peer},
	}
	if detour != "" {
		ep["detour"] = detour
	}
	return ep, nil
}

// entry 解析对端入口：clean-ip 为空 / auto 用默认入口；clean-port 为 0 用默认端口。
func entry(o options.Warp) (string, int) {
	host := strings.TrimSpace(o.CleanIP)
	if host == "" || strings.EqualFold(host, cleanIPAut) {
		host = DefaultEntry
	}
	port := o.CleanPort
	if port == 0 {
		port = DefaultEntryPort
	}
	return host, port
}

// NoiseWarnings 返回「噪声选项被忽略」的警告：只在值偏离默认时给（默认值每次都吵没有意义）；顺序固定。
func NoiseWarnings(o, def options.Warp) []string {
	var out []string
	for _, f := range []struct{ name, got, def string }{
		{"noise", o.Noise, def.Noise},
		{"noise-size", o.NoiseSize, def.NoiseSize},
		{"noise-delay", o.NoiseDelay, def.NoiseDelay},
		{"noise-mode", o.NoiseMode, def.NoiseMode},
	} {
		if f.got != f.def {
			out = append(out, fmt.Sprintf("warp-noise-unsupported: warp.%s=%q has no effect (the official kernel has no WARP noise)", f.name, f.got))
		}
	}
	return out
}
