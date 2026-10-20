package options

import (
	"net/netip"
	"strconv"
	"strings"
)

// Rule 是 `rules` 里的一条用户规则（Dart 侧智能分流把国内直连清单注入成两条 bypass 规则）。
// 各字段都是逗号分隔的列表。
type Rule struct {
	IP       string `json:"ip,omitempty"`
	Domains  string `json:"domains,omitempty"`
	Port     string `json:"port,omitempty"`
	Network  string `json:"network,omitempty"`
	Protocol string `json:"protocol,omitempty"`
	Outbound string `json:"outbound,omitempty"`
}

// 规则的目标。空串按 proxy 处理。
const (
	TargetBypass = "bypass"
	TargetBlock  = "block"
	TargetProxy  = "proxy"
)

// Target 返回规范化的目标（空 → proxy）。非法值由 Matchers 报错。
func (r Rule) Target() string {
	if r.Outbound == "" {
		return TargetProxy
	}
	return r.Outbound
}

// Matchers 是一条规则展开后的匹配项（都已去重、保序）。
type Matchers struct {
	Domain        []string
	DomainSuffix  []string
	DomainRegex   []string
	DomainKeyword []string
	IPCIDR        []string
	Port          []uint16
	PortRange     []string // sing-box 写法 "1000:2000"
	Network       []string
	Protocol      []string
}

// Empty 判断这条规则没有任何匹配项（只有目标）。
func (m Matchers) Empty() bool {
	return len(m.Domain)+len(m.DomainSuffix)+len(m.DomainRegex)+len(m.DomainKeyword)+
		len(m.IPCIDR)+len(m.Port)+len(m.PortRange)+len(m.Network)+len(m.Protocol) == 0
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// dedupe 去重并保持首次出现的顺序。
func dedupe[T comparable](in []T) []T {
	seen := make(map[T]struct{}, len(in))
	out := in[:0:0]
	for _, v := range in {
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

// Matchers 把一条规则解析成匹配项。
//
// 域名前缀：full: → Domain，domain: → DomainSuffix，regexp: → DomainRegex，keyword: → DomainKeyword；
// 不带前缀的按后缀匹配处理（与 domain: 相同）。geoip: / geosite: 报错（新内核没有这两个数据库）。
func (r Rule) Matchers() (Matchers, error) {
	var m Matchers
	switch r.Outbound {
	case "", TargetBypass, TargetBlock, TargetProxy:
	default:
		return m, invalid("rule outbound %q is not one of \"bypass\", \"block\", \"proxy\"", r.Outbound)
	}

	for _, item := range splitList(r.Domains) {
		prefix, value, hasPrefix := strings.Cut(item, ":")
		if !hasPrefix {
			m.DomainSuffix = append(m.DomainSuffix, strings.ToLower(item))
			continue
		}
		switch strings.ToLower(prefix) {
		case "geosite", "geoip":
			return Matchers{}, invalid("geosite/geoip rules are not supported: %q", item)
		case "full":
			m.Domain = append(m.Domain, strings.ToLower(value))
		case "domain":
			m.DomainSuffix = append(m.DomainSuffix, strings.ToLower(value))
		case "regexp":
			m.DomainRegex = append(m.DomainRegex, value) // 正则保持原样（大小写有意义）
		case "keyword":
			m.DomainKeyword = append(m.DomainKeyword, strings.ToLower(value))
		default:
			return Matchers{}, invalid("unknown domain prefix %q in %q", prefix, item)
		}
		if value == "" {
			return Matchers{}, invalid("empty value after prefix in %q", item)
		}
	}

	for _, item := range splitList(r.IP) {
		if low := strings.ToLower(item); strings.HasPrefix(low, "geoip:") || strings.HasPrefix(low, "geosite:") {
			return Matchers{}, invalid("geosite/geoip rules are not supported: %q", item)
		}
		if prefix, err := netip.ParsePrefix(item); err == nil {
			m.IPCIDR = append(m.IPCIDR, prefix.String())
			continue
		}
		if addr, err := netip.ParseAddr(item); err == nil {
			m.IPCIDR = append(m.IPCIDR, netip.PrefixFrom(addr, addr.BitLen()).String())
			continue
		}
		return Matchers{}, invalid("invalid CIDR or IP %q", item)
	}

	for _, item := range splitList(r.Port) {
		if lo, hi, isRange := strings.Cut(item, ":"); isRange {
			a, errA := parsePort(lo)
			b, errB := parsePort(hi)
			if errA != nil || errB != nil || a > b {
				return Matchers{}, invalid("invalid port range %q", item)
			}
			m.PortRange = append(m.PortRange, strconv.Itoa(int(a))+":"+strconv.Itoa(int(b)))
			continue
		}
		p, err := parsePort(item)
		if err != nil {
			return Matchers{}, invalid("invalid port %q", item)
		}
		m.Port = append(m.Port, p)
	}

	for _, item := range splitList(r.Network) {
		n := strings.ToLower(item)
		if n != "tcp" && n != "udp" {
			return Matchers{}, invalid("network %q is not tcp or udp", item)
		}
		m.Network = append(m.Network, n)
	}
	for _, item := range splitList(r.Protocol) {
		m.Protocol = append(m.Protocol, strings.ToLower(item))
	}

	m.Domain, m.DomainSuffix = dedupe(m.Domain), dedupe(m.DomainSuffix)
	m.DomainRegex, m.DomainKeyword = dedupe(m.DomainRegex), dedupe(m.DomainKeyword)
	m.IPCIDR, m.Port, m.PortRange = dedupe(m.IPCIDR), dedupe(m.Port), dedupe(m.PortRange)
	m.Network, m.Protocol = dedupe(m.Network), dedupe(m.Protocol)
	return m, nil
}

func parsePort(s string) (uint16, error) {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n < 1 || n > 65535 {
		return 0, invalid("invalid port %q", s)
	}
	return uint16(n), nil
}
