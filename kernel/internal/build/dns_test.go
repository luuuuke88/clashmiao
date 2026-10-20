package build_test

import (
	"encoding/json"
	"math/rand"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func buildCfg(t testing.TB, p build.Profile, o *options.Options) (*cfg.Config, []string) {
	t.Helper()
	raw, warnings, err := build.Build(p, o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	var c cfg.Config
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	return &c, warnings
}

func server(t testing.TB, c *cfg.Config, tag string) *cfg.DNSServer {
	t.Helper()
	for i := range c.DNS.Servers {
		if c.DNS.Servers[i].Tag == tag {
			return &c.DNS.Servers[i]
		}
	}
	return nil
}

// dns-remote 的 detour 恒等于业务出口（否则远程 DNS 直连泄漏）；dns-direct / dns-local 绝不写 detour
// （CheckConfig 放行、Start 拒绝指向空 direct 的 detour）。
func TestDNSDetourRules(t *testing.T) {
	for _, name := range gate.OptionNames() {
		t.Run(name, func(t *testing.T) {
			o := gate.Option(name)
			wantDetour := "select"
			if p, on := build.PolicyFor(o); on {
				wantDetour = p.Egress // warp_over_proxy 时业务出口是 warp
			}
			c, _ := buildCfg(t, gate.LoadProfile(t, "P2"), o)
			remote := server(t, c, "dns-remote")
			if remote == nil {
				t.Fatal("没有 dns-remote")
			}
			if remote.Type == "local" {
				if remote.Detour != "" {
					t.Errorf("local 类型不拨号，不该写 detour: %q", remote.Detour)
				}
			} else if remote.Detour != wantDetour {
				t.Errorf("dns-remote.detour = %q，期望业务出口 %s", remote.Detour, wantDetour)
			}
			for _, tag := range []string{"dns-direct", "dns-local", "dns-bootstrap", "dns-fake"} {
				if s := server(t, c, tag); s != nil && s.Detour != "" {
					t.Errorf("%s 不该有 detour，实际 %q", tag, s.Detour)
				}
			}
			if c.DNS.Final != "dns-remote" {
				t.Errorf("dns.final = %q", c.DNS.Final)
			}
			if r := c.Route.DefaultDomainResolver; r == nil || r.Server != "dns-direct" {
				t.Errorf("route.default_domain_resolver = %+v", r)
			}
		})
	}
}

// 自举解析器只在有域名型 DNS 服务器时生成；域名型服务器的 domain_resolver 恒为它，绝不是自己或另一个 DNS 服务器。
func TestDNSBootstrapGeneration(t *testing.T) {
	cases := []struct {
		option        string
		wantBootstrap bool
		resolverOf    map[string]string
	}{
		{"O1", false, map[string]string{}},
		{"O6-ip", false, map[string]string{}},
		{"O6-https-ip", false, map[string]string{}},
		{"O6-local", false, map[string]string{}},
		{"O6-https-domain", true, map[string]string{"dns-remote": "dns-bootstrap"}},
		{"O6-h3", true, map[string]string{"dns-remote": "dns-bootstrap"}},
		{"O6-tls", true, map[string]string{"dns-remote": "dns-bootstrap"}},
		{"O6-quic", true, map[string]string{"dns-remote": "dns-bootstrap"}},
		{"O6-direct-doh-domain", true, map[string]string{"dns-direct": "dns-bootstrap"}},
	}
	for _, tc := range cases {
		t.Run(tc.option, func(t *testing.T) {
			c, _ := buildCfg(t, gate.LoadProfile(t, "P1"), gate.Option(tc.option))
			b := server(t, c, "dns-bootstrap")
			if (b != nil) != tc.wantBootstrap {
				t.Fatalf("dns-bootstrap 存在 = %v，期望 %v", b != nil, tc.wantBootstrap)
			}
			if b != nil && (b.Type != "udp" || b.Server != "223.5.5.5" || b.Detour != "" || b.DomainResolver != "") {
				t.Errorf("dns-bootstrap 必须是无 detour、无 resolver 的 IP-only udp: %+v", *b)
			}
			for _, s := range c.DNS.Servers {
				if want := tc.resolverOf[s.Tag]; s.DomainResolver != want {
					t.Errorf("%s.domain_resolver = %q，期望 %q", s.Tag, s.DomainResolver, want)
				}
			}
		})
	}
}

// bootstrap 端口写法：IPv6 与带端口都能进配置。
func TestDNSBootstrapAddressForms(t *testing.T) {
	for addr, want := range map[string]struct {
		ip   string
		port int
	}{
		"223.5.5.5":          {"223.5.5.5", 0},
		"223.5.5.5:5353":     {"223.5.5.5", 5353},
		"2400:3200::1":       {"2400:3200::1", 0},
		"[2400:3200::1]:853": {"2400:3200::1", 853},
	} {
		o := gate.Option("O6-https-domain")
		o.BootstrapDNSAddress = addr
		c, _ := buildCfg(t, gate.LoadProfile(t, "P1"), o)
		b := server(t, c, "dns-bootstrap")
		if b == nil || b.Server != want.ip || b.ServerPort != want.port {
			t.Errorf("bootstrap %q → %+v，期望 %s:%d", addr, b, want.ip, want.port)
		}
	}
}

func TestDNSBuildRejectsBadAddresses(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(o *options.Options)
		want   string
	}{
		{"远程 rcode", func(o *options.Options) { o.RemoteDNSAddress = "rcode://success" }, "remote-dns-address"},
		{"直连 dhcp", func(o *options.Options) { o.DirectDNSAddress = "dhcp://en0" }, "direct-dns-address"},
		{"远程 fakeip", func(o *options.Options) { o.RemoteDNSAddress = "fakeip" }, "fakeip"},
		{"自举是域名", func(o *options.Options) {
			o.RemoteDNSAddress = "https://doh.example.net/dns-query"
			o.BootstrapDNSAddress = "dns.example.net"
		}, "bootstrap-dns-address"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			o := gate.Option("O1")
			tc.mutate(o)
			_, _, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv())
			if err == nil || !options.IsOptionError(err) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v，期望 option-invalid 且含 %q", err, tc.want)
			}
		})
	}
}

