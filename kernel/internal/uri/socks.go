package uri

import "strings"

func init() {
	for _, s := range []string{"socks", "socks5", "socks5h", "socks4", "socks4a"} {
		Register(s, convertSocks)
	}
}

// convertSocks：socks5://user:pass@host:port#name、socks://base64(user:pass)@host:port#name、socks4:// 等。
func convertSocks(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	version := "5"
	switch l.scheme {
	case "socks4":
		version = "4"
	case "socks4a":
		version = "4a"
	}
	out := base("socks", l.tag(), l.host, l.port)
	out["version"] = version
	user, pass := l.user, l.password
	// socks://base64(user:pass)@host:port：没有密码、且整段 userinfo 解出来是 user:pass 才当 base64。
	if l.hasUser && !l.hasPass && user != "" {
		if dec, err := decodeB64(user); err == nil && strings.Contains(string(dec), ":") {
			user, pass, _ = strings.Cut(string(dec), ":")
		}
	}
	if user != "" {
		out["username"] = user
	}
	if pass != "" {
		out["password"] = pass
	}
	return Entity{Map: out}, nil
}
