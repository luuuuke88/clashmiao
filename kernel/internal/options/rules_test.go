package options

import (
	"reflect"
	"strings"
	"testing"
)

func TestRuleMatchers(t *testing.T) {
	cases := []struct {
		name string
		rule Rule
		want Matchers
		err  string // 非空表示应报错，且错误里含这段
	}{
		{name: "empty rule", rule: Rule{}, want: Matchers{}},
		{name: "full prefix", rule: Rule{Domains: "full:Example.COM"}, want: Matchers{Domain: []string{"example.com"}}},
		{name: "domain prefix", rule: Rule{Domains: "domain:example.com"}, want: Matchers{DomainSuffix: []string{"example.com"}}},
		{name: "regexp prefix keeps case", rule: Rule{Domains: `regexp:^(.+\.)?Example\.cn$`}, want: Matchers{DomainRegex: []string{`^(.+\.)?Example\.cn$`}}},
		{name: "keyword prefix", rule: Rule{Domains: "keyword:Tracker"}, want: Matchers{DomainKeyword: []string{"tracker"}}},
		{name: "no prefix is suffix", rule: Rule{Domains: "example.org"}, want: Matchers{DomainSuffix: []string{"example.org"}}},
		{name: "mixed list", rule: Rule{Domains: "full:a.example.com, domain:example.net ,keyword:ads,regexp:^x$"},
			want: Matchers{Domain: []string{"a.example.com"}, DomainSuffix: []string{"example.net"}, DomainKeyword: []string{"ads"}, DomainRegex: []string{"^x$"}}},
		{name: "duplicates removed keep order", rule: Rule{Domains: "domain:b.example.com,domain:a.example.com,domain:b.example.com,full:z.example.com,full:z.example.com"},
			want: Matchers{DomainSuffix: []string{"b.example.com", "a.example.com"}, Domain: []string{"z.example.com"}}},
		{name: "empty items skipped", rule: Rule{Domains: ",, domain:example.com ,,"}, want: Matchers{DomainSuffix: []string{"example.com"}}},
		{name: "geosite rejected", rule: Rule{Domains: "geosite:cn"}, err: "geosite/geoip rules are not supported"},
		{name: "geoip in domains rejected", rule: Rule{Domains: "geoip:cn"}, err: "geosite/geoip rules are not supported"},
		{name: "geoip in ip rejected", rule: Rule{IP: "geoip:cn"}, err: "geosite/geoip rules are not supported"},
		{name: "geosite in ip rejected", rule: Rule{IP: "GEOSITE:cn"}, err: "geosite/geoip rules are not supported"},
		{name: "unknown prefix", rule: Rule{Domains: "ext:foo"}, err: "unknown domain prefix"},
		{name: "empty after prefix", rule: Rule{Domains: "domain:"}, err: "empty value"},
		{name: "cidr v4", rule: Rule{IP: "192.0.2.0/24"}, want: Matchers{IPCIDR: []string{"192.0.2.0/24"}}},
		{name: "cidr v6", rule: Rule{IP: "2001:db8::/32"}, want: Matchers{IPCIDR: []string{"2001:db8::/32"}}},
		{name: "bare ip becomes host prefix", rule: Rule{IP: "198.51.100.7, 2001:db8::1"}, want: Matchers{IPCIDR: []string{"198.51.100.7/32", "2001:db8::1/128"}}},
		{name: "cidr duplicates removed", rule: Rule{IP: "192.0.2.0/24,198.51.100.0/24,192.0.2.0/24"}, want: Matchers{IPCIDR: []string{"192.0.2.0/24", "198.51.100.0/24"}}},
		{name: "invalid cidr", rule: Rule{IP: "192.0.2.0/33"}, err: "invalid CIDR"},
		{name: "invalid ip", rule: Rule{IP: "not-an-ip"}, err: "invalid CIDR"},
		{name: "ports", rule: Rule{Port: "443, 80,443"}, want: Matchers{Port: []uint16{443, 80}}},
		{name: "port range", rule: Rule{Port: "1000:2000"}, want: Matchers{PortRange: []string{"1000:2000"}}},
		{name: "port mixed", rule: Rule{Port: "53,1000:2000,8080"}, want: Matchers{Port: []uint16{53, 8080}, PortRange: []string{"1000:2000"}}},
		{name: "port zero", rule: Rule{Port: "0"}, err: "invalid port"},
		{name: "port too big", rule: Rule{Port: "65536"}, err: "invalid port"},
		{name: "port range reversed", rule: Rule{Port: "2000:1000"}, err: "invalid port range"},
		{name: "port not number", rule: Rule{Port: "https"}, err: "invalid port"},
		{name: "network", rule: Rule{Network: "TCP,udp,tcp"}, want: Matchers{Network: []string{"tcp", "udp"}}},
		{name: "network bad", rule: Rule{Network: "icmp"}, err: "not tcp or udp"},
		{name: "protocol", rule: Rule{Protocol: "TLS, quic ,tls"}, want: Matchers{Protocol: []string{"tls", "quic"}}},
		{name: "outbound bypass", rule: Rule{Outbound: "bypass", IP: "10.0.0.0/8"}, want: Matchers{IPCIDR: []string{"10.0.0.0/8"}}},
		{name: "outbound block", rule: Rule{Outbound: "block"}, want: Matchers{}},
		{name: "outbound proxy", rule: Rule{Outbound: "proxy"}, want: Matchers{}},
		{name: "outbound other", rule: Rule{Outbound: "reject"}, err: "rule outbound"},
		{name: "everything at once", rule: Rule{IP: "203.0.113.0/24", Domains: "domain:example.com", Port: "443", Network: "tcp", Protocol: "tls", Outbound: "proxy"},
			want: Matchers{IPCIDR: []string{"203.0.113.0/24"}, DomainSuffix: []string{"example.com"}, Port: []uint16{443}, Network: []string{"tcp"}, Protocol: []string{"tls"}}},
	}
	for _, c := range cases {
		got, err := c.rule.Matchers()
		if c.err != "" {
			if err == nil {
				t.Errorf("%s: expected error containing %q", c.name, c.err)
			} else if !IsOptionError(err) || !strings.Contains(err.Error(), c.err) {
				t.Errorf("%s: error %q should be an option error containing %q", c.name, err, c.err)
			}
			continue
		}
		if err != nil {
			t.Errorf("%s: %v", c.name, err)
			continue
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s:\n got: %+v\nwant: %+v", c.name, got, c.want)
		}
	}
}

