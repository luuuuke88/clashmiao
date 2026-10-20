package uri

import "strings"

// tlsFor 按链接参数生成 sing-box 的 tls 块。
//
//	security=tls|reality|none；sni（回落 peer / servername / host / 服务器地址）、alpn、fp（utls 指纹）、
//	allowInsecure / insecure、reality 的 pbk / sid。
//
// defaultOn 为真（如 trojan）时没写 security 也启用 TLS。返回 nil 表示不启用。
// 不认识的 security 值（xtls 等）报 uri-invalid，不静默降级成明文。
func tlsFor(scheme string, p params, server string, defaultOn bool) (map[string]any, error) {
	security := strings.ToLower(p.get("security"))
	switch security {
	case "":
		if !defaultOn {
			return nil, nil
		}
		security = "tls"
	case "none":
		return nil, nil
	case "tls", "reality":
	default:
		return nil, invalidf(scheme, "unsupported security %q", security)
	}
	return buildTLS(scheme, p, server, security == "reality")
}

// buildTLS 生成启用状态的 tls 块。
func buildTLS(scheme string, p params, server string, reality bool) (map[string]any, error) {
	tls := map[string]any{"enabled": true}
	sni := p.get("sni", "peer", "servername")
	if sni == "" {
		sni = p.get("host")
	}
	if sni == "" {
		sni = server
	}
	if sni != "" {
		tls["server_name"] = sni
	}
	if alpn := splitList(p.get("alpn")); len(alpn) > 0 {
		tls["alpn"] = toAnyList(alpn)
	}
	if p.truthy("allowInsecure", "insecure", "allow_insecure", "skip-cert-verify") {
		tls["insecure"] = true
	}
	fp := p.get("fp", "fingerprint", "client-fingerprint")
	if reality {
		pbk := p.get("pbk", "public-key", "publickey")
		if pbk == "" {
			return nil, invalidf(scheme, "reality needs pbk (public key)")
		}
		if fp == "" {
			fp = "chrome" // reality 必须有 utls
		}
		r := map[string]any{"enabled": true, "public_key": pbk}
		if sid := p.get("sid", "short-id", "shortid"); sid != "" {
			r["short_id"] = sid
		}
		tls["reality"] = r
	}
	if fp != "" && fp != "none" {
		tls["utls"] = map[string]any{"enabled": true, "fingerprint": fp}
	}
	return tls, nil
}

func toAnyList(in []string) []any {
	out := make([]any, len(in))
	for i, s := range in {
		out[i] = s
	}
	return out
}
