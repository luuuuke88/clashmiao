package engine

import (
	"errors"
	"os"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
)

// raceHost 记录接口监视的宿主调用顺序，并让第一次启动与第一次停止停在测试控制的屏障上。
type raceHost struct {
	*fakeHost
	calls atomic.Int32 // StartInterfaceMonitor 的调用序号

	aEntered, aRelease       chan struct{} // 第一次启动（A）
	stopEntered, stopRelease chan struct{} // 第一次停止
	startedB                 chan struct{} // 第二次启动（B）进入宿主

	mu           sync.Mutex
	events       []string
	inStop       bool
	startInStop  bool
	stopsStarted int
}

func (h *raceHost) log(e string) { h.mu.Lock(); h.events = append(h.events, e); h.mu.Unlock() }

func (h *raceHost) StartInterfaceMonitor(l InterfaceListener) error {
	n := h.calls.Add(1)
	h.mu.Lock()
	if h.inStop {
		h.startInStop = true
	}
	h.mu.Unlock()
	if n == 1 {
		h.log("start-A")
		h.aEntered <- struct{}{}
		<-h.aRelease
		return nil
	}
	h.log("start-B")
	h.startedB <- struct{}{}
	return nil
}

func (h *raceHost) StopInterfaceMonitor() error {
	h.mu.Lock()
	h.stopsStarted++
	first := h.stopsStarted == 1
	h.inStop = true
	h.mu.Unlock()
	h.log("stop-begin")
	if first {
		h.stopEntered <- struct{}{}
		<-h.stopRelease
	}
	h.mu.Lock()
	h.inStop = false
	h.mu.Unlock()
	h.log("stop-end")
	return nil
}

type nopListener struct{}

func (nopListener) UpdateDefaultInterface(string, int32, bool, bool) {}
func (nopListener) UpdateNetworkPath(string)                         {}

// A 的启动被取消后迟到返回，它的收尾通过了代次检查、停在宿主的停止里；这时 B 启动——
// B 必须等 A 的宿主停止做完才开始，不能在 A 的停止进行中（或之后）被它停掉。
// 屏障：A 停在宿主停止内；B 要么排到 hostSem 的队里（onHostBarrier），要么直接进了宿主的启动（修复前的行为，判为失败）。
func TestLateMonitorStopCannotStopNewerStartAfterCheck(t *testing.T) {
	host := &raceHost{
		fakeHost:    newFakeHost(),
		aEntered:    make(chan struct{}, 1),
		aRelease:    make(chan struct{}),
		stopEntered: make(chan struct{}, 1),
		stopRelease: make(chan struct{}),
		startedB:    make(chan struct{}, 1),
	}
	pa := newPlatformAdapter(host)
	barrier := make(chan struct{}, 1)
	pa.onHostBarrier = func() { barrier <- struct{}{} }

	cancelA := make(chan struct{})
	pa.setCancel(cancelA)
	aErr := make(chan error, 1)
	go func() { aErr <- pa.StartDefaultInterfaceMonitor(nopListener{}) }()
	recv(t, host.aEntered, "A: host start")
	close(cancelA)
	if err := recvErr(t, aErr, "A: Start to return"); !errors.Is(err, ErrCanceled) {
		t.Fatalf("A: %v, want ErrCanceled", err)
	}

	// A 的宿主调用现在返回：迟到收尾通过代次检查，停在宿主的停止里。
	close(host.aRelease)
	recv(t, host.stopEntered, "A: late host stop")

	pa.setCancel(make(chan struct{}))
	bErr := make(chan error, 1)
	go func() { bErr <- pa.StartDefaultInterfaceMonitor(nopListener{}) }()
	select {
	case <-barrier: // 正确：B 在 A 的停止之后排队
	case <-host.startedB: // 错误：B 在 A 的宿主停止进行中就进了宿主启动
	}
	close(host.stopRelease)
	if err := recvErr(t, bErr, "B: Start to return"); err != nil {
		t.Fatalf("B: %v", err)
	}

	host.mu.Lock()
	defer host.mu.Unlock()
	if host.startInStop {
		t.Fatalf("B 的宿主启动发生在 A 的宿主停止进行中；事件序列 %v", host.events)
	}
	want := []string{"start-A", "stop-begin", "stop-end", "start-B"}
	if !reflect.DeepEqual(host.events, want) {
		t.Fatalf("宿主调用顺序 = %v，期望 %v（B 在 A 之后启动，且没有再被停）", host.events, want)
	}
	if st := pa.monitor; st != monitorStarted {
		t.Fatalf("B 的监视状态 = %v，期望已启动", st)
	}
}

// A 的迟到收尾停在宿主停止里（占着串行化槽位），B 随后启动并在槽位上排队。
// 这时 Stop：排队中的 B 必须被取消打断而先于 A 的停止返回，Stop 自己也要返回——
// 它们都不能等一个没人能催的宿主停止。
func TestQueuedMonitorStartIsCancelledAndStopReturns(t *testing.T) {
	host := &raceHost{
		fakeHost:    newFakeHost(),
		aEntered:    make(chan struct{}, 1),
		aRelease:    make(chan struct{}),
		stopEntered: make(chan struct{}, 1),
		stopRelease: make(chan struct{}),
		startedB:    make(chan struct{}, 1),
	}
	_ = os.Remove(testWorkDir + "/cache.db")
	e, err := New(host, &fakeHandler{})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	released := false
	release := func() {
		if !released {
			released = true
			close(host.stopRelease)
		}
	}
	t.Cleanup(func() { release(); _ = e.Close() })
	barrier := make(chan struct{}, 1)
	e.pa.onHostBarrier = func() { barrier <- struct{}{} }
	cfg := cancelConfig(t, freePort(t))

	// A：宿主启动被拦住，Stop 把它取消，之后宿主启动返回，迟到收尾停在宿主停止里。
	aErr := make(chan error, 1)
	go func() { aErr <- e.Start(cfg) }()
	recv(t, host.aEntered, "A: host start")
	if err := e.Stop(); err != nil {
		t.Fatalf("Stop(A): %v", err)
	}
	if err := recvErr(t, aErr, "A: Start to return"); !errors.Is(err, ErrCanceled) {
		t.Fatalf("A: %v, want ErrCanceled", err)
	}
	close(host.aRelease)
	recv(t, host.stopEntered, "A: late host stop")

	// B：在 A 的宿主停止之后排队。
	bErr := make(chan error, 1)
	go func() { bErr <- e.Start(cfg) }()
	recv(t, barrier, "B: queued behind A's host stop")

	// Stop：A 的宿主停止仍然卡着，B 与 Stop 都必须返回。
	stopErr := make(chan error, 1)
	go func() { stopErr <- e.Stop() }()
	if err := recvErr(t, bErr, "B: Start to return while A's host stop is blocked"); !errors.Is(err, ErrCanceled) {
		t.Fatalf("B: %v, want ErrCanceled", err)
	}
	if err := recvErr(t, stopErr, "Stop to return while A's host stop is blocked"); err != nil {
		t.Fatalf("Stop(B): %v", err)
	}
	select {
	case <-host.startedB:
		t.Fatal("被取消的 B 不该进入宿主的启动")
	default:
	}
	release()
}
