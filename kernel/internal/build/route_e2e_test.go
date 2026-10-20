//go:build !race

// 真流量测试：每条断言都查请求记录（目标、假节点、DNS），不只看 HTTP 200。
// 配置里有 urltest 组，在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），所以放在 !race 文件里。

package build_test

import (
	"fmt"
	"net/http"
	"strings"
	"testing"

	mdns "github.com/miekg/dns"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

type routeWorld struct {
	probe     *e2e.HTTPTarget // urltest 的探测目标（与业务目标分开，免得探测混进计数）
	target    *e2e.HTTPTarget
	nodeA     *e2e.Node
	nodeB     *e2e.Node
	directDNS *e2e.DNS
	remoteDNS *e2e.DNS
}

type routeRun struct {
	mixed   int
	dnsPort int
	eng     interface {
		Stop() error
		SelectOutbound(group, tag string) error
	}
}

func newRouteWorld(t *testing.T, records map[string][]string) *routeWorld {
	t.Helper()
	hosts := map[string]string{"proxied.example.net": "127.0.0.1", "remote.example.net": "127.0.0.1", "lan.example.net": "127.0.0.1"}
	w := &routeWorld{probe: e2e.NewHTTP(t), target: e2e.NewHTTP(t)}
	w.nodeA = e2e.NewNode(t, "node-a", hosts)
	w.nodeB = e2e.NewNode(t, "node-b", hosts)
	w.directDNS = e2e.NewDNS(t, e2e.NewRecords(records))
	w.remoteDNS = e2e.NewDNS(t, e2e.NewRecords(map[string][]string{"remote.example.net": {"192.0.2.77"}}))
	return w
}

func (w *routeWorld) profile() build.Profile {
	return build.Profile{Outbounds: []map[string]any{w.nodeA.Outbound("node-a"), w.nodeB.Outbound("node-b")}}
}

func (w *routeWorld) start(t *testing.T, mutate func(o *options.Options)) *routeRun {
	t.Helper()
	o := gate.Option("O1")
	o.EnableTun = false
	o.ConnectionTestURL = w.probe.URL("127.0.0.1", "/generate_204")
	o.DirectDNSAddress = "udp://" + addrOf(w.directDNS)
	o.RemoteDNSAddress = "tcp://" + addrOf(w.remoteDNS)
	o.Rules = []options.Rule{
		{Domains: "full:direct.example.net,full:dual.example.net", Outbound: "bypass"},
		{Domains: "full:blocked.example.net", Outbound: "block"},
	}
	if mutate != nil {
		mutate(o)
	}
	if err := o.Validate(); err != nil {
		t.Fatalf("选项不合法: %v", err)
	}
	raw, _, err := build.Build(w.profile(), o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	adapted, ap, err := gate.HostAdapt(raw, gate.AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := gate.CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("适配差异超出白名单: %v %v", err, bad)
	}
	eng, _ := gate.NewEngine(t)
	if err := eng.Start(string(adapted)); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = eng.Stop() })
	return &routeRun{mixed: ap.MixedPort, dnsPort: ap.DNSPort, eng: eng}
}

// seen 统计一个日志里目标等于 host:port 的条目数。
func seen(l *e2e.Log, hostPort string) int {
	return l.Count(func(e e2e.Entry) bool { return strings.HasPrefix(e.Target, hostPort) })
}

func (w *routeWorld) hostPort(host string) string { return fmt.Sprintf("%s:%d", host, w.target.Port) }

func getVia(t *testing.T, run *routeRun, rawURL string) (int, error) {
	t.Helper()
	resp, err := gate.ProxyClient(run.mixed).Get(rawURL)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}

