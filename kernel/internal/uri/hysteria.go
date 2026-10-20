package uri

func init() { Register("hysteria", convertHysteria) }

// convertHysteria（v1）：hysteria://host:port?auth=…&upmbps=…&downmbps=…&peer=sni&insecure=1&alpn=…&obfs=xplus&obfsParam=…&protocol=udp#name
// 内核只支持 udp 协议；faketcp / wechat-video 报错。sing-box 要求带宽必填，缺了就报错而不是替用户编一个数。
func convertHysteria(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if l.host == "" {
		return Entity{}, invalidf("hysteria", "missing host")
	}
	ports, err := portHopRanges("hysteria", l.query.get("mport", "ports"))
	if err != nil {
		return Entity{}, err
	}
	if l.port == 0 {
		return Entity{}, invalidf("hysteria", "missing port")
	}
	if proto := l.query.get("protocol"); proto != "" && proto != "udp" {
		return Entity{}, invalidf("hysteria", "unsupported protocol %q (only udp)", proto)
	}
	out := base("hysteria", l.tag(), l.host, l.port)
	if len(ports) > 0 {
		out["server_ports"] = toAnyList(ports)
	}
	if auth := l.query.get("auth", "auth_str", "auth-str"); auth != "" {
		out["auth_str"] = auth
	}
	for _, k := range [][2]string{{"upmbps", "up_mbps"}, {"downmbps", "down_mbps"}} {
		v := l.query.get(k[0], k[0][:len(k[0])-4])
		if v == "" {
			return Entity{}, invalidf("hysteria", "missing %s (the kernel requires up and down bandwidth)", k[0])
		}
		n, err := parseMbps(v)
		if err != nil {
			return Entity{}, invalidf("hysteria", "bad %s %q", k[0], v)
		}
		out[k[1]] = n
	}
	if ob := l.query.get("obfs"); ob != "" {
		if ob != "xplus" {
			return Entity{}, invalidf("hysteria", "unsupported obfs %q (only xplus)", ob)
		}
		pw := l.query.get("obfsParam", "obfs-param", "obfs_password")
		if pw == "" {
			return Entity{}, invalidf("hysteria", "obfs xplus needs obfsParam")
		}
		out["obfs"] = pw
	}
	tls, err := buildTLS("hysteria", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	out["tls"] = tls
	return Entity{Map: out}, nil
}
