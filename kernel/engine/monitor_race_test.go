package engine

import (
	"errors"
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
// 屏障：A 停在宿主停止内；B 要么排到 hostMu 的队里（onHostBarrier），要么直接进了宿主的启动（修复前的行为，判为失败）。
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
