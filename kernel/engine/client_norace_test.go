//go:build !race

package engine

import (
	"errors"
	"os"
	"strings"
	"testing"
)

type chanLogs chan string

func (c chanLogs) OnLog(line string) { c <- line }

// Client 不持有服务，只连 Engine 起的命令服务器（iOS 上两者在不同进程，Setup 同一个 BasePath）：
// 三类流、选择、测速都要与 Engine 自己的订阅给出同样的结果。
func TestClientSubscribesToEngineServer(t *testing.T) {
	e, tg, port := startWithURLTest(t)
	c := NewClient()
	defer c.Close()

	groups := make(chanGroups, 64)
	gsub, err := c.SubscribeGroups(groups)
	if err != nil {
		t.Fatalf("SubscribeGroups: %v", err)
	}
	defer gsub.Close()
	first := normalizeGroups(next(t, groups, "first groups frame"))
	want, err := os.ReadFile(wirePath("groups-first.json"))
	if err != nil {
		t.Fatal(err)
	}
	if first != string(want) {
		t.Fatalf("client groups frame differs from fixture\n got: %s\nwant: %s", first, want)
	}

	if err := c.SelectOutbound("select", "b"); err != nil {
		t.Fatalf("SelectOutbound: %v", err)
	}
	if err := c.URLTest("auto"); err != nil {
		t.Fatalf("URLTest: %v", err)
	}
	nextMatching(t, groups, "frame with select=b", func(f string) bool {
		return strings.Contains(f, `"tag":"select","type":"selector","selected":"b"`)
	})

	stats := make(chanStats, 64)
	ssub, err := c.SubscribeStats(stats, 100)
	if err != nil {
		t.Fatalf("SubscribeStats: %v", err)
	}
	defer ssub.Close()
	if got := keyOrder(next(t, stats, "first stats frame")); !strings.HasPrefix(got, "connections-in,") {
		t.Fatalf("stats key order %q", got)
	}

	logs := make(chanLogs, 256)
	lsub, err := c.SubscribeLogs(logs)
	if err != nil {
		t.Fatalf("SubscribeLogs: %v", err)
	}
	defer lsub.Close()
	e.WriteLog("client-test-marker")
	getVia(t, proxyClient(t, port), tg.URL+"/hello")
	nextMatching(t, logs, "marker line", func(l string) bool { return strings.Contains(l, "client-test-marker") })
}

// Engine 停掉服务后，Client 的订阅收到断线通知；Close 之后不能再订阅。
func TestClientCloseAndAfterClose(t *testing.T) {
	startWithURLTest(t)
	c := NewClient()
	groups := make(chanGroups, 64)
	if _, err := c.SubscribeGroups(groups); err != nil {
		t.Fatal(err)
	}
	next(t, groups, "first frame")
	if err := c.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := c.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}
	if _, err := c.SubscribeGroups(make(chanGroups, 1)); !errors.Is(err, os.ErrClosed) {
		t.Fatalf("subscribe after Close = %v, want ErrClosed", err)
	}
}
