//go:build !race

// 真查询的 DNS 测试：配置经 HostAdapt 副本真启动，查询经 mixed-in 被 hijack-dns 接管后走真实的 DNS 规则。
// 配置里有 urltest 组，在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），所以放在 !race 文件里。

package build_test

import (
	"fmt"
	"strings"
	"testing"

	mdns "github.com/miekg/dns"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

const (
	nodeDomain   = "node.example.net" // 假节点的「服务器域名」：解析它走 dns-direct
	remoteDomain = "remote.example.net"
	dohDomain    = "doh.example.net"
)

// dnsWorld 是一组本地可控的 DNS / 目标，每个都带请求记录。
type dnsWorld struct {
	ca        *e2e.CA
	remoteDNS *e2e.DNS // 作为「远程 DNS」的 IP 服务器
	directDNS *e2e.DNS // 作为「直连 DNS」的 IP 服务器
	bootDNS   *e2e.DNS // 自举解析器：只认识 doh.example.net
	doh       *e2e.DoH
	node      *e2e.Node
	traffic   *e2e.HTTPTarget
}

func newDNSWorld(t *testing.T) *dnsWorld {
	t.Helper()
	w := &dnsWorld{ca: e2e.NewCA(t)}
	w.remoteDNS = e2e.NewDNS(t, e2e.NewRecords(map[string][]string{remoteDomain: {"192.0.2.77"}, nodeDomain: {"127.0.0.1"}}))
	w.directDNS = e2e.NewDNS(t, e2e.NewRecords(map[string][]string{nodeDomain: {"127.0.0.1"}, remoteDomain: {"192.0.2.78"}}))
	w.bootDNS = e2e.NewDNS(t, e2e.NewRecords(map[string][]string{dohDomain: {"127.0.0.1"}}))
	w.doh = e2e.NewDoH(t, w.ca, dohDomain, e2e.NewRecords(map[string][]string{nodeDomain: {"127.0.0.1"}, remoteDomain: {"192.0.2.88"}}))
	w.node = e2e.NewNode(t, "node-a", map[string]string{dohDomain: "127.0.0.1", nodeDomain: "127.0.0.1"})
	w.traffic = e2e.NewHTTP(t)
	return w
}

// profile：一个节点，其服务器地址是域名 node.example.net（经 DNS 才能连上假节点）。
func (w *dnsWorld) profile() build.Profile {
	n := w.node.Outbound("node-a")
	n["server"] = nodeDomain
	return build.Profile{Outbounds: []map[string]any{n}}
}

// start 构建、适配（可注入测试 CA）并真启动；返回 mixed-in 端口与引擎。
func (w *dnsWorld) start(t *testing.T, o *options.Options, mutate func(raw []byte) []byte) (int, interface{ Stop() error }, error) {
	t.Helper()
	o.ConnectionTestURL = w.traffic.URL("127.0.0.1", "/generate_204")
	o.EnableTun = false // 主机上没有 TUN；DNS 路径与 tun 无关
	if err := o.Validate(); err != nil {
		t.Fatalf("选项不合法: %v", err)
	}
	raw, _, err := build.Build(w.profile(), o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if mutate != nil {
		raw = mutate(raw)
	}
	adapted, ap, err := gate.HostAdapt(raw, gate.AdaptOptions{CAPEM: w.ca.PEM()})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := gate.CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("适配差异超出白名单: %v %v", err, bad)
	}
	if err := gate.CheckConfig(adapted); err != nil {
		t.Fatalf("CheckConfig: %v", err)
	}
	eng, _ := gate.NewEngine(t)
	return ap.MixedPort, eng, eng.Start(string(adapted))
}

func addrOf(d *e2e.DNS) string { return fmt.Sprintf("127.0.0.1:%d", d.Port) }

func queryA(t *testing.T, mixed int, name string) (string, error) {
	t.Helper()
	resp, err := gate.QueryDNSViaMixed(t, mixed, name, mdns.TypeA)
	if err != nil {
		return "", err
	}
	if resp.Rcode != mdns.RcodeSuccess || len(resp.Answer) == 0 {
		return "", fmt.Errorf("rcode=%s answers=%d", mdns.RcodeToString[resp.Rcode], len(resp.Answer))
	}
	return resp.Answer[0].(*mdns.A).A.String(), nil
}

func nodeConnectsTo(w *dnsWorld, port int) int {
	suffix := fmt.Sprintf(":%d", port)
	return w.node.Log.Count(func(e e2e.Entry) bool { return strings.HasSuffix(e.Target, suffix) })
}

func queriesFor(d *e2e.DNS, name string) int { return d.Queries(name) }

// (a) 直连 DNS 配成域名型 DoH：经 bootstrap 解析到本地回环，查询真的完成。
func TestE2EDirectDNSIsDomainDoH(t *testing.T) {
	w := newDNSWorld(t)
	o := gate.Option("O1")
	o.DirectDNSAddress = w.doh.URL()
	o.RemoteDNSAddress = "tcp://" + addrOf(w.remoteDNS)
	o.BootstrapDNSAddress = addrOf(w.bootDNS)
	mixed, eng, err := w.start(t, o, nil)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer eng.Stop()

	// 节点域名属于「直连域名」规则：由 dns-direct（DoH）回答。
	ip, err := queryA(t, mixed, nodeDomain)
	if err != nil || ip != "127.0.0.1" {
		t.Fatalf("经 hijack-dns 查询 %s = %q %v", nodeDomain, ip, err)
	}
	if w.doh.Log.Count(func(e e2e.Entry) bool { return e.Target == nodeDomain }) == 0 {
		t.Errorf("DoH 记录里应有 %s 的查询: %v", nodeDomain, w.doh.Log.Entries())
	}
	if queriesFor(w.bootDNS, dohDomain) == 0 {
		t.Errorf("自举 DNS 应收到 %s 的解析: %v", dohDomain, w.bootDNS.Log.Entries())
	}
	if n := queriesFor(w.remoteDNS, nodeDomain); n != 0 {
		t.Errorf("直连域名不该问远程 DNS，实际 %d 次", n)
	}
	if n := queriesFor(w.bootDNS, nodeDomain); n != 0 {
		t.Errorf("自举 DNS 只负责 DNS 服务器自己的域名，不该收到 %s: %d 次", nodeDomain, n)
	}
	if n := nodeConnectsTo(w, w.doh.Port); n != 0 {
		t.Errorf("直连 DNS 的 DoH 连接不该经过假节点: %d 次", n)
	}

	// 整条链：节点的服务器域名经 dns-direct（DoH）解析后，代理请求真的经过假节点到达目标。
	status, body := gate.Get(t, gate.ProxyClient(mixed), w.traffic.URL("127.0.0.1", "/hello"))
	if status != 200 || body != "ok" {
		t.Fatalf("经代理的请求 = %d %q", status, body)
	}
	if w.node.Log.Count(func(e e2e.Entry) bool { return e.Target == fmt.Sprintf("127.0.0.1:%d", w.traffic.Port) }) == 0 {
		t.Errorf("请求应出现在假节点记录里: %v", w.node.Log.Entries())
	}
}

// (b) 远程 DNS 配成域名型 DoH：同样完成，且 DoH 连接经 detour 走了代理（出现在假节点记录里）。
func TestE2ERemoteDNSIsDomainDoHThroughProxy(t *testing.T) {
	w := newDNSWorld(t)
	o := gate.Option("O1")
	o.RemoteDNSAddress = w.doh.URL()
	o.DirectDNSAddress = "udp://" + addrOf(w.directDNS)
	o.BootstrapDNSAddress = addrOf(w.bootDNS)
	mixed, eng, err := w.start(t, o, nil)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer eng.Stop()

	before := nodeConnectsTo(w, w.doh.Port)
	ip, err := queryA(t, mixed, remoteDomain)
	if err != nil || ip != "192.0.2.88" {
		t.Fatalf("经 hijack-dns 查询 %s = %q %v（应由远程 DoH 回答 192.0.2.88）", remoteDomain, ip, err)
	}
	if w.doh.Log.Count(func(e e2e.Entry) bool { return e.Target == remoteDomain }) == 0 {
		t.Errorf("DoH 记录里应有 %s: %v", remoteDomain, w.doh.Log.Entries())
	}
	if nodeConnectsTo(w, w.doh.Port) <= before {
		t.Errorf("远程 DoH 的连接应出现在假节点记录里（detour 走了代理）: %v", w.node.Log.Entries())
	}
	if n := queriesFor(w.directDNS, remoteDomain); n != 0 {
		t.Errorf("远程域名不该问直连 DNS: %d 次（泄漏）", n)
	}
	if queriesFor(w.bootDNS, dohDomain) == 0 {
		t.Errorf("自举 DNS 应收到 %s 的解析", dohDomain)
	}
}

// (c) 远程 DNS 为 IP + tcp://：查询经假节点到达本地 TCP DNS（出口是代理）；直连域名的查询不经假节点。
func TestE2ERemoteTCPDNSGoesThroughProxyDirectDoesNot(t *testing.T) {
	w := newDNSWorld(t)
	o := gate.Option("O1")
	o.RemoteDNSAddress = "tcp://" + addrOf(w.remoteDNS)
	o.DirectDNSAddress = "udp://" + addrOf(w.directDNS)
	mixed, eng, err := w.start(t, o, nil)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer eng.Stop()

	// 远程：走 dns-remote，经 detour（假节点）连到本地 TCP DNS。
	before := nodeConnectsTo(w, w.remoteDNS.Port)
	ip, err := queryA(t, mixed, remoteDomain)
	if err != nil || ip != "192.0.2.77" {
		t.Fatalf("远程查询 %s = %q %v", remoteDomain, ip, err)
	}
	if got := nodeConnectsTo(w, w.remoteDNS.Port); got <= before {
		t.Errorf("远程 DNS 的 TCP 连接应经过假节点: before=%d after=%d %v", before, got, w.node.Log.Entries())
	}
	if !w.remoteDNS.Log.Has(func(e e2e.Entry) bool { return e.Target == remoteDomain && e.Detail == "A/tcp" }) {
		t.Errorf("远程 DNS 应收到 TCP 查询: %v", w.remoteDNS.Log.Entries())
	}
	if n := queriesFor(w.directDNS, remoteDomain); n != 0 {
		t.Errorf("远程域名不该问直连 DNS: %d 次", n)
	}

	// 直连：节点域名走 dns-direct（UDP，直连），不经过假节点。
	nodeBefore := nodeConnectsTo(w, w.directDNS.Port)
	remoteBefore := queriesFor(w.remoteDNS, nodeDomain)
	ip, err = queryA(t, mixed, nodeDomain)
	if err != nil || ip != "127.0.0.1" {
		t.Fatalf("直连查询 %s = %q %v", nodeDomain, ip, err)
	}
	if got := nodeConnectsTo(w, w.directDNS.Port); got != nodeBefore {
		t.Errorf("直连 DNS 的查询不该经过假节点: before=%d after=%d", nodeBefore, got)
	}
	if got := queriesFor(w.remoteDNS, nodeDomain); got != remoteBefore {
		t.Errorf("直连域名不该问远程 DNS（泄漏）: before=%d after=%d", remoteBefore, got)
	}
	if !w.directDNS.Log.Has(func(e e2e.Entry) bool { return e.Target == nodeDomain && strings.HasSuffix(e.Detail, "/udp") }) {
		t.Errorf("直连 DNS 应收到 UDP 查询: %v", w.directDNS.Log.Entries())
	}
}

// (d) 自举解析器不可达：域名型 DoH 以明确的失败结束（不挂起，也不绕去别的解析器）。
func TestE2EUnreachableBootstrapFailsClearly(t *testing.T) {
	w := newDNSWorld(t)
	o := gate.Option("O1")
	o.DirectDNSAddress = w.doh.URL()
	o.RemoteDNSAddress = "tcp://" + addrOf(w.remoteDNS)
	o.BootstrapDNSAddress = fmt.Sprintf("127.0.0.1:%d", gate.FreeUDPPort(t))
	mixed, eng, err := w.start(t, o, nil)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer eng.Stop()

	ip, err := queryA(t, mixed, nodeDomain)
	if err == nil {
		t.Fatalf("自举不可达时查询不该成功，却得到 %s", ip)
	}
	t.Logf("明确失败: %v", err)
	if w.doh.Log.Len() != 0 {
		t.Errorf("没解析出 DoH 的地址，DoH 不该收到任何查询: %v", w.doh.Log.Entries())
	}
	if w.bootDNS.Log.Len() != 0 || w.remoteDNS.Log.Len() != 0 {
		t.Errorf("解析不该绕去别的服务器: boot=%v remote=%v", w.bootDNS.Log.Entries(), w.remoteDNS.Log.Entries())
	}
}

// 反例（DNS 版）：把 dns-direct 的 detour 改成 direct，不变量与真 Start 都拒绝（CheckConfig 放行）。
func TestE2ECounterexampleDirectDNSDetourDirect(t *testing.T) {
	w := newDNSWorld(t)
	o := gate.Option("O1")
	o.RemoteDNSAddress = "tcp://" + addrOf(w.remoteDNS)
	o.DirectDNSAddress = "udp://" + addrOf(w.directDNS)
	_, eng, err := w.start(t, o, func(raw []byte) []byte {
		bad := strings.Replace(string(raw), `"tag": "dns-direct",`, `"tag": "dns-direct",
        "detour": "direct",`, 1)
		if bad == string(raw) {
			t.Fatal("没找到可改的 dns-direct")
		}
		if vs := gate.CheckInvariants([]byte(bad), o, build.AndroidEnv()); !containsAny(vs, "指向空 direct") {
			t.Fatalf("不变量应抓住这个坏配置: %v", vs)
		}
		return []byte(bad)
	})
	if err == nil {
		_ = eng.Stop()
		t.Fatal("Start 应当拒绝 dns-direct 的 detour 指向空 direct")
	}
	t.Logf("Start 拒绝: %v", err)
}

func containsAny(list []string, substr string) bool {
	for _, s := range list {
		if strings.Contains(s, substr) {
			return true
		}
	}
	return false
}
