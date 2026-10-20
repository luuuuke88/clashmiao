//go:build !race

// WARP 真流量验证（spec §5.2.2）：测试进程里再起一个 sing-box 实例当假 WARP 对端（WireGuard 端点），
// 再起假节点（本地 SOCKS 上游，带 UDP ASSOCIATE），被测配置的适配副本经 engine 真起。
// 每条断言都查请求记录：隧道里的每个目标都会记在 exit 节点的 Log 里，节点收到的 UDP 记在 node 的 Log 里。
// 配置里有 urltest 组，在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），所以放在 !race 文件里。
//
// 地址约定：隧道里的「远端」用保留的假地址（192.0.2.80 目标、192.0.2.53 远程 DNS、198.51.100.7 节点自己），
// 由 exit / node 的 Hosts 映射到回环；真能直连的只有 127.0.0.1。所以「经隧道到达」可以由请求记录证明，
// 而不是靠碰巧能连上。

package build_test

import (
	"fmt"
	"testing"

	mdns "github.com/miekg/dns"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

const (
	fakeTarget = "192.0.2.80" // 业务目标（经代理 / 隧道才到得了）
	fakeDNS    = "192.0.2.53" // 远程 DNS
	fakeProbe  = "192.0.2.99" // urltest 的探测目标
	fakeNodeIP = "198.51.100.7"
)

type warpWorld struct {
	target, direct, probe *e2e.HTTPTarget
	remoteDNS, directDNS  *e2e.DNS
	node, exit            *e2e.Node
	peer                  *e2e.WGPeer
}

func newWarpWorld(t *testing.T) *warpWorld {
	t.Helper()
	w := &warpWorld{target: e2e.NewHTTP(t), direct: e2e.NewHTTP(t), probe: e2e.NewHTTP(t)}
	w.remoteDNS = e2e.NewDNS(t, e2e.NewRecords(map[string][]string{"probe.example.net": {"192.0.2.77"}}))
	w.directDNS = e2e.NewDNS(t, e2e.NewRecords(nil))
	loopback := map[string]string{fakeTarget: "127.0.0.1", fakeDNS: "127.0.0.1", fakeProbe: "127.0.0.1", fakeNodeIP: "127.0.0.1"}
	w.node = e2e.NewNode(t, "node", loopback)
	w.exit = e2e.NewNode(t, "warp-exit", loopback)
	w.peer = e2e.NewWGPeer(t, w.exit)
	return w
}

type warpRun struct {
	mixed int
	eng   interface {
		Stop() error
		SelectOutbound(group, tag string) error
	}
	raw      []byte
	warnings []string
}

// start 构建并真起。nodeServer 是订阅里节点的地址：warp_over_proxy 下节点是 WG 外层 UDP 的载体，要能直连（127.0.0.1）；
// proxy_over_warp 下节点只能经隧道到达（假地址）。mode 为空表示不启用 WARP。
func (w *warpWorld) start(t *testing.T, mode, nodeServer string) *warpRun {
	t.Helper()
	opt := gate.Option("O1")
	switch mode {
	case options.WarpProxyOverWarp, options.WarpWarpOverProxy:
		opt.Warp.Enable, opt.Warp.Mode = true, mode
		opt.Warp.WireguardConfig = w.peer.ClientConfig()
		opt.Warp.CleanIP, opt.Warp.CleanPort = "127.0.0.1", w.peer.Port
	}
	opt.EnableTun = false
	opt.ConnectionTestURL = w.probe.URL(fakeProbe, "/generate_204")
	opt.DirectDNSAddress = "udp://" + w.directDNS.Addr()
	opt.RemoteDNSAddress = fmt.Sprintf("tcp://%s:%d", fakeDNS, w.remoteDNS.Port)
	opt.Rules = []options.Rule{{IP: "127.0.0.1/32", Outbound: options.TargetBypass}}
	if err := opt.Validate(); err != nil {
		t.Fatalf("选项不合法: %v", err)
	}
	nodeOut := w.node.Outbound("node-n")
	nodeOut["server"] = nodeServer
	raw, warnings, err := build.Build(build.Profile{Outbounds: []map[string]any{nodeOut}}, opt, build.AndroidEnv())
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
	if err := eng.SelectOutbound("select", "node-n"); err != nil {
		t.Fatal(err)
	}
	return &warpRun{mixed: ap.MixedPort, eng: eng, raw: raw, warnings: warnings}
}

func (w *warpWorld) get(t *testing.T, r *warpRun, rawURL string) {
	t.Helper()
	resp, err := gate.ProxyClient(r.mixed).Get(rawURL)
	if err != nil {
		t.Fatalf("GET %s: %v", rawURL, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("GET %s = %d", rawURL, resp.StatusCode)
	}
}

func hostPort(host string, port int) string { return fmt.Sprintf("%s:%d", host, port) }

func has(l *e2e.Log, kind, target string) bool {
	return l.Has(func(e e2e.Entry) bool { return e.Kind == kind && e.Target == target })
}

// 业务请求经 WARP 的路径断言之后，再核对直连规则命中的目标两处记录都为空，且远程 DNS 的路径。
func (w *warpWorld) checkDirectBypass(t *testing.T, r *warpRun) {
	t.Helper()
	dt := hostPort("127.0.0.1", w.direct.Port)
	w.get(t, r, "http://"+dt+"/direct")
	if !w.direct.Log.Has(func(e e2e.Entry) bool { return e.Target == dt+"/direct" }) {
		t.Errorf("直连目标没收到请求: %v", w.direct.Log.Entries())
	}
	for name, l := range map[string]*e2e.Log{"假节点": w.node.Log, "WARP 出口": w.exit.Log} {
		if l.Has(func(e e2e.Entry) bool { return e.Target == dt }) {
			t.Errorf("直连规则命中的目标不该出现在%s的记录里: %v", name, l.Entries())
		}
	}
}

func (w *warpWorld) queryRemoteDNS(t *testing.T, r *warpRun) {
	t.Helper()
	resp, err := gate.QueryDNSViaMixed(t, r.mixed, "probe.example.net", mdns.TypeA)
	if err != nil {
		t.Fatalf("DNS 查询: %v", err)
	}
	if len(resp.Answer) != 1 || resp.Answer[0].(*mdns.A).A.String() != "192.0.2.77" {
		t.Fatalf("DNS 应答 = %v", resp.Answer)
	}
	if w.remoteDNS.Queries("probe.example.net") == 0 {
		t.Fatalf("远程 DNS 没收到查询: %v", w.remoteDNS.Log.Entries())
	}
}

// warp_over_proxy：业务流量先进 WARP 隧道，隧道的外层 UDP 经所选节点（UDP ASSOCIATE）到达对端，再由对端出口访问目标。
func TestWarpE2EWarpOverProxy(t *testing.T) {
	w := newWarpWorld(t)
	r := w.start(t, options.WarpWarpOverProxy, "127.0.0.1")
	if vs, err := build.CheckWarpGraph(r.raw, mustPolicy(t, options.WarpWarpOverProxy)); err != nil || len(vs) != 0 {
		t.Fatalf("图断言: %v %v", err, vs)
	}

	tgt := hostPort(fakeTarget, w.target.Port)
	w.get(t, r, "http://"+tgt+"/hello")

	// 1) 假节点收到的是 WG 外层 UDP（目标是对端的回环口），而不是业务目标的 TCP CONNECT。
	peerAddr := hostPort("127.0.0.1", w.peer.Port)
	if !has(w.node.Log, "socks-udp", peerAddr) {
		t.Errorf("假节点应收到发往 WARP 对端 %s 的 UDP 关联数据报: %v", peerAddr, w.node.Log.Entries())
	}
	if has(w.node.Log, "socks", tgt) {
		t.Errorf("业务目标不该作为 TCP CONNECT 出现在假节点上（应封在隧道里）: %v", w.node.Log.Entries())
	}
	// 2) 业务目标经隧道到达：WARP 出口记录了它，目标也收到了请求。
	if !has(w.exit.Log, "socks", tgt) {
		t.Errorf("WARP 出口应记录隧道里的目标 %s: %v", tgt, w.exit.Log.Entries())
	}
	if !w.target.Log.Has(func(e e2e.Entry) bool { return e.Target == tgt+"/hello" }) {
		t.Errorf("目标没收到请求: %v", w.target.Log.Entries())
	}

	// 3) 远程 DNS 同走 warp（dns-remote.detour = warp，spec R12 的 DNS 假设用真流量证实）。
	w.queryRemoteDNS(t, r)
	if !has(w.exit.Log, "socks", hostPort(fakeDNS, w.remoteDNS.Port)) {
		t.Errorf("远程 DNS 的连接应经 WARP 隧道出去: %v", w.exit.Log.Entries())
	}

	// 4) 直连规则命中的目标：节点与出口都没有记录。
	w.checkDirectBypass(t, r)
}

// proxy_over_warp：先过 WARP（直连对端），再经节点：节点本身只能经隧道到达，业务目标经节点。
func TestWarpE2EProxyOverWarp(t *testing.T) {
	w := newWarpWorld(t)
	r := w.start(t, options.WarpProxyOverWarp, fakeNodeIP)
	if vs, err := build.CheckWarpGraph(r.raw, mustPolicy(t, options.WarpProxyOverWarp)); err != nil || len(vs) != 0 {
		t.Fatalf("图断言: %v %v", err, vs)
	}

	tgt := hostPort(fakeTarget, w.target.Port)
	w.get(t, r, "http://"+tgt+"/hello")

	// 1) 节点的地址（假地址，直连根本到不了）是经隧道访问的：WARP 出口记录了它。
	nodeAddr := hostPort(fakeNodeIP, w.node.Port)
	if !has(w.exit.Log, "socks", nodeAddr) {
		t.Errorf("WARP 出口应记录经隧道访问节点 %s: %v", nodeAddr, w.exit.Log.Entries())
	}
	// 2) 业务目标经节点：节点记录了它，WARP 出口没有直接记录它（它在节点之后，不在隧道里）。
	if !has(w.node.Log, "socks", tgt) {
		t.Errorf("业务目标应经假节点到达: %v", w.node.Log.Entries())
	}
	if has(w.exit.Log, "socks", tgt) {
		t.Errorf("业务目标不该直接出现在 WARP 出口上（它由节点代为访问）: %v", w.exit.Log.Entries())
	}
	if w.node.Log.Has(func(e e2e.Entry) bool { return e.Kind == "socks-udp" }) {
		t.Errorf("本模式不该有 UDP 关联: %v", w.node.Log.Entries())
	}
	if !w.target.Log.Has(func(e e2e.Entry) bool { return e.Target == tgt+"/hello" }) {
		t.Errorf("目标没收到请求: %v", w.target.Log.Entries())
	}

	// 3) 远程 DNS 经 select（节点），节点再经隧道。
	w.queryRemoteDNS(t, r)
	if !has(w.node.Log, "socks", hostPort(fakeDNS, w.remoteDNS.Port)) {
		t.Errorf("远程 DNS 应经所选节点: %v", w.node.Log.Entries())
	}

	// 4) 直连规则命中的目标：节点与出口都没有记录。
	w.checkDirectBypass(t, r)
}

// 关闭 WARP：路径退回常态——节点直连，隧道出口与 UDP 关联都没有任何记录。
func TestWarpE2EDisabledFallsBackToPlainProxy(t *testing.T) {
	w := newWarpWorld(t)
	r := w.start(t, "", "127.0.0.1")
	tgt := hostPort(fakeTarget, w.target.Port)
	w.get(t, r, "http://"+tgt+"/hello")
	if !has(w.node.Log, "socks", tgt) {
		t.Errorf("常态下业务目标应经假节点: %v", w.node.Log.Entries())
	}
	if w.exit.Log.Len() != 0 {
		t.Errorf("没有 WARP 时隧道出口不该有任何记录: %v", w.exit.Log.Entries())
	}
	if w.node.Log.Has(func(e e2e.Entry) bool { return e.Kind == "socks-udp" }) {
		t.Errorf("没有 WARP 时不该有 UDP 关联: %v", w.node.Log.Entries())
	}
}

func mustPolicy(t *testing.T, mode string) build.WarpPolicy {
	t.Helper()
	o := gate.Option("O1")
	o.Warp.Enable, o.Warp.Mode = true, mode
	p, ok := build.PolicyFor(o)
	if !ok {
		t.Fatalf("没有模式 %s 的策略", mode)
	}
	return p
}
