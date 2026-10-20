package engine

import (
	"errors"
	"testing"
)

func TestStartProxyReloadStopClose(t *testing.T) {
	tg := newTarget(t)
	host := newFakeHost()
	e, _ := newTestEngine(t, host)
	port := freePort(t)
	cfg := testConfig(port, "")

	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	code, body := getVia(t, proxyClient(t, port), tg.URL+"/hello")
	if code != 200 || body != "hello" {
		t.Fatalf("proxy GET = %d %q", code, body)
	}
	// 请求确实到了本地目标
	if got := <-tg.hits; got != "/hello" {
		t.Fatalf("target saw %q", got)
	}

	// 重载：同一个 Engine 再 Start 一次仍可用
	if err := e.Start(cfg); err != nil {
		t.Fatalf("reload Start: %v", err)
	}
	if code, _ := getVia(t, proxyClient(t, port), tg.URL+"/hello"); code != 200 {
		t.Fatalf("after reload GET = %d", code)
	}

	// Stop 幂等，且之后可以再次 Start
	for i := 0; i < 2; i++ {
		if err := e.Stop(); err != nil {
			t.Fatalf("Stop #%d: %v", i, err)
		}
	}
	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start after Stop: %v", err)
	}
	if code, _ := getVia(t, proxyClient(t, port), tg.URL+"/hello"); code != 200 {
		t.Fatalf("after restart GET = %d", code)
	}

	// Close 幂等：第二次返回 nil；Close 之后仍可再次 Start（命令服务器重建）
	if err := e.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("second Close should be nil: %v", err)
	}
	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start after Close: %v", err)
	}
	if code, _ := getVia(t, proxyClient(t, port), tg.URL+"/hello"); code != 200 {
		t.Fatalf("after Close+Start GET = %d", code)
	}
}

func TestLogsForwardedToHost(t *testing.T) {
	host := newFakeHost()
	e, _ := newTestEngine(t, host)
	port := freePort(t)
	// debug 级别：启动期间就会有日志
	cfg := testConfig(port, "")
	cfg = replaceOnce(t, cfg, `"level": "warn"`, `"level": "debug"`)
	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start: %v", err)
	}
	line := <-host.logs
	if line == "" {
		t.Fatal("empty log line")
	}
}

func TestSystemProxyAndHandlerCallbacks(t *testing.T) {
	// 命令服务器回调到 Handler：这里直接走 commandHandler，证明字段映射不丢。
	host := newFakeHost()
	e, h := newTestEngine(t, host)
	ch := &commandHandler{e: e}
	st, err := ch.GetSystemProxyStatus()
	if err != nil || !st.Available || st.Enabled {
		t.Fatalf("status = %+v, %v", st, err)
	}
	_ = ch.SetSystemProxyEnabled(true)
	if st, _ = ch.GetSystemProxyStatus(); !st.Enabled {
		t.Fatal("enabled flag not propagated")
	}
	_ = ch.ServiceReload()
	_ = ch.ServiceStop()
	if h.reloads.Load() != 1 || h.stops.Load() != 1 {
		t.Fatalf("reloads=%d stops=%d", h.reloads.Load(), h.stops.Load())
	}
}

func TestErrCanceledIsDistinct(t *testing.T) {
	if !errors.Is(ErrCanceled, ErrCanceled) {
		t.Fatal("unreachable")
	}
	var se *StartError
	if errors.As(ErrCanceled, &se) {
		t.Fatal("ErrCanceled must not look like a classified start error")
	}
}
