package build

import (
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strconv"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// DNSServerSpec 是 ParseDNSAddress 的结果：一个类型化 DNS 服务器的定义（不含 tag / detour）。
type DNSServerSpec struct {
	Type string // udp / tcp / tls / https / h3 / quic / local / fakeip
	// Host 是服务器地址（IP 字面量或域名），local / fakeip 为空。
	Host string
	// Port 为 0 表示用类型的默认端口（不写 server_port）。
	Port int
	// Path 只有 https / h3 有，缺省 /dns-query。
	Path string
	// IsDomain 为真表示 Host 是域名：这个服务器自己的解析必须交给 dns-bootstrap。
	IsDomain bool
}

// 各类型的默认端口。显式写出与默认相同的端口时不输出 server_port，让黄金文件保持简洁。
var defaultDNSPort = map[string]int{"udp": 53, "tcp": 53, "tls": 853, "https": 443, "h3": 443, "quic": 853}

func dnsAddrErr(addr, format string, args ...any) error {
	return &options.Error{Msg: fmt.Sprintf("dns address %q: ", addr) + fmt.Sprintf(format, args...)}
}

// ParseDNSAddress 把选项里的 DNS 地址（remote-dns-address / direct-dns-address）映射成类型化服务器（spec §3.4 第 1 行）。
//
//	1.1.1.1  1.1.1.1:53  [2001:db8::1]:53  udp://…   → udp
//	tcp://…                                         → tcp
//	tls://…                                         → tls（默认 853）
//	https://host[:port][/path]                      → https（默认 443、/dns-query）
//	h3://…                                          → h3（默认 443、/dns-query）
//	quic://…                                        → quic（默认 853）
//	local                                           → local
//	fakeip                                          → fakeip
//
// rcode:// dhcp:// 与未知 scheme 一律返回 option-invalid，不静默降级。
func ParseDNSAddress(addr string) (DNSServerSpec, error) {
	s := strings.TrimSpace(addr)
	if s == "" {
		return DNSServerSpec{}, dnsAddrErr(addr, "must not be empty")
	}
	switch strings.ToLower(s) {
	case "local":
		return DNSServerSpec{Type: "local"}, nil
	case "fakeip":
		return DNSServerSpec{Type: "fakeip"}, nil
	}

	scheme := "udp"
	rest := s
	if i := strings.Index(s, "://"); i >= 0 {
		scheme = strings.ToLower(s[:i])
		rest = s[i+3:]
		switch scheme {
		case "udp", "tcp", "tls", "https", "h3", "quic":
		case "rcode", "dhcp":
			return DNSServerSpec{}, dnsAddrErr(addr, "%s:// is not supported (use a rule action instead)", scheme)
		default:
			return DNSServerSpec{}, dnsAddrErr(addr, "unsupported scheme %q", scheme)
		}
	}

	// 把「主机[:端口]」与「路径」切开。IPv6 字面量带方括号时 url 解析器会处理，裸 IPv6 单独判断。
	hostPort, path := rest, ""
	if i := strings.IndexAny(rest, "/?#"); i >= 0 {
		hostPort, path = rest[:i], rest[i:]
	}
	if hostPort == "" {
		return DNSServerSpec{}, dnsAddrErr(addr, "missing host")
	}

	var host string
	port := 0
	switch {
	case isBareIP(hostPort):
		host = hostPort
	default:
		u, err := url.Parse("//" + hostPort)
		if err != nil && strings.Contains(err.Error(), "port") {
			return DNSServerSpec{}, dnsAddrErr(addr, "invalid port")
		}
		if err != nil || u.Hostname() == "" {
			return DNSServerSpec{}, dnsAddrErr(addr, "invalid host")
		}
		host = u.Hostname()
		if p := u.Port(); p != "" {
			n, err := strconv.Atoi(p)
			if err != nil || n < 1 || n > 65535 {
				return DNSServerSpec{}, dnsAddrErr(addr, "invalid port %q", p)
			}
			port = n
		} else if strings.HasSuffix(hostPort, ":") {
			return DNSServerSpec{}, dnsAddrErr(addr, "empty port")
		}
	}
	if strings.ContainsAny(host, " \t") {
		return DNSServerSpec{}, dnsAddrErr(addr, "invalid host")
	}

	spec := DNSServerSpec{Type: scheme, Host: host}
	if port != defaultDNSPort[scheme] {
		spec.Port = port
	}
	if _, err := netip.ParseAddr(strings.Trim(host, "[]")); err != nil {
		spec.IsDomain = true
	} else {
		spec.Host = strings.Trim(host, "[]")
	}

	switch scheme {
	case "https", "h3":
		u, err := url.Parse("//x" + path)
		if err != nil {
			return DNSServerSpec{}, dnsAddrErr(addr, "invalid path")
		}
		if u.RawQuery != "" || u.Fragment != "" {
			return DNSServerSpec{}, dnsAddrErr(addr, "query and fragment are not supported")
		}
		spec.Path = u.Path
		if spec.Path == "" || spec.Path == "/" {
			spec.Path = "/dns-query"
		}
	default:
		if path != "" && path != "/" {
			return DNSServerSpec{}, dnsAddrErr(addr, "%s does not take a path", scheme)
		}
	}
	return spec, nil
}

// isBareIP：整串就是一个 IP（含不带方括号的 IPv6）。「1.1.1.1:53」不是，它带端口。
func isBareIP(s string) bool {
	_, err := netip.ParseAddr(s)
	return err == nil
}

// hostIsIPLiteral 判断 s（可能带端口）的主机部分是否是 IP 字面量。
func hostIsIPLiteral(s string) bool {
	if isBareIP(s) {
		return true
	}
	if h, _, err := net.SplitHostPort(s); err == nil {
		_, err := netip.ParseAddr(h)
		return err == nil
	}
	return false
}
