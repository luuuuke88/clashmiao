package core_test

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

// 不带 urltest 的最小配置：并发取消 / 清理逻辑在 -race 下也跑。
func minimalConfig(port int) string {
	return fmt.Sprintf(`{
  "log": {"level": "error"},
  "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": %d}],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"auto_detect_interface": true, "final": "direct"}
}`, port)
}

func recvErr(t *testing.T, ch <-chan error, what string) error {
	t.Helper()
	select {
	case err := <-ch:
		return err
	case <-time.After(30 * time.Second): // 失败兜底，不是等待手段
		t.Fatalf("等待%s超时", what)
		return nil
	}
}

// 门面层的并发 Stop：宿主的接口监视启动阻塞时，另一个线程 Stop，Start 以「取消」结束；
// 宿主那次调用之后才返回，适配器替它撤销（StopInterfaceMonitor）；同一个 Engine 能干净地再 Start。
func TestStopInterruptsStartThroughFacade(t *testing.T) {
	host := newTestHost()
	entered, release := make(chan struct{}, 1), make(chan struct{})
	host.monitorEntered, host.monitorRelease = entered, release
	e := newCoreEngine(t, host)
	cfg := minimalConfig(freeTCPPort(t))

	startErr := make(chan error, 1)
	go func() { startErr <- e.Start(cfg) }()
	select {
	case <-entered:
	case <-time.After(30 * time.Second):
		t.Fatal("宿主的 StartInterfaceMonitor 没有被调用")
	}
	stopErr := make(chan error, 1)
	go func() { stopErr <- e.Stop() }()

	err := recvErr(t, startErr, "Start 返回")
	if err == nil || !strings.HasPrefix(err.Error(), "canceled:") {
		t.Fatalf("Start err = %v，期望 canceled:", err)
	}
	if err := recvErr(t, stopErr, "Stop 返回"); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	close(release)
	select {
	case <-host.monitorStopped:
	case <-time.After(30 * time.Second):
		t.Fatal("迟到的接口监视没有被撤销")
	}
	if got := host.monitorStops.Load(); got != 1 {
		t.Fatalf("StopInterfaceMonitor 次数 = %d，期望 1", got)
	}

	host.monitorEntered, host.monitorRelease = nil, nil
	if err := e.Start(cfg); err != nil {
		t.Fatalf("取消之后再次 Start: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("Close（第二次）应返回 nil: %v", err)
	}
}
