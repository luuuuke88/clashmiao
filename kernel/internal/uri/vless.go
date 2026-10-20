package uri

func init() { Register("vless", convertVLess) }

// convertVLess：vless://uuid@host:port?encryption=none&flow=…&security=tls|reality&sni=…&fp=…&pbk=…&sid=…
// &type=tcp|ws|grpc|httpupgrade|h2|http&host=…&path=…&serviceName=…#name
func convertVLess(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	if l.user == "" {
		return Entity{}, invalidf("vless", "missing uuid")
	}
	if enc := l.query.get("encryption"); enc != "" && enc != "none" {
		return Entity{}, invalidf("vless", "unsupported encryption %q (only none)", enc)
	}
	out := base("vless", l.tag(), l.host, l.port)
	out["uuid"] = l.user
	tls, err := tlsFor("vless", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	if tls != nil {
		out["tls"] = tls
	}
	if flow := l.query.get("flow"); flow != "" {
		if tls == nil {
			return Entity{}, invalidf("vless", "flow %q needs tls or reality", flow)
		}
		out["flow"] = flow
	}
	if pe := l.query.get("packetEncoding", "packet-encoding", "packet_encoding"); pe != "" {
		out["packet_encoding"] = pe
	}
	tr, err := transportFor("vless", transportSpec{
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