func TestRuleTargetDefaultsToProxy(t *testing.T) {
	for in, want := range map[string]string{"": TargetProxy, "bypass": TargetBypass, "block": TargetBlock, "proxy": TargetProxy} {
		if got := (Rule{Outbound: in}).Target(); got != want {
			t.Errorf("Target(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestMatchersEmpty(t *testing.T) {
	m, _ := Rule{Outbound: "bypass"}.Matchers()
	if !m.Empty() {
		t.Fatal("rule with only a target should have empty matchers")
	}
	m, _ = Rule{IP: "10.0.0.0/8"}.Matchers()
	if m.Empty() {
		t.Fatal("rule with a CIDR is not empty")
	}
}

// 智能分流注入的两条规则的形态（约 7.5k 条 CIDR 与数千条域名）要能解析，且去重后数量不变。
func TestLargeRuleParses(t *testing.T) {
	var ips, doms []string
	for i := 0; i < 7500; i++ {
		ips = append(ips, "198.18."+itoa(i/256%256)+"."+itoa(i%256)+"/32")
		doms = append(doms, "domain:h"+itoa(i)+".example.cn")
	}
	m, err := Rule{IP: strings.Join(ips, ","), Domains: strings.Join(doms, ","), Outbound: "bypass"}.Matchers()
	if err != nil {
		t.Fatal(err)
	}
	if len(m.IPCIDR) != len(dedupe(ips)) || len(m.DomainSuffix) != 7500 {
		t.Fatalf("got %d cidrs, %d suffixes", len(m.IPCIDR), len(m.DomainSuffix))
	}
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	return string(b)
}