// 直连域名规则：各节点 server 域名去重、排序；节点顺序打乱、重复节点都不改变 DNS 块。
func TestDNSDirectDomainsAreDeduplicatedAndStable(t *testing.T) {
	base := gate.LoadProfile(t, "P2")
	node := func(tag, host string) map[string]any {
		return map[string]any{"type": "shadowsocks", "tag": tag, "server": host, "server_port": 8388, "method": "aes-128-gcm", "password": "x"}
	}
	nodes := []map[string]any{node("a", "b.example.net"), node("b", "a.example.net"), node("c", "B.example.net"), node("d", "c.example.net"), node("e", "192.0.2.7")}
	dnsOf := func(nodes []map[string]any) string {
		c, _ := buildCfg(t, build.Profile{Outbounds: nodes}, gate.Option("O1"))
		b, _ := json.Marshal(c.DNS)
		return string(b)
	}
	want := dnsOf(nodes)
	c, _ := buildCfg(t, build.Profile{Outbounds: nodes}, gate.Option("O1"))
	rule := c.DNS.Rules[0]
	if got := strings.Join(rule.Domain, ","); got != "a.example.net,b.example.net,c.example.net" {
		t.Fatalf("直连域名 = %s（应去重、小写、排序，且不含 IP 字面量）", got)
	}
	r := rand.New(rand.NewSource(1))
	for i := 0; i < 20; i++ {
		shuffled := append([]map[string]any(nil), nodes...)
		r.Shuffle(len(shuffled), func(i, j int) { shuffled[i], shuffled[j] = shuffled[j], shuffled[i] })
		if got := dnsOf(shuffled); got != want {
			t.Fatalf("节点顺序改变了 DNS 块:\n%s\n%s", want, got)
		}
	}
	_ = base
}

// 端点（WireGuard）的对端域名同样要直连解析。
func TestDNSDirectDomainsIncludeEndpointPeers(t *testing.T) {
	c, _ := buildCfg(t, gate.LoadProfile(t, "P4b"), gate.Option("O1"))
	got := strings.Join(c.DNS.Rules[0].Domain, ",")
	if got != "hk.example.net,wg2.example.net" {
		t.Fatalf("直连域名 = %s，应含出站 server 与端点 peers.address", got)
	}
}

// 全是 IP 的节点：没有直连域名规则。
func TestDNSNoDirectDomainRuleWhenNodesAreIPs(t *testing.T) {
	p := build.Profile{Outbounds: []map[string]any{{"type": "shadowsocks", "tag": "a", "server": "192.0.2.9", "server_port": 1, "method": "aes-128-gcm", "password": "x"}}}
	c, _ := buildCfg(t, p, gate.Option("O1"))
	for _, r := range c.DNS.Rules {
		if r.Server == "dns-direct" {
			t.Errorf("不该有指向 dns-direct 的规则: %+v", r)
		}
	}
	if len(c.DNS.Rules) != 1 || c.DNS.Rules[0].Domain[0] != "cp.cloudflare.com" {
		t.Errorf("只应留探测域名规则: %+v", c.DNS.Rules)
	}
}

