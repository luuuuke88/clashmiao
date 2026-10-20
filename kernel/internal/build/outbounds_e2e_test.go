//go:build !race

// 出站装配的真流量测试：配置经 HostAdapt 副本真启动，断言实际走过的路径。
// 配置里有 urltest 组，在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），所以放在 !race 文件里。

package build_test

import (
	"fmt"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// startProfile 构建（节点 / 端点原样，不换假节点）、适配、真启动；返回 mixed-in 端口。
func startProfile(t *testing.T, p build.Profile, o *options.Options) (int, func(), interface {
	SelectOutbound(group, tag string) error
	URLTest(tag string) error
}) {
	t.Helper()
	o.EnableTun = false
	if err := o.Validate(); err != nil {
		t.Fatal(err)
	}
	raw, _, err := build.Build(p, o, build.AndroidEnv())
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
	if err := gate.CheckConfig(adapted); err != nil {
		t.Fatalf("CheckConfig: %v", err)
	}
	eng, _ := gate.NewEngine(t)
	if err := eng.Start(string(adapted)); err != nil {
		t.Fatalf("Start: %v", err)
	}
	groupsOf = func(what string, pred func(gate.Groups) bool) gate.Groups { return gate.WaitGroups(t, eng, what, pred) }
	watchGroups = func() *gate.GroupWatcher { return gate.WatchGroups(t, eng) }
	t.Cleanup(func() { _ = eng.Stop() })
	return ap.MixedPort, func() { _ = eng.Stop() }, eng
}

var (
	groupsOf    func(what string, pred func(gate.Groups) bool) gate.Groups
	watchGroups func() *gate.GroupWatcher
)

// (a) select 默认指向端点：首帧 selected 是端点的真实 tag（含 §default§ 标记的那个）；端点独占的订阅也能起得来。
//
// 限制：端点是 WireGuard，主机上没有对端实例，所以这里验证「装配与启动」而不是经端点的流量；
// 经端点的真流量留给 U13 的本地 WireGuard 对端测试。
func TestOutboundsE2EEndpointDefaultAndEndpointOnly(t *testing.T) {
	ep := func(tag string) map[string]any {
		e := wgEndpoint(tag)
		return e
	}
	t.Run("端点带 default 标记", func(t *testing.T) {
		p := build.Profile{Outbounds: []map[string]any{ssNode("a")}, Endpoints: []map[string]any{ep("wg-sg§default§")}}
		startProfile(t, p, gate.Option("O1"))
		g := groupsOf("select 的首帧", func(g gate.Groups) bool { return g.Find("select") != nil })
		sel := g.Find("select")
		if sel.Selected != "wg-sg§default§" {
			t.Errorf("selected = %q，期望端点的真实 tag", sel.Selected)
		}
		if got := strings.Join(sel.ItemTags(), ","); got != "auto,a,wg-sg§default§" {
			t.Errorf("select 成员 = %s", got)
		}
		if auto := g.Find("auto"); auto == nil || strings.Join(auto.ItemTags(), ",") != "a,wg-sg§default§" {
			t.Errorf("auto 成员 = %+v", auto)
		}
	})
	t.Run("端点独占", func(t *testing.T) {
		p := build.Profile{Endpoints: []map[string]any{ep("wg-1"), ep("wg-2")}}
		startProfile(t, p, gate.Option("O1"))
		g := groupsOf("select 的首帧", func(g gate.Groups) bool { return g.Find("select") != nil })
		if got := strings.Join(g.Find("select").ItemTags(), ","); got != "auto,wg-1,wg-2" {
			t.Errorf("select 成员 = %s", got)
		}
		if g.Find("select").Selected != "auto" {
			t.Errorf("selected = %q", g.Find("select").Selected)
		}
	})
}

// (b) 分片：enable-fragment 开时本地 TLS 目标看到 ClientHello 被拆成多条 TLS 记录；关时恰好 1 条；reality 节点不被加分片。
func TestOutboundsE2EFragmentSplitsClientHello(t *testing.T) {
	ca := e2e.NewCA(t)
	trojanTo := func(port int) map[string]any {
		return map[string]any{"type": "trojan", "tag": "frag-node", "server": "127.0.0.1", "server_port": port, "password": "x",
			"tls": map[string]any{"enabled": true, "server_name": "tls.example.net", "insecure": true}}
	}
	realityTo := func(port int) map[string]any {
		return map[string]any{"type": "vless", "tag": "reality-node", "server": "127.0.0.1", "server_port": port, "uuid": "11111111-2222-4333-8444-555555555555",
			"tls": map[string]any{"enabled": true, "server_name": "tls.example.net",
				"utls":    map[string]any{"enabled": true, "fingerprint": "chrome"},
				"reality": map[string]any{"enabled": true, "public_key": "ivDROKaq354cSx7DJ6wLY49DSI3S8pMXN47fhzmty4Y", "short_id": "0123abcd"}}}
	}
	records := func(l *e2e.Log) []int {
		var out []int
		for _, e := range l.Entries() {
			n, _ := strconv.Atoi(strings.TrimPrefix(e.Detail, "records="))
			out = append(out, n)
		}
		return out
	}
	run := func(t *testing.T, mkNode func(int) map[string]any, tag string, o *options.Options) []int {
		target := e2e.NewTLSRec(t, ca, "tls.example.net")
		traffic := e2e.NewHTTP(t)
		mixed, _, ctl := startProfile(t, build.Profile{Outbounds: []map[string]any{mkNode(target.Port)}}, o)
		if err := ctl.SelectOutbound("select", tag); err != nil {
			t.Fatal(err)
		}
		// 经 mixed-in 发一个请求：节点去拨 TLS 目标，ClientHello 先到；之后协议握手失败是预期的（目标不是真代理）。
		_, _ = gate.ProxyClient(mixed).Get(traffic.URL("127.0.0.1", "/x"))
		target.Log.MustWait(t, 1)
		return records(target.Log)
	}

	t.Run("关闭：1 条记录", func(t *testing.T) {
		for _, n := range run(t, trojanTo, "frag-node", gate.Option("O1")) {
			if n != 1 {
				t.Errorf("关闭分片时 ClientHello 应是 1 条 TLS 记录，实际 %d", n)
			}
		}
	})
	t.Run("开启：多于 1 条记录", func(t *testing.T) {
		for _, n := range run(t, trojanTo, "frag-node", gate.Option("O4")) {
			if n < 2 {
				t.Errorf("开启分片时 ClientHello 应被拆成 >= 2 条 TLS 记录，实际 %d", n)
			}
		}
	})
	t.Run("reality 节点不被加分片", func(t *testing.T) {
		for _, n := range run(t, realityTo, "reality-node", gate.Option("O4")) {
			if n != 1 {
				t.Errorf("reality 的 ClientHello 不该被拆: 记录数 %d", n)
			}
		}
	})
}

// (d) auto 选中延迟最低的假节点：node-slow 排在成员第一位（初始选中它）且人为注入 120 ms 链路延迟，
// 超出 urltest 默认的 50 ms 容差，auto 必须换到 node-fast。同步靠分组流的帧（事件），延迟只是被模拟的链路特性。
func TestOutboundsE2EAutoPicksTheFasterNode(t *testing.T) {
	slow := e2e.NewNode(t, "slow", nil)
	fast := e2e.NewNode(t, "fast", nil)
	slow.SetLatency(120 * time.Millisecond)
	probe := e2e.NewHTTP(t)

	o := gate.Option("O1")
	o.ConnectionTestURL = probe.URL("127.0.0.1", "/generate_204")
	p := build.Profile{Outbounds: []map[string]any{slow.Outbound("node-slow"), fast.Outbound("node-fast")}}
	_, _, ctl := startProfile(t, p, o)

	watch := watchGroups() // 先订阅再触发，不漏掉测速引起的帧
	if err := ctl.URLTest("auto"); err != nil {
		t.Fatal(err)
	}
	g := watch.Wait("auto 选中 node-fast 且两台都有结果", func(g gate.Groups) bool {
		a := g.Find("auto")
		return a != nil && a.Selected == "node-fast" && a.ItemDelay("node-slow") > 0 && a.ItemDelay("node-fast") > 0
	})
	a := g.Find("auto")
	if fd, sd := a.ItemDelay("node-fast"), a.ItemDelay("node-slow"); fd >= sd || sd < 120 {
		t.Errorf("node-fast %d ms 应小于 node-slow %d ms（慢节点含 120 ms 注入延迟）", fd, sd)
	}
	if fast.Log.Count(func(e e2e.Entry) bool { return e.Target == fmt.Sprintf("127.0.0.1:%d", probe.Port) }) == 0 {
		t.Error("node-fast 应该转发过探测")
	}
}
