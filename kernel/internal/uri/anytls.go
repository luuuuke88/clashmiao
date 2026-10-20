package uri

func init() { Register("anytls", convertAnyTLS) }

// convertAnyTLS：anytls://password@host:port?sni=…&insecure=1&alpn=…&fp=…#name（始终启用 TLS）
func convertAnyTLS(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	pw := l.credentials()
	if pw == "" {
		return Entity{}, invalidf("anytls", "missing password")
	}
	out := base("anytls", l.tag(), l.host, l.port)
	out["password"] = pw
	tls, err := buildTLS("anytls", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	out["tls"] = tls
	return Entity{Map: out}, nil
}