// (a) bypass 命中的域名直连（节点记录为空）；未命中的走假节点。(b) block 命中被拒。
func TestRouteE2EBypassProxyBlock(t *testing.T) {
	w := newRouteWorld(t, map[string][]string{"direct.example.net": {"127.0.0.1"}})
	run := w.start(t, nil)
	if err := run.eng.SelectOutbound("select", "node-a"); err != nil {
		t.Fatal(err)
	}

	// bypass：目标收到、节点没有记录、直连 DNS 收到查询。
	direct := w.hostPort("direct.example.net")
	if code, err := getVia(t, run, "http://"+direct+"/a"); err != nil || code != 200 {
		t.Fatalf("bypass 请求 = %d %v", code, err)
	}
	if seen(w.target.Log, direct) != 1 {
		t.Errorf("目标应收到 1 次 bypass 请求: %v", w.target.Log.Entries())
	}
	if seen(w.nodeA.Log, direct)+seen(w.nodeB.Log, direct) != 0 {
		t.Errorf("bypass 的请求不该经过任何假节点: A=%v B=%v", w.nodeA.Log.Entries(), w.nodeB.Log.Entries())
	}
	if w.directDNS.Queries("direct.example.net") == 0 {
		t.Errorf("bypass 域名应由直连 DNS 解析: %v", w.directDNS.Log.Entries())
	}

	// 未命中：走所选假节点，由节点（Hosts）解析域名，本机直连 DNS 不被问到。
	proxied := w.hostPort("proxied.example.net")
	if code, err := getVia(t, run, "http://"+proxied+"/b"); err != nil || code != 200 {
		t.Fatalf("代理请求 = %d %v", code, err)
	}
	if seen(w.nodeA.Log, proxied) != 1 || seen(w.nodeB.Log, proxied) != 0 {
		t.Errorf("请求应只出现在所选节点 node-a 的记录里: A=%v B=%v", w.nodeA.Log.Entries(), w.nodeB.Log.Entries())
	}
	if w.directDNS.Queries("proxied.example.net") != 0 {
		t.Errorf("走代理的域名不该由本机解析（泄漏）: %v", w.directDNS.Log.Entries())
	}

	// block：请求失败，目标与节点都没有记录。
	blocked := w.hostPort("blocked.example.net")
	// mixed 入站对被 reject 的 HTTP 代理请求回 502（或直接断开）；两种都算「被拒」，关键是没有任何地方收到它。
	if code, err := getVia(t, run, "http://"+blocked+"/c"); err == nil && code < 500 {
		t.Fatalf("block 命中的请求应被拒，却得到 %d", code)
	}
	if seen(w.target.Log, blocked)+seen(w.nodeA.Log, blocked)+seen(w.nodeB.Log, blocked) != 0 {
		t.Errorf("被 block 的请求不该到达任何地方")
	}
}

// (c) bypass-lan 开 / 关：私有（含回环）地址目标直连 / 走代理。
func TestRouteE2EBypassLANTwoStates(t *testing.T) {
	for _, on := range []bool{false, true} {
		t.Run(fmt.Sprintf("bypass-lan=%v", on), func(t *testing.T) {
			w := newRouteWorld(t, map[string][]string{})
			run := w.start(t, func(o *options.Options) { o.BypassLAN = on })
			if err := run.eng.SelectOutbound("select", "node-a"); err != nil {
				t.Fatal(err)
			}
			lan := w.hostPort("127.0.0.1")
			if code, err := getVia(t, run, "http://"+lan+"/lan"); err != nil || code != 200 {
				t.Fatalf("请求 = %d %v", code, err)
			}
			viaNode := seen(w.nodeA.Log, lan)
			if on && viaNode != 0 {
				t.Errorf("开启 bypass-lan：私有地址应直连，不该出现在节点记录: %v", w.nodeA.Log.Entries())
			}
			if !on && viaNode != 1 {
				t.Errorf("关闭 bypass-lan：私有地址按常规走代理，节点记录应有 1 条，实际 %d", viaNode)
			}
			if seen(w.target.Log, lan) != 1 {
				t.Errorf("目标都应收到请求: %v", w.target.Log.Entries())
			}
		})
	}
}