// O3：fake DNS、DNS 路由的规则内容与顺序。
func TestDNSRulesForO3(t *testing.T) {
	c, _ := buildCfg(t, gate.LoadProfile(t, "P2"), gate.Option("O3"))
	var got []string
	for _, r := range c.DNS.Rules {
		switch {
		case r.Server == "dns-direct" && len(r.Domain) == 3:
			got = append(got, "direct-node-domains")
		case r.Server == "dns-fake":
			got = append(got, "fake")
			if len(r.Inbound) != 1 || r.Inbound[0] != "tun-in" || !r.DisableCache {
				t.Errorf("fake 规则应限定 tun-in 且禁缓存: %+v", r)
			}
		case r.Server == "dns-direct":
			got = append(got, "bypass:"+strings.Join(append(append([]string{}, r.Domain...), r.DomainSuffix...), "|"))
		case r.Action == "predefined":
			got = append(got, "block:"+strings.Join(r.DomainKeyword, "|")+":"+r.Rcode)
		case r.Server == "dns-remote":
			got = append(got, "probe")
			if r.RewriteTTL == nil || *r.RewriteTTL != 3000 {
				t.Errorf("探测规则应固定 TTL 3000: %+v", r)
			}
		}
	}
	want := "direct-node-domains,fake,bypass:direct.example.net|example.cn,block:ads:NOERROR,probe"
	if strings.Join(got, ",") != want {
		t.Errorf("规则顺序 = %v\n期望     %s", got, want)
	}
	// 只有 IP 条件的 bypass 规则与走代理的规则都不产生 DNS 规则。
	for _, r := range c.DNS.Rules {
		if strings.Contains(strings.Join(r.Domain, ","), "proxy.example.com") || len(r.DomainSuffix) > 0 && r.DomainSuffix[0] == "proxy.example.com" {
			t.Errorf("proxy 规则不该产生 DNS 规则: %+v", r)
		}
	}
	if len(c.DNS.Rules) != 5 {
		t.Errorf("规则数 = %d，期望 5", len(c.DNS.Rules))
	}
}

// 仅线路（没有 tun-in）：fake DNS 与引用 tun-in 的规则整条省略。
func TestDNSFakeOmittedWithoutTun(t *testing.T) {
	o := gate.Option("O3")
	o.EnableTun = false
	c, _ := buildCfg(t, gate.LoadProfile(t, "P2"), o)
	if server(t, c, "dns-fake") != nil {
		t.Error("仅线路不该有 dns-fake")
	}
	for _, r := range c.DNS.Rules {
		if r.Server == "dns-fake" || len(r.Inbound) > 0 {
			t.Errorf("仅线路不该有引用 tun-in 的规则: %+v", r)
		}
	}
	// 没开 fake DNS 时同样没有。
	c, _ = buildCfg(t, gate.LoadProfile(t, "P2"), gate.Option("O1"))
	if server(t, c, "dns-fake") != nil {
		t.Error("没开 enable-fake-dns 不该有 dns-fake")
	}
}

// DNS 路由关闭时不为用户规则生成 DNS 规则。
func TestDNSRoutingOff(t *testing.T) {
	o := gate.Option("O3")
	o.EnableDNSRouting = false
	c, _ := buildCfg(t, gate.LoadProfile(t, "P2"), o)
	for _, r := range c.DNS.Rules {
		if r.Action == "predefined" || len(r.DomainKeyword) > 0 {
			t.Errorf("关闭 DNS 路由后不该有用户规则的 DNS 规则: %+v", r)
		}
	}
}

// domain strategy 默认不写；非空时只写在对应服务器的规则里。
func TestDNSDomainStrategyOnlyWhenSet(t *testing.T) {
	c, _ := buildCfg(t, gate.LoadProfile(t, "P2"), gate.Option("O3"))
	for _, r := range c.DNS.Rules {
		if r.Strategy != "" {
			t.Errorf("默认不该写 strategy: %+v", r)
		}
	}
	o := gate.Option("O3")
	o.DirectDNSDomainStrategy, o.RemoteDNSDomainStrategy = "prefer_ipv4", "ipv4_only"
	c, _ = buildCfg(t, gate.LoadProfile(t, "P2"), o)
	for _, r := range c.DNS.Rules {
		switch r.Server {
		case "dns-direct":
			if r.Strategy != "prefer_ipv4" {
				t.Errorf("直连规则 strategy = %q", r.Strategy)
			}
		case "dns-remote":
			if r.Strategy != "ipv4_only" {
				t.Errorf("远程规则 strategy = %q", r.Strategy)
			}
		default:
			if r.Strategy != "" {
				t.Errorf("其它规则不该有 strategy: %+v", r)
			}
		}
	}
}

func TestDNSStrategyFollowsIPv6Mode(t *testing.T) {
	for _, mode := range []string{"ipv4_only", "prefer_ipv4", "prefer_ipv6", "ipv6_only"} {
		o := gate.Option("O1")
		o.IPv6Mode = mode
		c, _ := buildCfg(t, gate.LoadProfile(t, "P1"), o)
		if c.DNS.Strategy != mode {
			t.Errorf("ipv6-mode %s → dns.strategy %q", mode, c.DNS.Strategy)
		}
	}
}

// independent-dns-cache 弃用且不写：用户改过它（偏离默认）时给一条 warning，默认值不制造噪声。
func TestDNSIndependentCacheWarning(t *testing.T) {
	_, w := buildCfg(t, gate.LoadProfile(t, "P1"), gate.Option("O1"))
	if len(w) != 0 {
		t.Errorf("默认选项不该有警告: %v", w)
	}
	o := gate.Option("O1")
	o.IndependentDNSCache = false
	raw, w, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv())
	if err != nil {
		t.Fatal(err)
	}
	if len(w) != 1 || !strings.HasPrefix(w[0], "independent-dns-cache-ignored:") {
		t.Errorf("warnings = %v", w)
	}
	if strings.Contains(string(raw), "independent_cache") {
		t.Error("配置里不该写 independent_cache")
	}
}
