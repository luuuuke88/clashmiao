package uri

func init() { Register("trojan", convertTrojan) }

// convertTrojan：trojan://password@host:port?security=tls&sni=…&type=ws|grpc&host=…&path=…&alpn=…&fp=…#name
// trojan 默认启用 TLS；写了 security=none 才是明文。
func convertTrojan(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	pw := l.credentials()
	if pw == "" {
		return Entity{}, invalidf("trojan", "missing password")
	}
	out := base("trojan", l.tag(), l.host, l.port)
	out["password"] = pw
	tls, err := tlsFor("trojan", l.query, l.host, true)
	if err != nil {
		return Entity{}, err
	}
	if tls != nil {
		out["tls"] = tls
	}
	tr, err := transportFor("trojan", transportSpec{
		Network: l.query.get("type", "net"), HeaderType: l.query.get("headerType"),
		Host: l.query.get("host"), Path: l.query.get("path"), ServiceName: l.query.get("serviceName", "service_name"),
	})
	if err != nil {
		return Entity{}, err
	}
	if tr != nil {
		out["transport"] = tr
	}
	return Entity{Map: out}, nil
}
