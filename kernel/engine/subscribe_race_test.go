//go:build !race

package engine

import (
	"errors"
	"os"
	"testing"
)

// 订阅「注册之后、Connect 之前」被 Stop 关闭：不能泄漏流，也不能让 Stop 白等 30 s。
// 暂停点与 Stop 的进展都靠事件同步：Stop 先把订阅标成关闭，再等 Connect 返回，之后才放行。
func TestSubscribeClosedBetweenRegisterAndConnect(t *testing.T) {
	e, _, _ := startWithURLTest(t)

	entered, release := make(chan struct{}, 1), make(chan struct{})
	e.mu.Lock()
	e.hooks.beforeConnect = func(*Subscription) {
		entered <- struct{}{}
		<-release
	}
	e.mu.Unlock()

	type result struct {
		sub *Subscription
		err error
	}
	got := make(chan result, 1)
	go func() {
		sub, err := e.SubscribeGroups(chanGroups(make(chan string, 64)))
		got <- result{sub, err}
	}()
	recv(t, entered, "subscribe to reach the pause point")

	e.mu.Lock()
	var registered *Subscription
	for s := range e.subs {
		if s != e.logSub {
			registered = s
		}
	}
	e.mu.Unlock()
	if registered == nil {
		t.Fatal("订阅此刻应已注册")
	}

	stopped := make(chan error, 1)
	go func() { stopped <- e.Close() }()
	waitUntil(t, "Close to mark the subscription closed", func() bool { return registered.closed.Load() })
	close(release) // 放行 Connect

	r := <-got
	if r.sub != nil || !errors.Is(r.err, os.ErrClosed) {
		t.Fatalf("subscribe = (%v, %v)，期望 (nil, ErrClosed)", r.sub, r.err)
	}
	if err := recvErr(t, stopped, "Close to return"); err != nil {
		t.Fatalf("Close: %v", err)
	}
	select {
	case <-registered.done:
	default:
		t.Fatal("流应已结束（done 已关闭），不能泄漏")
	}
	e.mu.Lock()
	n := len(e.subs)
	e.mu.Unlock()
	if n != 0 {
		t.Fatalf("e.subs 还剩 %d 条", n)
	}
}

// Connect 失败：没有流 goroutine，done 也必须关闭，订阅被摘除，Close 不再等。
func TestSubscribeConnectFailureClosesDone(t *testing.T) {
	e, _, _ := startWithURLTest(t)
	errConnect := errors.New("injected connect failure")
	var seen *Subscription
	e.mu.Lock()
	e.hooks.connect = func(s *Subscription) error { seen = s; return errConnect }
	e.mu.Unlock()

	sub, err := e.SubscribeStats(chanStats(make(chan string, 4)), 1000)
	if sub != nil || !errors.Is(err, errConnect) {
		t.Fatalf("subscribe = (%v, %v)", sub, err)
	}
	select {
	case <-seen.done:
	default:
		t.Fatal("Connect 失败后 done 必须关闭")
	}
	if err := seen.Close(); err != nil { // 立即返回、幂等
		t.Fatalf("Close after failed connect: %v", err)
	}
	e.mu.Lock()
	_, still := e.subs[seen]
	e.mu.Unlock()
	if still {
		t.Fatal("失败的订阅应已从 e.subs 摘除")
	}
}