// (d) dns-in 的查询被劫持：直接向 dns-in 发 DNS 查询，由 DNS 规则回答，出口与 U5 一致
// （直连域名问直连 DNS，其它问远程 DNS 且经假节点）。
func TestRouteE2EDNSInIsHijacked(t *testing.T) {
	w := newRouteWorld(t, map[string][]string{"direct.example.net": {"127.0.0.1"}})
	run := w.start(t, nil)
	if err := run.eng.SelectOutbound("select", "node-a"); err != nil {
		t.Fatal(err)
	}
	ask := func(name string) *mdns.Msg {
		t.Helper()
		m := new(mdns.Msg)
		m.SetQuestion(mdns.Fqdn(name), mdns.TypeA)
		resp, _, err := (&mdns.Client{Net: "udp"}).Exchange(m, fmt.Sprintf("127.0.0.1:%d", run.dnsPort))
		if err != nil {
			t.Fatalf("向 dns-in 查询 %s: %v", name, err)
		}
		return resp
	}

	if r := ask("direct.example.net"); len(r.Answer) != 1 || r.Answer[0].(*mdns.A).A.String() != "127.0.0.1" {
		t.Fatalf("direct.example.net 应由直连 DNS 回答: %v", r)
	}
	if w.directDNS.Queries("direct.example.net") == 0 || w.remoteDNS.Queries("direct.example.net") != 0 {
		t.Errorf("直连域名应只问直连 DNS: direct=%v remote=%v", w.directDNS.Log.Entries(), w.remoteDNS.Log.Entries())
	}

	before := seen(w.nodeA.Log, fmt.Sprintf("127.0.0.1:%d", w.remoteDNS.Port))
	if r := ask("remote.example.net"); len(r.Answer) != 1 || r.Answer[0].(*mdns.A).A.String() != "192.0.2.77" {
		t.Fatalf("remote.example.net 应由远程 DNS 回答: %v", r)
	}
	if w.remoteDNS.Queries("remote.example.net") == 0 || w.directDNS.Queries("remote.example.net") != 0 {
		t.Errorf("其它域名应只问远程 DNS: direct=%v remote=%v", w.directDNS.Log.Entries(), w.remoteDNS.Log.Entries())
	}
	if after := seen(w.nodeA.Log, fmt.Sprintf("127.0.0.1:%d", w.remoteDNS.Port)); after <= before {
		t.Errorf("远程 DNS 的连接应经过假节点: before=%d after=%d", before, after)
	}
}

// (e) 手选换节点后，新请求出现在另一台假节点的记录里。
func TestRouteE2ESelectSwitchesNode(t *testing.T) {
	w := newRouteWorld(t, map[string][]string{})
	run := w.start(t, nil)
	hit := func(path string) string { return w.hostPort("proxied.example.net") + path }

	if err := run.eng.SelectOutbound("select", "node-a"); err != nil {
		t.Fatal(err)
	}
	if code, err := getVia(t, run, "http://"+hit("/1")); err != nil || code != 200 {
		t.Fatalf("%d %v", code, err)
	}
	a1, b1 := seen(w.nodeA.Log, w.hostPort("proxied.example.net")), seen(w.nodeB.Log, w.hostPort("proxied.example.net"))
	if a1 != 1 || b1 != 0 {
		t.Fatalf("选 node-a 后请求应只在 A: A=%d B=%d", a1, b1)
	}

	if err := run.eng.SelectOutbound("select", "node-b"); err != nil {
		t.Fatal(err)
	}
	if code, err := getVia(t, run, "http://"+hit("/2")); err != nil || code != 200 {
		t.Fatalf("%d %v", code, err)
	}
	a2, b2 := seen(w.nodeA.Log, w.hostPort("proxied.example.net")), seen(w.nodeB.Log, w.hostPort("proxied.example.net"))
	if a2 != 1 || b2 != 1 {
		t.Errorf("换成 node-b 后新请求应只在 B: A=%d B=%d", a2, b2)
	}
}

