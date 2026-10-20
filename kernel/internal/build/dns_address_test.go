package build

import (
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func TestParseDNSAddress(t *testing.T) {
	cases := []struct {
		in   string
		want DNSServerSpec
	}{
		// 裸 IP / udp
		{"1.1.1.1", DNSServerSpec{Type: "udp", Host: "1.1.1.1"}},
		{"  1.1.1.1  ", DNSServerSpec{Type: "udp", Host: "1.1.1.1"}},
		{"1.1.1.1:53", DNSServerSpec{Type: "udp", Host: "1.1.1.1"}}, // 与默认端口相同时不写 server_port
		{"1.1.1.1:5353", DNSServerSpec{Type: "udp", Host: "1.1.1.1", Port: 5353}},
		{"udp://8.8.8.8", DNSServerSpec{Type: "udp", Host: "8.8.8.8"}},
		{"UDP://8.8.8.8:5353", DNSServerSpec{Type: "udp", Host: "8.8.8.8", Port: 5353}},
		{"dns.example.net", DNSServerSpec{Type: "udp", Host: "dns.example.net", IsDomain: true}},
		{"dns.example.net:5353", DNSServerSpec{Type: "udp", Host: "dns.example.net", Port: 5353, IsDomain: true}},
		// IPv6
		{"2001:db8::1", DNSServerSpec{Type: "udp", Host: "2001:db8::1"}},
		{"[2001:db8::1]", DNSServerSpec{Type: "udp", Host: "2001:db8::1"}},
		{"[2001:db8::1]:53", DNSServerSpec{Type: "udp", Host: "2001:db8::1"}},
		{"[2001:db8::1]:5353", DNSServerSpec{Type: "udp", Host: "2001:db8::1", Port: 5353}},
		{"udp://[2001:db8::1]:5353", DNSServerSpec{Type: "udp", Host: "2001:db8::1", Port: 5353}},
		{"tcp://[2001:db8::1]", DNSServerSpec{Type: "tcp", Host: "2001:db8::1"}},
		{"https://[2001:db8::1]:8443/dq", DNSServerSpec{Type: "https", Host: "2001:db8::1", Port: 8443, Path: "/dq"}},
		// tcp / tls / quic
		{"tcp://1.1.1.1", DNSServerSpec{Type: "tcp", Host: "1.1.1.1"}},
		{"tcp://1.1.1.1:5353", DNSServerSpec{Type: "tcp", Host: "1.1.1.1", Port: 5353}},
		{"tls://dot.example.net", DNSServerSpec{Type: "tls", Host: "dot.example.net", IsDomain: true}},
		{"tls://dot.example.net:853", DNSServerSpec{Type: "tls", Host: "dot.example.net", IsDomain: true}},
		{"tls://dot.example.net:8853", DNSServerSpec{Type: "tls", Host: "dot.example.net", Port: 8853, IsDomain: true}},
		{"TLS://1.0.0.1", DNSServerSpec{Type: "tls", Host: "1.0.0.1"}},
		{"quic://doq.example.net", DNSServerSpec{Type: "quic", Host: "doq.example.net", IsDomain: true}},
		{"quic://doq.example.net:784", DNSServerSpec{Type: "quic", Host: "doq.example.net", Port: 784, IsDomain: true}},
		// https / h3：默认端口 443、默认路径 /dns-query
		{"https://1.1.1.1/dns-query", DNSServerSpec{Type: "https", Host: "1.1.1.1", Path: "/dns-query"}},
		{"https://1.1.1.1", DNSServerSpec{Type: "https", Host: "1.1.1.1", Path: "/dns-query"}},
		{"https://1.1.1.1/", DNSServerSpec{Type: "https", Host: "1.1.1.1", Path: "/dns-query"}},
		{"https://doh.example.net/dns-query", DNSServerSpec{Type: "https", Host: "doh.example.net", Path: "/dns-query", IsDomain: true}},
		{"https://doh.example.net:443/dns-query", DNSServerSpec{Type: "https", Host: "doh.example.net", Path: "/dns-query", IsDomain: true}},
		{"https://doh.example.net:8443/custom/path", DNSServerSpec{Type: "https", Host: "doh.example.net", Port: 8443, Path: "/custom/path", IsDomain: true}},
		{"HTTPS://DOH.example.net/dns-query", DNSServerSpec{Type: "https", Host: "DOH.example.net", Path: "/dns-query", IsDomain: true}},
		{"h3://doh.example.net/dns-query", DNSServerSpec{Type: "h3", Host: "doh.example.net", Path: "/dns-query", IsDomain: true}},
		{"h3://1.1.1.1", DNSServerSpec{Type: "h3", Host: "1.1.1.1", Path: "/dns-query"}},
		// local / fakeip
		{"local", DNSServerSpec{Type: "local"}},
		{"LOCAL", DNSServerSpec{Type: "local"}},
		{"fakeip", DNSServerSpec{Type: "fakeip"}},
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			got, err := ParseDNSAddress(tc.in)
			if err != nil {
				t.Fatalf("ParseDNSAddress(%q): %v", tc.in, err)
			}
			if got != tc.want {
				t.Errorf("ParseDNSAddress(%q)\n got  %+v\n want %+v", tc.in, got, tc.want)
			}
		})
	}
}

func TestParseDNSAddressRejects(t *testing.T) {
	cases := []struct{ in, why string }{
		{"", "empty"},
		{"   ", "empty"},
		{"rcode://success", "rcode"},
		{"dhcp://en0", "dhcp"},
		{"dhcp://", "dhcp"},
		{"ftp://1.1.1.1", "unsupported scheme"},
		{"https+local://1.1.1.1", "unsupported scheme"},
		{"1.1.1.1:0", "invalid port"},
		{"1.1.1.1:65536", "invalid port"},
		{"1.1.1.1:abc", "invalid port"},
		{"1.1.1.1:", "empty port"},
		{"tcp://", "missing host"},
		{"https://", "missing host"},
		{"https:///dns-query", "missing host"},
		{"tls://dot.example.net/path", "does not take a path"},
		{"quic://doq.example.net/x", "does not take a path"},
		{"https://doh.example.net/dns-query?x=1", "query"},
		{"https://doh.example.net/dns-query#frag", "query"},
		{"udp://[2001:db8::1", "invalid"},
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			_, err := ParseDNSAddress(tc.in)
			if err == nil {
				t.Fatalf("ParseDNSAddress(%q) 应当失败", tc.in)
			}
			if !options.IsOptionError(err) || !strings.HasPrefix(err.Error(), options.ErrorPrefix) {
				t.Errorf("错误应是 option-invalid: %v", err)
			}
			if !strings.Contains(err.Error(), tc.why) {
				t.Errorf("错误 %q 应含 %q", err, tc.why)
			}
		})
	}
}

// 域名型地址一律标记，IP 字面量（含 IPv6）一律不标：自举解析器只为域名生成。
func TestParseDNSAddressDomainDetection(t *testing.T) {
	for in, want := range map[string]bool{
		"1.1.1.1": false, "2001:db8::1": false, "[::1]:53": false, "https://1.1.1.1/dns-query": false,
		"dns.example.net": true, "https://doh.example.net/x": true, "quic://doq.example.net": true,
		"local": false,
	} {
		got, err := ParseDNSAddress(in)
		if err != nil {
			t.Fatal(err)
		}
		if got.IsDomain != want {
			t.Errorf("%q IsDomain=%v，期望 %v", in, got.IsDomain, want)
		}
	}
}
