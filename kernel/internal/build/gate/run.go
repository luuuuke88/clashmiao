package gate

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/sagernet/sing-box/experimental/libbox"

	"github.com/luuuuke88/clashmiao/kernel/engine"
)

// WorkDir 是 engine.Setup 用的工作目录（cache.db 与命令服务器的 socket 在这里）。
var WorkDir string

// Setup 初始化 libbox（进程内只能做一次），供包的 TestMain 调用；返回清理函数。
// 目录放在系统临时目录下的短名字目录里：命令服务器的 unix socket 路径有长度上限。
func Setup() (func(), error) {
	base, err := os.MkdirTemp("", "cg")
	if err != nil {
		return nil, err
	}
	WorkDir = base + "/work"
	if err := engine.Setup(engine.SetupOptions{BasePath: base, WorkingPath: WorkDir, TempPath: base + "/tmp", LogMaxLines: 300}); err != nil {
		_ = os.RemoveAll(base)
		return nil, err
	}
	return func() { _ = os.RemoveAll(base) }, nil
}

// CheckConfig 是 libbox.CheckConfig 的薄封装。注意它会放行「detour 指向空 direct」「selector 默认值非成员」
// 这类只在启动时才被拒绝的配置，所以闸门另有真 Start。
func CheckConfig(raw []byte) error { return libbox.CheckConfig(string(raw)) }

// NewEngine 建一个 Engine 并在测试结束时 Close。每次从干净的 cache.db 开始，免得上一个测试的选择漏进来。
func NewEngine(t testing.TB) (*engine.Engine, *FakeHost) {
	t.Helper()
	_ = os.Remove(WorkDir + "/cache.db")
	host := NewFakeHost()
	e, err := engine.New(host, Handler{})
	if err != nil {
		t.Fatalf("engine.New: %v", err)
	}
	t.Cleanup(func() { _ = e.Close() })
	return e, host
}

// Groups 是分组流一帧的解析结果。
type Groups []Group

// Group 对应线格式里的一个分组。
type Group struct {
	Tag      string `json:"tag"`
	Type     string `json:"type"`
	Selected string `json:"selected"`
	Items    []struct {
		Tag   string `json:"tag"`
		Type  string `json:"type"`
		Delay int    `json:"url-test-delay"`
	} `json:"items"`
}

// Find 按 tag 找分组。
func (g Groups) Find(tag string) *Group {
	for i := range g {
		if g[i].Tag == tag {
			return &g[i]
		}
	}
	return nil
}

// ItemTags 是分组成员的 tag。
func (g *Group) ItemTags() []string {
	var out []string
	for _, it := range g.Items {
		out = append(out, it.Tag)
	}
	return out
}

type groupsChan chan string

func (c groupsChan) OnGroups(j string) { c <- j }

// FirstGroups 订阅分组流并返回首帧。
func FirstGroups(t testing.TB, e *engine.Engine) Groups {
	t.Helper()
	ch := make(groupsChan, 16)
	sub, err := e.SubscribeGroups(ch)
	if err != nil {
		t.Fatalf("SubscribeGroups: %v", err)
	}
	defer sub.Close()
	select {
	case raw := <-ch:
		var g Groups
		if err := json.Unmarshal([]byte(raw), &g); err != nil {
			t.Fatalf("分组首帧不是预期的 JSON: %v\n%s", err, raw)
		}
		return g
	case <-time.After(30 * time.Second):
		t.Fatal("等待分组首帧超时")
		return nil
	}
}

// ProxyClient 返回经 127.0.0.1:port（mixed-in）发请求的 HTTP 客户端。
func ProxyClient(port int) *http.Client {
	u, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	return &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(u), DisableKeepAlives: true},
		Timeout:   30 * time.Second,
	}
}

// Get 取 URL 并返回状态码与正文。
func Get(t testing.TB, c *http.Client, target string) (int, string) {
	t.Helper()
	resp, err := c.Get(target)
	if err != nil {
		t.Fatalf("GET %s: %v", target, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

// WaitGroups 订阅分组流，等到某一帧满足 pred 并返回它；30 s 内等不到就让测试失败（兜底，不是等待手段）。
func WaitGroups(t testing.TB, e *engine.Engine, what string, pred func(Groups) bool) Groups {
	t.Helper()
	ch := make(groupsChan, 256)
	sub, err := e.SubscribeGroups(ch)
	if err != nil {
		t.Fatalf("SubscribeGroups: %v", err)
	}
	defer sub.Close()
	deadline := time.After(30 * time.Second)
	for {
		select {
		case raw := <-ch:
			var g Groups
			if err := json.Unmarshal([]byte(raw), &g); err != nil {
				t.Fatalf("分组帧不是预期的 JSON: %v\n%s", err, raw)
			}
			if pred(g) {
				return g
			}
		case <-deadline:
			t.Fatalf("等待分组流出现「%s」超时", what)
			return nil
		}
	}
}

// ItemDelay 返回分组成员的测速延迟（毫秒，0 表示还没有结果）。
func (g *Group) ItemDelay(tag string) int {
	for _, it := range g.Items {
		if it.Tag == tag {
			return it.Delay
		}
	}
	return -1
}

// GroupWatcher 持续订阅分组流并保留最新一帧：Wait 先看最新状态，再等后续的帧。
// 在触发动作之前创建它，就不会漏掉动作引起的帧。
type GroupWatcher struct {
	t      testing.TB
	ch     groupsChan
	sub    interface{ Close() error }
	latest Groups
}

// WatchGroups 开始订阅；测试结束自动取消。
func WatchGroups(t testing.TB, e *engine.Engine) *GroupWatcher {
	t.Helper()
	w := &GroupWatcher{t: t, ch: make(groupsChan, 1024)}
	sub, err := e.SubscribeGroups(w.ch)
	if err != nil {
		t.Fatalf("SubscribeGroups: %v", err)
	}
	w.sub = sub
	t.Cleanup(func() { _ = sub.Close() })
	return w
}

// Wait 等到最新状态或之后的某一帧满足 pred；30 s 内等不到就让测试失败（兜底，不是等待手段）。
func (w *GroupWatcher) Wait(what string, pred func(Groups) bool) Groups {
	w.t.Helper()
	if w.latest != nil && pred(w.latest) {
		return w.latest
	}
	deadline := time.After(30 * time.Second)
	for {
		select {
		case raw := <-w.ch:
			var g Groups
			if err := json.Unmarshal([]byte(raw), &g); err != nil {
				w.t.Fatalf("分组帧不是预期的 JSON: %v\n%s", err, raw)
			}
			w.latest = g
			if pred(g) {
				return g
			}
		case <-deadline:
			w.t.Fatalf("等待分组流出现「%s」超时；最新状态 %+v", what, w.latest)
			return nil
		}
	}
}

func jsonUnmarshal(raw []byte, v any) error { return json.Unmarshal(raw, v) }
