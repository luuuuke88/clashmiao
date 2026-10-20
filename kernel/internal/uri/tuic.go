package uri

func init() { Register("tuic", convertTUIC) }

// convertTUIC（v5）：tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=…&allow_insecure=1&disable_sni=1#name
func convertTUIC(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	if l.user == "" {
		return Entity{}, invalidf("tuic", "missing uuid")
	}
	if !l.hasPass || l.password == "" {
		return Entity{}, invalidf("tuic", "missing password (only tuic v5 uuid:password is supported)")
	}
	out := base("tuic", l.tag(), l.host, l.port)
	out["uuid"] = l.user
	out["password"] = l.password
	if cc := l.query.get("congestion_control", "congestion-control", "congestion_controller"); cc != "" {
		out["congestion_control"] = cc
	}
	if m := l.query.get("udp_relay_mode", "udp-relay-mode"); m != "" {
		out["udp_relay_mode"] = m
	}
	if l.query.truthy("udp_over_stream", "udp-over-stream") {
		out["udp_over_stream"] = true
	}
	if l.query.truthy("reduce_rtt", "zero_rtt_handshake", "zero-rtt-handshake") {
		out["zero_rtt_handshake"] = true
	}
	tls, err := buildTLS("tuic", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	if l.query.truthy("disable_sni", "disable-sni") {
		tls["disable_sni"] = true
	}
	out["tls"] = tls
	return Entity{Map: out}, nil
}
