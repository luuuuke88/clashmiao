package engine

import (
	"reflect"
	"testing"
)

type recordDisconnects struct{ msgs []string }

func (r *recordDisconnects) OnDisconnected(m string) { r.msgs = append(r.msgs, m) }

// 订阅断线要上抛给处理器（重连策略在调用方）；订阅被我们自己关掉之后不再回调；
// 全部流都结束时 done 才关闭（Close 靠它等 goroutine 退出）。
func TestDisconnectedIsForwardedUnlessClosed(t *testing.T) {
	sub := &Subscription{done: make(chan struct{})}
	sub.pending.Store(2)
	rec := &recordDisconnects{}
	h := &clientHandler{sub: sub, h: rec}

	h.Disconnected("first")
	select {
	case <-sub.done:
		t.Fatal("done closed while a stream is still running")
	default:
	}
	h.Disconnected("second")
	select {
	case <-sub.done:
	default:
		t.Fatal("done not closed after the last stream ended")
	}
	if !reflect.DeepEqual(rec.msgs, []string{"first", "second"}) {
		t.Fatalf("forwarded = %v", rec.msgs)
	}

	sub.closed.Store(true)
	h.Disconnected("after close")
	if len(rec.msgs) != 2 {
		t.Fatalf("callback after Close: %v", rec.msgs)
	}

	// 处理器没实现 DisconnectListener 时安静地忽略
	h2 := &clientHandler{sub: &Subscription{done: make(chan struct{})}, h: struct{}{}}
	h2.sub.pending.Store(1)
	h2.Disconnected("x")
}
