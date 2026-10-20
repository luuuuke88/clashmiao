//go:build !race

package core_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	mdns "github.com/miekg/dns"

	"github.com/luuuuke88/clashmiao/kernel/core"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
)

// 订阅解析出的配置带 auto（urltest），官方 urltest 在启动时有已知的上游数据竞争，
// 所以这些真启动测试只在 gotest.sh 的第二遍（无 -race）跑；不带 urltest 的并发逻辑见 core_race_test.go。

type groupsCh chan string

func (c groupsCh) OnGroups(j string)         { c <- j }
func (c groupsCh) OnDisconnected(msg string) {}

type statsCh chan string

func (c statsCh) OnStats(j string)          { c <- j }
func (c statsCh) OnDisconnected(msg string) {}

func recvString(t *testing.T, ch <-chan string, what string) string {
	t.Helper()
	select {
	case s := <-ch:
		return s
	case <-time.After(30 * time.Second): // 失败兜底，不是等待手段
		t.Fatalf("等待%s超时", what)
		return ""
	}
}

// 端到端（Go 内）：Parse 合成订阅 → BuildConfig → 适配副本 CheckConfig → NewEngine + Start（无 tun）→ 分组首帧 / 统计帧 / 日志；
// 手选经门面生效；Stop / Close / 订阅 Close 都幂等且无错。
func TestEndToEndStartViaFacade(t *testing.T) {
	out := filepath.Join(t.TempDir(), "profile.json")
	if err := core.Parse(out, subscriptionFixture("singbox-full.json"), false); err != nil {
		t.Fatal(err)
	}
	content, err := core.BuildConfig(out, `{}`)
	if err != nil {
		t.Fatal(err)
	}
	adapted := checkBuilt(t, content, `{}`)

	host := newTestHost()
	e := newCoreEngine(t, host)
	if err := e.Start(string(adapted)); err != nil {
		t.Fatalf("Start: %v", err)
	}

	gch := make(groupsCh, 16)
	gsub, err := e.SubscribeGroups(gch)
	if err != nil {
		t.Fatal(err)
	}
	var groups []struct {
		Tag      string `json:"tag"`
		Selected string `json:"selected"`
		Items    []struct {
			Tag string `json:"tag"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(recvString(t, gch, "分组首帧")), &groups); err != nil {
		t.Fatalf("分组首帧不是 JSON: %v", err)
	}
	var sel *struct {
		Tag      string `json:"tag"`
		Selected string `json:"selected"`
		Items    []struct {
			Tag string `json:"tag"`
		} `json:"items"`
	}
	for i := range groups {
		if groups[i].Tag == "select" {
			sel = &groups[i]
		}
	}
	if sel == nil || len(sel.Items) < 2 {
		t.Fatalf("没有可用的 select 组: %+v", groups)
	}

	// 手选一个非当前成员，再看到分组帧里 selected 变化
	var pick string
	for _, it := range sel.Items {
		if it.Tag != sel.Selected {
			pick = it.Tag
			break
		}
	}
	if err := e.SelectOutbound("select", pick); err != nil {
		t.Fatalf("SelectOutbound: %v", err)
	}
	for {
		var g []struct {
			Tag      string `json:"tag"`
			Selected string `json:"selected"`
		}
		if err := json.Unmarshal([]byte(recvString(t, gch, "手选后的分组帧")), &g); err != nil {
			t.Fatal(err)
		}
		done := false
		for _, x := range g {
			if x.Tag == "select" && x.Selected == pick {
				done = true
			}
		}
		if done {
			break
		}
	}

	sch := make(statsCh, 16)
	ssub, err := e.SubscribeStats(sch, 200)
	if err != nil {
		t.Fatal(err)
	}
	var stats map[string]any
	if err := json.Unmarshal([]byte(recvString(t, sch, "统计帧")), &stats); err != nil {
		t.Fatalf("统计帧不是 JSON: %v", err)
	}
	for _, k := range []string{"uplink", "downlink", "uplink-total", "downlink-total", "connections-in", "connections-out"} {
		if _, ok := stats[k]; !ok {
			t.Errorf("统计帧缺少键 %s: %v", k, stats)
		}
	}

	if err := e.URLTest("auto"); err != nil {
		t.Errorf("URLTest: %v", err)
	}

	for name, c := range map[string]func() error{"groups": gsub.Close, "stats": ssub.Close} {
		if err := c(); err != nil {
			t.Errorf("%s Subscription.Close: %v", name, err)
		}
		if err := c(); err != nil {
			t.Errorf("%s Subscription.Close（第二次）: %v", name, err)
		}
	}
	if err := e.Stop(); err != nil {
		t.Errorf("Stop: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Errorf("Close: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Errorf("Close（第二次）应返回 nil: %v", err)
	}
	// 接口监视被宿主收掉：启动一次、停止至少一次
	if host.monitorStops.Load() < 1 {
		t.Error("StopInterfaceMonitor 没有被调用")
	}
}

// Engine 自己关订阅（Stop / Close）时不触发 OnDisconnected——重连策略在 Kotlin，自己关的不该被当成断线重连；
// 其后订阅再 Close 也是 nil。真正的断线转发由 engine 包的测试锁定，门面的接口声明由编译期断言保证。
type discCh struct {
	groupsCh
	disc chan string
}

func (d discCh) OnDisconnected(msg string) { d.disc <- msg }

func TestEngineStopClosesSubscriptionsWithoutDisconnectCallback(t *testing.T) {
	out := filepath.Join(t.TempDir(), "profile.json")
	if err := core.Parse(out, subscriptionFixture("singbox-single.json"), false); err != nil {
		t.Fatal(err)
	}
	content, err := core.BuildConfig(out, `{}`)
	if err != nil {
		t.Fatal(err)
	}
	adapted := checkBuilt(t, content, `{}`)
	e := newCoreEngine(t, newTestHost())
	if err := e.Start(string(adapted)); err != nil {
		t.Fatal(err)
	}
	h := discCh{groupsCh: make(groupsCh, 16), disc: make(chan string, 4)}
	sub, err := e.SubscribeGroups(h)
	if err != nil {
		t.Fatal(err)
	}
	recvString(t, h.groupsCh, "分组首帧")
	if err := e.Stop(); err != nil {
		t.Fatal(err)
	}
	// Stop 会等订阅的 goroutine 全部退出，此刻若要来断线通知，早已到了
	select {
	case msg := <-h.disc:
		t.Fatalf("Engine 自己关订阅不该触发 OnDisconnected: %q", msg)
	default:
	}
	if err := sub.Close(); err != nil {
		t.Fatalf("Stop 之后 Subscription.Close = %v", err)
	}
}

// 本地 DNS 经门面：宿主的 LocalDNS（core.DNSCall）真的被内核调用并把结果送回 DNS 应答。
type fakeLocalDNS struct{ lookups chan string }

func (f fakeLocalDNS) Raw() bool { return false }
func (f fakeLocalDNS) Exchange(c *core.DNSCall, _ []byte) error {
	c.ErrorCode(2)
	return nil
}
func (f fakeLocalDNS) Lookup(c *core.DNSCall, network, domain string) error {
	f.lookups <- network + " " + domain
	c.Success("192.0.2.77\n")
	return nil
}

func TestLocalDNSThroughFacade(t *testing.T) {
	port := freeTCPPort(t)
	cfg := fmt.Sprintf(`{
  "log": {"level": "error"},
  "dns": {"servers": [{"type": "local", "tag": "dns-local"}], "final": "dns-local"},
  "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": %d}],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"auto_detect_interface": true, "final": "direct", "default_domain_resolver": "dns-local",
    "rules": [{"action": "sniff"}, {"protocol": "dns", "action": "hijack-dns"}]}
}`, port)
	host := newTestHost()
	host.localDNS = fakeLocalDNS{lookups: make(chan string, 8)}
	e := newCoreEngine(t, host)
	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	resp, err := gate.QueryDNSViaMixed(t, port, "host.example.net", mdns.TypeA)
	if err != nil {
		t.Fatalf("DNS 查询: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("应答 = %v", resp)
	}
	if a, ok := resp.Answer[0].(*mdns.A); !ok || a.A.String() != "192.0.2.77" {
		t.Fatalf("应答不是宿主给的地址: %v", resp.Answer[0])
	}
	select {
	case got := <-host.localDNS.(fakeLocalDNS).lookups:
		if !strings.HasSuffix(strings.TrimSuffix(got, "."), "host.example.net") {
			t.Errorf("Lookup 参数 = %q", got)
		}
	default:
		t.Error("宿主的 Lookup 没有被调用")
	}
}

// 启动失败的错误分类前缀经门面原样出现：配置建不出服务 → create-service:。
func TestStartErrorPrefixThroughFacade(t *testing.T) {
	e := newCoreEngine(t, newTestHost())
	err := e.Start(`{"outbounds":[{"type":"no-such-type","tag":"x"}]}`)
	if err == nil || !strings.HasPrefix(err.Error(), "create-service:") {
		t.Fatalf("err = %v", err)
	}
	if errors.Is(err, nil) {
		t.Fatal("unreachable")
	}
}

// WARP 两种模式（与无 WARP）经门面真起：BuildConfig → 适配副本 → NewEngine + Start，select 里没有 warp。
func TestWarpFlowRealStart(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.json")
	if err := core.Parse(profile, writeFile(t, dir, "sub.json", customDirectSub), false); err != nil {
		t.Fatal(err)
	}
	for _, m := range flowModes(t) {
		t.Run(m.name, func(t *testing.T) {
			content, err := core.BuildConfig(profile, m.opts)
			if err != nil {
				t.Fatal(err)
			}
			adapted := checkBuilt(t, content, m.opts)
			e := newCoreEngine(t, newTestHost())
			if err := e.Start(string(adapted)); err != nil {
				t.Fatalf("Start: %v", err)
			}
			gch := make(groupsCh, 16)
			sub, err := e.SubscribeGroups(gch)
			if err != nil {
				t.Fatal(err)
			}
			defer sub.Close()
			frame := recvString(t, gch, "分组首帧")
			if strings.Contains(frame, `"tag":"warp"`) || strings.Contains(frame, `"warp"`) {
				t.Errorf("分组里不该出现 warp: %s", frame)
			}
			if err := e.Stop(); err != nil {
				t.Fatal(err)
			}
		})
	}
}
