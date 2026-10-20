package uri

import (
	"encoding/base64"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// 这是 U9 用来跑通订阅管线的最小 ss:// 实现（SIP002，userinfo 为 base64(method:password) 或明文）；
// U10 会用完整实现（旧式整体 base64、插件、IPv6……）替换它。
func init() { Register("ss", minimalSS) }

func minimalSS(line string) (Entity, error) {
	u, err := url.Parse(line)
	if err != nil {
		return Entity{}, fmt.Errorf("ss: %w", err)
	}
	if u.User == nil || u.Hostname() == "" || u.Port() == "" {
		return Entity{}, fmt.Errorf("ss: expected ss://userinfo@host:port")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil || port < 1 || port > 65535 {
		return Entity{}, fmt.Errorf("ss: bad port %q", u.Port())
	}
	method, password := u.User.Username(), ""
	if p, ok := u.User.Password(); ok {
		password = p
	} else if dec, err := decodeB64(u.User.Username()); err == nil {
		m, pw, ok := strings.Cut(string(dec), ":")
		if !ok {
			return Entity{}, fmt.Errorf("ss: userinfo is not method:password")
		}
		method, password = m, pw
	} else {
		return Entity{}, fmt.Errorf("ss: bad userinfo")
	}
	tag := u.Fragment
	if tag == "" {
		tag = fmt.Sprintf("%s:%d", u.Hostname(), port)
	}
	return Entity{Map: map[string]any{
		"type": "shadowsocks", "tag": tag, "server": u.Hostname(), "server_port": port,
		"method": method, "password": password,
	}}, nil
}

// decodeB64 接受标准 / urlsafe、带 / 不带 padding 的 base64。
func decodeB64(s string) ([]byte, error) {
	s = strings.TrimSpace(s)
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return b, nil
		}
	}
	return nil, fmt.Errorf("not base64")
}
