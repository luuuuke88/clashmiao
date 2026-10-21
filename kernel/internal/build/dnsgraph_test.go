package build_test

import (
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
)

func baseConfig() *cfg.Config {
	return &cfg.Config{
		DNS: &cfg.DNS{Servers: []cfg.DNSServer{
			{Type: "https", Tag: "dns-remote", Server: "1.1.1.1", Path: "/dns-query", Detour: "select"},
			{Type: "udp", Tag: "dns-direct", Server: "223.5.5.5"},
		}, Final: "dns-remote"},
		Outbounds: []cfg.Outbound{
			{"type": "selector", "tag": "select", "outbounds": []any{"node"}, "default": "node"},
			{"type": "shadowsocks", "tag": "node", "server": "node.example.net", "server_port": 1},
			{"type": "direct", "tag": "direct"},
		},
		Route: &cfg.Route{DefaultDomainResolver: &cfg.DomainResolver{Server: "dns-direct"}},
	}
}

func wantDepError(t *testing.T, c *cfg.Config, substr string) {
	t.Helper()
	err := build.CheckDNSDeps(c)
	if err == nil {
		t.Fatalf("应当失败（含 %q）", substr)
	}
	if !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) || !strings.Contains(err.Error(), substr) {
		t.Fatalf("错误 = %v，期望 build-failed: 且含 %q", err, substr)
	}
}

func TestCheckDNSDepsAcceptsNormalConfig(t *testing.T) {
	if err := build.CheckDNSDeps(baseConfig()); err != nil {
		t.Fatal(err)
	}
	// 直连 DNS 为域名型 DoH，经 bootstrap 解析：合法。
	c := baseConfig()
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "doh.example.net", Path: "/dns-query", DomainResolver: "dns-bootstrap"}
	c.DNS.Servers = append(c.DNS.Servers, cfg.DNSServer{Type: "udp", Tag: "dns-bootstrap", Server: "223.5.5.5"})
	if err := build.CheckDNSDeps(c); err != nil {
		t.Fatal(err)
	}
}

// ①直连 DNS 为域名型 DoH 时，dns-direct.domain_resolver == dns-bootstrap（真构建产出）。
func TestDirectDoHDomainUsesBootstrap(t *testing.T) {
	c, _ := buildCfg(t, gate.LoadProfile(t, "P1"), gate.Option("O6-direct-doh-domain"))
	if s := server(t, c, "dns-direct"); s == nil || s.DomainResolver != "dns-bootstrap" || s.Server != "doh.example.net" {
		t.Fatalf("dns-direct = %+v", s)
	}
	if err := build.CheckDNSDeps(c); err != nil {
		t.Fatal(err)
	}
}

// ②自引用与间接环。
func TestCheckDNSDepsSelfReference(t *testing.T) {
	c := baseConfig()
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "doh.example.net", Path: "/dns-query", DomainResolver: "dns-direct"}
	wantDepError(t, c, "dns dependency cycle: dns-direct -> dns-direct")
}

func TestCheckDNSDepsIndirectCycle(t *testing.T) {
	c := baseConfig()
	c.DNS.Servers[0] = cfg.DNSServer{Type: "https", Tag: "dns-remote", Server: "a.example.net", Path: "/dns-query", DomainResolver: "dns-direct", Detour: "select"}
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "b.example.net", Path: "/dns-query", DomainResolver: "dns-remote"}
	err := build.CheckDNSDeps(c)
	if err == nil || !strings.Contains(err.Error(), "dns dependency cycle") ||
		!strings.Contains(err.Error(), "dns-remote") || !strings.Contains(err.Error(), "dns-direct") {
		t.Fatalf("err = %v", err)
	}
}

// 经 detour 与 default_domain_resolver 绕回自己：dns-remote 经 select 到域名节点，节点用 dns-remote 解析。
func TestCheckDNSDepsCycleThroughDetourAndDefaultResolver(t *testing.T) {
	c := baseConfig()
	c.Route.DefaultDomainResolver = &cfg.DomainResolver{Server: "dns-remote"}
	wantDepError(t, c, "dns dependency cycle: dns-remote -> select -> node -> dns-remote")
}

// 域名型服务器没写 domain_resolver，或链的终点不是 IP 字面量服务器。
func TestCheckDNSDepsResolverChainMustEndAtIP(t *testing.T) {
	c := baseConfig()
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "doh.example.net", Path: "/dns-query"}
	wantDepError(t, c, "no domain_resolver")

	c = baseConfig()
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "doh.example.net", Path: "/dns-query", DomainResolver: "dns-local"}
	c.DNS.Servers = append(c.DNS.Servers, cfg.DNSServer{Type: "local", Tag: "dns-local"})
	wantDepError(t, c, "not an IP-literal server")

	c = baseConfig()
	c.DNS.Servers[1] = cfg.DNSServer{Type: "https", Tag: "dns-direct", Server: "doh.example.net", Path: "/dns-query", DomainResolver: "dns-x"}
	c.DNS.Servers = append(c.DNS.Servers, cfg.DNSServer{Type: "udp", Tag: "dns-x", Server: "dns.example.net", DomainResolver: "dns-y"},
		cfg.DNSServer{Type: "udp", Tag: "dns-y", Server: "9.9.9.9"})
	// dns-direct → dns-x(域名) → dns-y(IP)：终点是 IP，合法。
	if err := build.CheckDNSDeps(c); err != nil {
		t.Fatalf("两级链终点是 IP，应合法: %v", err)
	}
}

