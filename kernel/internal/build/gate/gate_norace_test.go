//go:build !race

// 这些测试要真起带 urltest 组（构建器产出的 auto）的配置，在 -race 下会撞上游的数据竞争
// （见 tools/kernel/gotest.sh），所以放在 !race 文件里，由 gotest.sh 的第二遍运行。

package gate

import (
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/engine"
	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
)

// live 是一个真起来的实例及它的本地目标。
type live struct {
	Node   *e2e.Node
	Target *e2e.HTTPTarget
	Engine *engine.Engine
	Mixed  int
}

// buildLive 构建 c 的配置（节点换成假节点、测速指向本地目标）并适配；mutate 可在适配前改原始配置（造反例）。
func buildLive(t *testing.T, c Case, mutateRaw func(raw []byte) []byte) (*live, []byte, AdaptOptions) {
	t.Helper()
	l := &live{Node: e2e.NewNode(t, "node-a", nil), Target: e2e.NewHTTP(t)}
	o := Option(c.Option)
	o.ConnectionTestURL = l.Target.URL("127.0.0.1", "/generate_204")
	raw, _, err := build.Build(UseFakeNodes(LoadProfile(t, c.Profile), l.Node), o, build.AndroidEnv())
	if err != nil {
		t.Fatal(err)
	}
	if mutateRaw != nil {
		raw = mutateRaw(raw)
	}
	adapted, ap, err := HostAdapt(raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	l.Mixed = ap.MixedPort
	return l, adapted, ap
}

func (l *live) start(t *testing.T, adapted []byte) error {
	t.Helper()
	l.Engine, _ = NewEngine(t)
	return l.Engine.Start(string(adapted))
}

func viaNode(target *e2e.HTTPTarget) func(e2e.Entry) bool {
	want := fmt.Sprintf("127.0.0.1:%d", target.Port)
	return func(e e2e.Entry) bool { return e.Target == want }
}

// 真 Start 一份构建器产出：首帧分组正确，手选与测速命令可用，经 mixed-in 的流量真的走了假节点、直连的不走，Stop 干净。
func TestRealStartP1O1Traffic(t *testing.T) {
	l, adapted, _ := buildLive(t, Case{"P1-O1", "P1", "O1"}, nil)
	if err := CheckConfig(adapted); err != nil {
		t.Fatalf("CheckConfig: %v", err)
	}
	if err := l.start(t, adapted); err != nil {
		t.Fatalf("Start: %v", err)
	}

	groups := FirstGroups(t, l.Engine)
	sel := groups.Find("select")
	if sel == nil {
		t.Fatalf("首帧没有 select 组: %+v", groups)
	}
	if got := strings.Join(sel.ItemTags(), ","); got != "auto,香港01" {
		t.Errorf("select 成员 = %s，期望 auto,香港01", got)
	}
	if sel.Selected != "auto" {
		t.Errorf("select 默认 = %q，期望 auto", sel.Selected)
	}
	if auto := groups.Find("auto"); auto == nil || auto.Type != "urltest" {
		t.Errorf("auto 组缺失或不是 urltest: %+v", auto)
	}

	if err := l.Engine.SelectOutbound("select", "香港01"); err != nil {
		t.Fatalf("SelectOutbound: %v", err)
	}
	if err := l.Engine.URLTest("auto"); err != nil {
		t.Fatalf("URLTest: %v", err)
	}

	// 经 mixed-in 的请求：目标收到，假节点记录里多一条。
	// 用一个独立的目标：l.Target 是测速目标，urltest 的探测也会经假节点到它那里，会混进计数。
	traffic := e2e.NewHTTP(t)
	before := l.Node.Log.Count(viaNode(traffic))
	status, body := Get(t, ProxyClient(l.Mixed), traffic.URL("127.0.0.1", "/hello"))
	if status != 200 || body != "ok" {
		t.Fatalf("经代理的请求 = %d %q", status, body)
	}
	if got := l.Node.Log.Count(viaNode(traffic)); got != before+1 {
		t.Errorf("假节点记录应多一条，before=%d after=%d: %v", before, got, l.Node.Log.Entries())
	}

	// 不经代理的请求不进假节点。
	n := l.Node.Log.Count(viaNode(traffic))
	if status, _ := Get(t, &http.Client{}, traffic.URL("127.0.0.1", "/direct")); status != 200 {
		t.Fatalf("直连请求 = %d", status)
	}
	if l.Node.Log.Count(viaNode(traffic)) != n {
		t.Errorf("直连请求不该出现在假节点记录里: %v", l.Node.Log.Entries())
	}

	if err := l.Engine.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
}

// 反例 1 的另一半：DNS 服务器 detour 指向空 direct，CheckConfig 放行，真 Start 拒绝。
func TestCounterexampleDNSDetourToEmptyDirectRejectedByStart(t *testing.T) {
	l, adapted, _ := buildLive(t, Case{"P1-O1", "P1", "O1"}, func(raw []byte) []byte {
		return mutate(t, raw, func(c map[string]any) {
			findOne(t, asMap(c["dns"])["servers"], "tag", "dns-direct")["detour"] = "direct"
		})
	})
	if err := CheckConfig(adapted); err != nil {
		t.Fatalf("前提不成立：CheckConfig 本应放行这个坏配置，却拒绝了: %v", err)
	}
	err := l.start(t, adapted)
	if err == nil {
		_ = l.Engine.Stop()
		t.Fatal("Start 应当拒绝「DNS 服务器 detour 指向空 direct」，却成功了")
	}
	t.Logf("Start 拒绝: %v", err)
	if !strings.HasPrefix(err.Error(), "start-service:") && !strings.HasPrefix(err.Error(), "create-service:") {
		t.Errorf("错误缺少稳定前缀: %v", err)
	}
}

// 反例 2 的另一半：selector 的 default 不在成员里，CheckConfig 放行，真 Start 拒绝。
func TestCounterexampleSelectorDefaultRejectedByStart(t *testing.T) {
	l, adapted, _ := buildLive(t, Case{"P1-O1", "P1", "O1"}, func(raw []byte) []byte {
		return mutate(t, raw, func(c map[string]any) {
			findOne(t, c["outbounds"], "tag", "select")["default"] = "§default§"
		})
	})
	if err := CheckConfig(adapted); err != nil {
		t.Fatalf("前提不成立：CheckConfig 本应放行这个坏配置，却拒绝了: %v", err)
	}
	err := l.start(t, adapted)
	if err == nil {
		_ = l.Engine.Stop()
		t.Fatal("Start 应当拒绝「selector default 不是成员」，却成功了")
	}
	t.Logf("Start 拒绝: %v", err)
}

// 「仅线路」配置真起得来，且分组正常（没有 tun 也不需要 TUN 权限）。
func TestRealStartLineOnly(t *testing.T) {
	l, adapted, _ := buildLive(t, Case{"P1-O2", "P1", "O2"}, nil)
	if err := l.start(t, adapted); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if FirstGroups(t, l.Engine).Find("select") == nil {
		t.Fatal("没有 select 组")
	}
	if err := l.Engine.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
}
