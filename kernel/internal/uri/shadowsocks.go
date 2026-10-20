package uri

import (
	"net"
	"strconv"
	"strings"
)

func init() { Register("ss", convertShadowsocks) }

// convertShadowsocks 认三种写法：
//
//	SIP002：ss://base64url(method:password)@host:port[/][?plugin=…]#name
//	明文  ：ss://method:password@host:port#name（password 做了 percent 编码，2022 系列加密常用）
//	旧式  ：ss://base64(method:password@host:port)#name（整体 base64）
//
// host 可以是方括号包起来的 IPv6。plugin 只支持 sing-box 内置的 obfs-local（simple-obfs）与 v2ray-plugin，其余报 uri-invalid。
func convertShadowsocks(line string) (Entity, error) {
	rest := line[len("ss://"):]
	name := ""
	if i := strings.Index(rest, "#"); i >= 0 {
		name, rest = unescape(rest[i+1:]), rest[:i]
	}
	var userinfo, hostPart string
	if at := strings.LastIndex(rest, "@"); at >= 0 {
		userinfo, hostPart = rest[:at], rest[at+1:]
	} else {
		// 旧式：整体 base64（可能后面还跟 ?plugin=…，先切掉再解）。
		payload, query, _ := strings.Cut(rest, "?")
		dec, err := decodeB64(strings.TrimSuffix(payload, "/"))
		if err != nil {
			return Entity{}, invalidf("ss", "payload is neither SIP002 nor base64")
		}
		at := strings.LastIndex(string(dec), "@")
		if at < 0 {
			return Entity{}, invalidf("ss", "decoded payload has no @")
		}
		userinfo, hostPart = string(dec[:at]), string(dec[at+1:])
		if query != "" {
			hostPart += "?" + query
		}
		return buildSS(userinfo, hostPart, name, true)
	}
	return buildSS(userinfo, hostPart, name, false)
}

func buildSS(userinfo, hostPart, name string, userinfoIsPlain bool) (Entity, error) {
	var method, password string
	if userinfoIsPlain || strings.Contains(userinfo, ":") {
		m, pw, ok := strings.Cut(userinfo, ":")
		if !ok {
			return Entity{}, invalidf("ss", "userinfo is not method:password")
		}
		method, password = unescape(m), unescape(pw)
	} else {
		dec, err := decodeB64(unescape(userinfo))
		if err != nil {
			return Entity{}, invalidf("ss", "userinfo is not base64")
		}
		m, pw, ok := strings.Cut(string(dec), ":")
		if !ok {
			return Entity{}, invalidf("ss", "userinfo is not method:password")
		}
		method, password = m, pw
	}
	if method == "" {
		return Entity{}, invalidf("ss", "missing method")
	}

	authority, query, _ := strings.Cut(hostPart, "?")
	authority = strings.TrimSuffix(authority, "/")
	host, portStr, err := net.SplitHostPort(authority)
	if err != nil {
		return Entity{}, invalidf("ss", "bad host:port %q", authority)
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port < 1 || port > 65535 || host == "" {
		return Entity{}, invalidf("ss", "bad host or port")
	}
	if name == "" {
		name = defaultTag(host, port)
	}
	out := base("shadowsocks", name, host, port)
	out["method"] = method
	out["password"] = password

	if plugin := parseParams(query).get("plugin"); plugin != "" {
		pl, opts, _ := strings.Cut(plugin, ";")
		switch strings.ToLower(pl) {
		case "obfs-local", "simple-obfs":
			pl = "obfs-local"
		case "v2ray-plugin":
		default:
			return Entity{}, invalidf("ss", "unsupported plugin %q", pl)
		}
		out["plugin"] = pl
		if opts != "" {
			out["plugin_opts"] = opts
		}
	}
	return Entity{Map: out}, nil
}