func TestCheckDNSDepsMissingServers(t *testing.T) {
	c := baseConfig()
	c.Route.DefaultDomainResolver = &cfg.DomainResolver{Server: "ghost"}
	wantDepError(t, c, "not a dns server")
	c = baseConfig()
	c.DNS.Servers[0].DomainResolver = "ghost"
	c.DNS.Servers[0].Server = "x.example.net"
	wantDepError(t, c, "does not exist")
}

// ③bootstrap-dns-address 为域名被拒（选项层与构建层都拒）。
func TestBootstrapDomainRejected(t *testing.T) {
	o := gate.Option("O6-https-domain")
	o.BootstrapDNSAddress = "dns.example.net"
	if err := o.Validate(); err == nil {
		t.Error("选项层应拒绝域名自举地址")
	}
	if _, _, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv()); err == nil {
		t.Error("构建层应拒绝域名自举地址")
	}
}

// ④没有域名型服务器时不生成 dns-bootstrap；闸门不变量的「dns-bootstrap ⇔ 有域名型服务器」双向成立。
func TestNoBootstrapWithoutDomainServers(t *testing.T) {
	for _, name := range []string{"O1", "O6-ip", "O6-tcp", "O6-udp", "O6-local", "O6-https-ip"} {
		c, _ := buildCfg(t, gate.LoadProfile(t, "P1"), gate.Option(name))
		if server(t, c, "dns-bootstrap") != nil {
			t.Errorf("%s 不该生成 dns-bootstrap", name)
		}
	}
}

// 闸门的不变量里复用了同一份检查：把一份合法配置的 dns-direct 改成自引用，CheckInvariants 必须报。
func TestInvariantsReuseDNSDepsCheck(t *testing.T) {
	raw, o := gate.BuildCase(t, gate.Case{Name: "x", Profile: "P1", Option: "O6-direct-doh-domain"})
	bad := strings.Replace(string(raw), `"domain_resolver": "dns-bootstrap"`, `"domain_resolver": "dns-direct"`, 1)
	if bad == string(raw) {
		t.Fatal("夹具里没有可替换的 domain_resolver")
	}
	found := false
	for _, v := range gate.CheckInvariants([]byte(bad), o, build.AndroidEnv()) {
		if strings.Contains(v, "dns dependency cycle") {
			found = true
		}
	}
	if !found {
		t.Error("不变量没有抓住 DNS 依赖环")
	}
}

// 节点自己写的 domain_resolver（字符串或对象形式）才是它实际生效的解析器：
// dns-remote → select → node → dns-remote 在默认解析器是 dns-direct 时同样是环。
func TestCheckDNSDepsHonoursNodeDomainResolver(t *testing.T) {
	c := baseConfig()
	c.Outbounds[1]["domain_resolver"] = "dns-remote"
	wantDepError(t, c, "dns dependency cycle: dns-remote -> select -> node -> dns-remote")

	c = baseConfig()
	c.Outbounds[1]["domain_resolver"] = map[string]any{"server": "dns-remote", "strategy": "ipv4_only"}
	wantDepError(t, c, "dns dependency cycle: dns-remote -> select -> node -> dns-remote")

	// 指向直连 DNS（不经 select）合法，不能因为写了 domain_resolver 就误报。
	c = baseConfig()
	c.Outbounds[1]["domain_resolver"] = map[string]any{"server": "dns-direct"}
	if err := build.CheckDNSDeps(c); err != nil {
		t.Fatalf("节点显式用 dns-direct 应合法: %v", err)
	}
}

// 节点的 domain_resolver 指向不存在的服务器（订阅自己的 dns 块被丢弃后留下的悬空引用）。
func TestCheckDNSDepsNodeResolverMustExist(t *testing.T) {
	c := baseConfig()
	c.Outbounds[1]["domain_resolver"] = "sub-dns"
	wantDepError(t, c, `domain_resolver "sub-dns" is not a dns server`)

	c = baseConfig()
	c.Outbounds[1]["domain_resolver"] = map[string]any{"server": "sub-dns"}
	wantDepError(t, c, `domain_resolver "sub-dns" is not a dns server`)
}

// Build 端：订阅节点自带的 domain_resolver 一律去掉并给警告，运行配置里不会悬空，也不会被它改写解析路径。
func TestBuildDropsSubscriptionDomainResolvers(t *testing.T) {
	p := gate.LoadProfile(t, "P1")
	p.Outbounds = append([]map[string]any{}, p.Outbounds...)
	hit := false
	for i, n := range p.Outbounds {
		if _, ok := n["server"].(string); !ok {
			continue
		}
		m := map[string]any{}
		for k, v := range n {
			m[k] = v
		}
		m["domain_resolver"] = map[string]any{"server": "sub-dns", "strategy": "ipv4_only"}
		p.Outbounds[i] = m
		hit = true
		break
	}
	if !hit {
		t.Fatal("夹具里没有带 server 的节点")
	}
	c, warnings := buildCfg(t, p, gate.Option("O1"))
	for _, o := range c.Outbounds {
		if _, ok := o["domain_resolver"]; ok {
			t.Fatalf("%s 仍带 domain_resolver", o.Tag())
		}
	}
	found := false
	for _, w := range warnings {
		if strings.HasPrefix(w, "domain-resolver-dropped:") {
			found = true
		}
	}
	if !found {
		t.Errorf("缺少 domain-resolver-dropped 警告: %v", warnings)
	}
	if err := build.CheckDNSDeps(c); err != nil {
		t.Fatal(err)
	}
}
