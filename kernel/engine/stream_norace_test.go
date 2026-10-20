//go:build !race

// 这些测试要真起带 urltest 组的配置，在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），
// 所以放在 !race 文件里，由 gotest.sh 的第二遍运行。

package engine

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

type chanGroups chan string

func (c chanGroups) OnGroups(j string) { c <- j }

type chanStats chan string

func (c chanStats) OnStats(j string) { c <- j }

func next(t *testing.T, ch <-chan string, what string) string {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(30 * time.Second):
		t.Fatalf("timeout waiting for %s", what)
		return ""
	}
}

// nextMatching 一直读帧直到 pred 为真（读不到时超时失败）。
func nextMatching(t *testing.T, ch <-chan string, what string, pred func(string) bool) string {
	t.Helper()
	deadline := time.After(30 * time.Second)
	for {
		select {
		case v := <-ch:
			if pred(v) {
				return v
			}
		case <-deadline:
			t.Fatalf("timeout waiting for %s", what)
			return ""
		}
	}
}

var (
	delayRe   = regexp.MustCompile(`"url-test-delay":\d+`)
	urltestRe = regexp.MustCompile(`("type":"urltest","selected":")[^"]*`)
)

// normalizeGroups 抹掉随时序变化的部分：测速延迟、urltest 组此刻选中了谁。
func normalizeGroups(raw string) string {
	raw = delayRe.ReplaceAllString(raw, `"url-test-delay":0`)
	return urltestRe.ReplaceAllString(raw, `${1}a`)
}

func wirePath(name string) string { return filepath.Join("..", "testdata", "wire", name) }

func startWithURLTest(t *testing.T) (*Engine, *target, int) {
	t.Helper()
	tg := newTarget(t)
	e, _ := newTestEngine(t, newFakeHost())
	port := freePort(t)
	if err := e.Start(testConfig(port, tg.URL+"/generate_204")); err != nil {
		t.Fatalf("Start: %v", err)
	}
	return e, tg, port
}

func TestGroupsFirstFrameMatchesWireFixture(t *testing.T) {
	e, _, _ := startWithURLTest(t)
	ch := make(chanGroups, 64)
	sub, err := e.SubscribeGroups(ch)
	if err != nil {
		t.Fatalf("SubscribeGroups: %v", err)
	}
	defer sub.Close()

	got := normalizeGroups(next(t, ch, "first groups frame"))
	if os.Getenv("UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(wirePath("groups-first.json"), []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(wirePath("groups-first.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	if got != string(want) {
		t.Fatalf("first frame differs from testdata/wire/groups-first.json\n got: %s\nwant: %s", got, want)
	}
}

func TestSelectOutboundShowsInNextFrame(t *testing.T) {
	e, _, _ := startWithURLTest(t)
	ch := make(chanGroups, 64)
	sub, err := e.SubscribeGroups(ch)
	if err != nil {
		t.Fatal(err)
	}
	defer sub.Close()
	_ = next(t, ch, "first frame")

	if err := e.SelectOutbound("select", "b"); err != nil {
		t.Fatalf("SelectOutbound: %v", err)
	}
	// 选择组变化是否触发一次推送取决于上游；这里主动再触发一次测速，保证有新帧，再检查 selected。
	if err := e.URLTest("auto"); err != nil {
		t.Fatalf("URLTest: %v", err)
	}
	frame := nextMatching(t, ch, "frame with select=b", func(f string) bool {
		return strings.Contains(f, `"tag":"select","type":"selector","selected":"b"`)
	})
	if frame == "" {
		t.Fatal("no frame")
	}
	if err := e.SelectOutbound("select", "no-such"); err == nil {
		t.Fatal("selecting a missing member must fail")
	}
	if err := e.SelectOutbound("auto", "a"); err == nil {
		t.Fatal("selecting on a urltest group must fail")
	}
}

func TestURLTestFillsDelays(t *testing.T) {
	e, tg, _ := startWithURLTest(t)
	ch := make(chanGroups, 64)
	sub, err := e.SubscribeGroups(ch)
	if err != nil {
		t.Fatal(err)
	}
	defer sub.Close()
	if err := e.URLTest("auto"); err != nil {
		t.Fatalf("URLTest: %v", err)
	}
	// 本地目标收到了 /generate_204
	for p := range tg.hits {
		if p == "/generate_204" {
			break
		}
	}
	frame := nextMatching(t, ch, "frame with positive delay", func(f string) bool {
		var gs []groupWire
		if json.Unmarshal([]byte(f), &gs) != nil {
			return false
		}
		for _, g := range gs {
			if g.Tag != "auto" || len(g.Items) == 0 {
				continue
			}
			for _, it := range g.Items {
				if it.URLTestDelay <= 0 {
					return false
				}
			}
			return true
		}
		return false
	})
	if frame == "" {
		t.Fatal("no frame")
	}
}

func TestStatsFrameKeysAndTypes(t *testing.T) {
	e, tg, port := startWithURLTest(t)
	ch := make(chanStats, 64)
	sub, err := e.SubscribeStats(ch, 100)
	if err != nil {
		t.Fatal(err)
	}
	defer sub.Close()

	first := next(t, ch, "first stats frame")
	var m map[string]any
	if err := json.Unmarshal([]byte(first), &m); err != nil {
		t.Fatalf("stats frame is not JSON: %v", err)
	}
	wantKeys := []string{"connections-in", "connections-out", "uplink", "downlink", "uplink-total", "downlink-total"}
	if len(m) != len(wantKeys) {
		t.Fatalf("keys = %v, want exactly %v", m, wantKeys)
	}
	for _, k := range wantKeys {
		v, ok := m[k].(float64)
		if !ok {
			t.Fatalf("%s is not a JSON number: %#v", k, m[k])
		}
		if v != float64(int64(v)) {
			t.Fatalf("%s is not an integer: %v", k, v)
		}
	}
	// 键顺序与夹具一致（线格式是契约）
	fixture, err := os.ReadFile(wirePath("stats-frame.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	if keyOrder(first) != keyOrder(string(fixture)) {
		t.Fatalf("key order %q != fixture %q", keyOrder(first), keyOrder(string(fixture)))
	}

	// 有流量之后：累计值非零，速率在某一帧非零
	client := proxyClient(t, port)
	sawRate := false
	for i := 0; i < 50 && !sawRate; i++ {
		getVia(t, client, tg.URL+"/hello")
		frame := next(t, ch, "stats frame under traffic")
		var s statsWire
		if err := json.Unmarshal([]byte(frame), &s); err != nil {
			t.Fatal(err)
		}
		if s.DownlinkTotal > 0 && s.Downlink > 0 {
			sawRate = true
		}
	}
	if !sawRate {
		t.Fatal("never saw a non-zero downlink rate while generating traffic")
	}
}

var keyRe = regexp.MustCompile(`"([a-z-]+)":`)

func keyOrder(j string) string {
	var keys []string
	for _, m := range keyRe.FindAllStringSubmatch(j, -1) {
		keys = append(keys, m[1])
	}
	return strings.Join(keys, ",")
}
