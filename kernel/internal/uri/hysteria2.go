package uri

import (
	"fmt"
	"strconv"
	"strings"
)

func init() {
	Register("hysteria2", convertHysteria2)
	Register("hy2", convertHysteria2)
}

// convertHysteria2：hysteria2://password@host[:port]?obfs=salamander&obfs-password=…&insecure=1&sni=…&mport=20000-30000&up=…&down=…#name
//
// pinSHA256 报错：协议里的 pin 是「证书」的 SHA-256，sing-box 的 certificate_public_key_sha256 是「公钥」的 SHA-256，
// 两者不是同一个值，转换过去只会让所有连接握手失败，而改成 insecure 又会悄悄放弃校验——所以明确拒绝，不静默降级。
func convertHysteria2(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if l.host == "" {
		return Entity{}, invalidf("hysteria2", "missing host")
	}
	if l.query.get("pinSHA256") != "" {
		return Entity{}, invalidf("hysteria2", "pinSHA256 pinning is not supported (certificate hash cannot be converted to the kernel's public-key pin)")
	}
	ports, err := portHopRanges("hysteria2", l.query.get("mport", "ports"))
	if err != nil {
		return Entity{}, err
	}
	port := l.port
	if port == 0 {
		if len(ports) == 0 {
			return Entity{}, invalidf("hysteria2", "missing port")
		}
		first, _, _ := strings.Cut(ports[0], ":")
		port, _ = strconv.Atoi(first)
	}
	pw := l.credentials()
	if pw == "" {
		return Entity{}, invalidf("hysteria2", "missing password")
	}
	out := base("hysteria2", l.tagFor(port), l.host, port)
	out["password"] = pw
	if len(ports) > 0 {
		out["server_ports"] = toAnyList(ports)
	}
	if ob := l.query.get("obfs"); ob != "" {
		if !strings.EqualFold(ob, "salamander") {
			return Entity{}, invalidf("hysteria2", "unsupported obfs %q (only salamander)", ob)
		}
		opw := l.query.get("obfs-password", "obfs_password")
		if opw == "" {
			return Entity{}, invalidf("hysteria2", "obfs salamander needs obfs-password")
		}
		out["obfs"] = map[string]any{"type": "salamander", "password": opw}
	}
	for _, k := range [][2]string{{"up", "up_mbps"}, {"down", "down_mbps"}} {
		if v := l.query.get(k[0], k[0]+"mbps"); v != "" {
			n, err := parseMbps(v)
			if err != nil {
				return Entity{}, invalidf("hysteria2", "bad %s %q", k[0], v)
			}
			out[k[1]] = n
		}
	}
	tls, err := buildTLS("hysteria2", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	out["tls"] = tls
	return Entity{Map: out}, nil
}

func (l *link) tagFor(port int) string {
	if l.name != "" {
		return l.name
	}
	return defaultTag(l.host, port)
}

// portHopRanges 把 20000-30000 或 20000-30000,40000-50000 或单个端口转成 sing-box 的 "start:end" 列表。
func portHopRanges(scheme, s string) ([]string, error) {
	var out []string
	for _, item := range splitList(s) {
		lo, hi, isRange := strings.Cut(strings.ReplaceAll(item, ":", "-"), "-")
		a, errA := strconv.Atoi(strings.TrimSpace(lo))
		if errA != nil || a < 1 || a > 65535 {
			return nil, invalidf(scheme, "bad port range %q", item)
		}
		if !isRange {
			out = append(out, fmt.Sprintf("%d:%d", a, a))
			continue
		}
		b, errB := strconv.Atoi(strings.TrimSpace(hi))
		if errB != nil || b < a || b > 65535 {
			return nil, invalidf(scheme, "bad port range %q", item)
		}
		out = append(out, fmt.Sprintf("%d:%d", a, b))
	}
	return out, nil
}

// parseMbps 接受「100」「100 mbps」「1 gbps」。
func parseMbps(s string) (int, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	unit := 1
	switch {
	case strings.HasSuffix(s, "gbps"):
		s, unit = strings.TrimSpace(strings.TrimSuffix(s, "gbps")), 1000
	case strings.HasSuffix(s, "mbps"):
		s = strings.TrimSpace(strings.TrimSuffix(s, "mbps"))
	}
	n, err := strconv.Atoi(s)
	if err != nil || n <= 0 {
		return 0, fmt.Errorf("bad rate")
	}
	return n * unit, nil
}