// (f) IPv6：同一名称 A 与 AAAA 并存，v4 与 v6 回环各有一个目标。ipv4_only 只记录到 v4，prefer_ipv6 记录到 v6。
func TestRouteE2EIPv6Modes(t *testing.T) {
	var v4, v6 *e2e.HTTPTarget
	for i := 0; i < 20 && v6 == nil; i++ {
		v4 = e2e.NewHTTP(t)
		var err error
		if v6, err = e2e.NewHTTPOnPort(t, "::1", v4.Port); err != nil {
			if i == 0 && strings.Contains(err.Error(), "address family") || strings.Contains(err.Error(), "cannot assign") || strings.Contains(err.Error(), "not supported") {
				t.Skipf("本机没有可用的 IPv6 回环，跳过 v6 路径: %v", err)
			}
			v6 = nil
		}
	}
	if v6 == nil {
		t.Skip("找不到 v4 与 v6 回环上都空闲的同一个端口，跳过 v6 路径")
	}
	for _, tc := range []struct {
		mode        string
		wantV4Hits  int
		wantV6Hits  int
		wantAAAAQry bool
	}{
		{"ipv4_only", 1, 0, false},
		{"prefer_ipv6", 0, 1, true},
	} {
		t.Run(tc.mode, func(t *testing.T) {
			w := newRouteWorld(t, map[string][]string{"dual.example.net": {"127.0.0.1", "::1"}})
			run := w.start(t, func(o *options.Options) { o.IPv6Mode = tc.mode })
			url := fmt.Sprintf("http://dual.example.net:%d/v6", v4.Port)
			before4, before6 := seen(v4.Log, fmt.Sprintf("dual.example.net:%d", v4.Port)), seen(v6.Log, fmt.Sprintf("dual.example.net:%d", v4.Port))
			if code, err := getVia(t, run, url); err != nil || code != 200 {
				t.Fatalf("请求 = %d %v", code, err)
			}
			got4 := seen(v4.Log, fmt.Sprintf("dual.example.net:%d", v4.Port)) - before4
			got6 := seen(v6.Log, fmt.Sprintf("dual.example.net:%d", v4.Port)) - before6
			if got4 != tc.wantV4Hits || got6 != tc.wantV6Hits {
				t.Errorf("%s: v4 命中 %d（期望 %d），v6 命中 %d（期望 %d）；DNS 记录 %v", tc.mode, got4, tc.wantV4Hits, got6, tc.wantV6Hits, w.directDNS.Log.Entries())
			}
			sawAAAA := w.directDNS.Log.Has(func(e e2e.Entry) bool { return strings.HasPrefix(e.Detail, "AAAA/") })
			if sawAAAA != tc.wantAAAAQry {
				t.Errorf("%s: AAAA 查询 = %v，期望 %v", tc.mode, sawAAAA, tc.wantAAAAQry)
			}
		})
	}
}

// 全量智能分流清单（7.5k CIDR + 域名）：真启动，配置体积与启动结果记在日志里。
func TestRouteE2ECNDirectFullRulesStart(t *testing.T) {
	w := newRouteWorld(t, map[string][]string{})
	run := w.start(t, func(o *options.Options) {
		full := cnDirectOptions(t)
		o.Rules, o.EnableDNSRouting = full.Rules, true
	})
	if err := run.eng.SelectOutbound("select", "node-a"); err != nil {
		t.Fatal(err)
	}
	// 清单里没有的域名仍走代理；回环地址不在国内 IP 段里。
	if code, err := getVia(t, run, "http://"+w.hostPort("proxied.example.net")+"/x"); err != nil || code != 200 {
		t.Fatalf("全量清单下的代理请求 = %d %v", code, err)
	}
	if seen(w.nodeA.Log, w.hostPort("proxied.example.net")) != 1 {
		t.Errorf("请求应经节点: %v", w.nodeA.Log.Entries())
	}
	_ = http.StatusOK
}
