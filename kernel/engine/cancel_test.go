package engine

import (
	"errors"
	"io"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"
)

// cancelConfig 与 testConfig 一样，只多一个 auto_detect_interface，让内核真的去启动平台的接口监视。
func cancelConfig(t *testing.T, port int) string {
	t.Helper()
	return replaceOnce(t, testConfig(port, ""), `"route": {"final": "select"}`, `"route": {"final": "select", "auto_detect_interface": true}`)
}

func recv(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(30 * time.Second):
		t.Fatalf("timeout waiting for %s", what)
	}
}

func recvErr(t *testing.T, ch <-chan error, what string) error {
	t.Helper()
	select {
	case err := <-ch:
		return err
	case <-time.After(30 * time.Second):
		t.Fatalf("timeout waiting for %s", what)
		return nil
	}
}

func TestStartCancelledWhileInterfaceMonitorBlocks(t *testing.T) {
	host := newFakeHost()
	entered, release := make(chan struct{}, 1), make(chan struct{})
	host.setMonitorBlock(entered, release)
	e, _ := newTestEngine(t, host)
	port := freePort(t)
	cfg := cancelConfig(t, port)

	startErr := make(chan error, 1)
	go func() { startErr <- e.Start(cfg) }()
	recv(t, entered, "interface monitor start")

	// 另一个 goroutine 里 Stop：Start 必须以「取消」结束，而不是超时
	stopErr := make(chan error, 1)
	go func() { stopErr <- e.Stop() }()

	err := recvErr(t, startErr, "Start to return")
	if !errors.Is(err, ErrCanceled) {
		t.Fatalf("Start error = %v, want ErrCanceled", err)
	}
	var se *StartError
	if errors.As(err, &se) {
		t.Fatalf("cancellation must not be reported as a classified start error: %v", err)
	}
	if err := recvErr(t, stopErr, "Stop to return"); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	// 宿主那次阻塞的调用此刻才返回：适配器必须替它撤销（调宿主的 StopInterfaceMonitor）
	if host.monitorStops.Load() != 0 {
		t.Fatalf("monitor stop called before the blocked start returned: %d", host.monitorStops.Load())
	}
	close(release)
	recv(t, host.monitorStopped, "late StopInterfaceMonitor")
	if got := host.monitorStops.Load(); got != 1 {
		t.Fatalf("StopInterfaceMonitor calls = %d, want 1", got)
	}

	// 订阅 goroutine 都退出了（这条路径上没有订阅，但也不能留下我们自己的 goroutine）
	waitUntil(t, "engine goroutines to drain", func() bool {
		return goroutineCount("kernel/engine.callCancelable") == 0
	})

	// 命令服务器还在（Stop 不关它）：同一个 Engine 能干净地再 Start 并真的转发流量
	host.setMonitorBlock(nil, nil)
	host.defaultReported = make(chan struct{}, 4)
	tg := newTarget(t)
	if err := e.Start(cfg); err != nil {
		t.Fatalf("Start after cancel: %v", err)
	}
	recv(t, host.defaultReported, "default interface report")
	if code, _ := getVia(t, proxyClient(t, port), tg.URL+"/hello"); code != 200 {
		t.Fatalf("GET after restart = %d", code)
	}
	if err := e.Stop(); err != nil {
		t.Fatal(err)
	}
	// 这一轮正常启动的监视也被正常关闭：start 一次、stop 一次（累计 2 / 2）
	if host.monitorStarts.Load() != 2 || host.monitorStops.Load() != 2 {
		t.Fatalf("monitor start/stop = %d/%d, want 2/2", host.monitorStarts.Load(), host.monitorStops.Load())
	}
}

func tunConfig(t *testing.T, port int) string {
	t.Helper()
	return strings.Replace(cancelConfig(t, port), `"inbounds": [`, `"inbounds": [{"type": "tun", "tag": "tun-in", "address": ["172.19.0.1/28"], "auto_route": true, "mtu": 9000, "stack": "system"}, `, 1)
}

func TestStartCancelledWhileOpenTunBlocks(t *testing.T) {
	host := newFakeHost()
	host.tunSpecs = make(chan string, 4)
	host.tunOwned = make(chan int, 4)
	host.tunPeers = make(chan *os.File, 4)
	entered, release := make(chan struct{}, 1), make(chan struct{})
	host.setTunBlock(entered, release)
	e, _ := newTestEngine(t, host)
	cfg := tunConfig(t, freePort(t))

	startErr := make(chan error, 1)
	go func() { startErr <- e.Start(cfg) }()
	recv(t, entered, "OpenTun")

	// libbox 真实传给宿主的 TunSpec（经 tunSpecJSON 读 libbox.TunOptions）
	spec := <-host.tunSpecs
	t.Logf("TunSpec from libbox: %s", spec)
	for _, want := range []string{`"mtu":9000`, `"auto_route":true`, `"inet4_address":["172.19.0.1/28"]`, `"include_package":[]`, `"http_proxy":{"enabled":false`} {
		if !strings.Contains(spec, want) {
			t.Fatalf("TunSpec %s lacks %s", spec, want)
		}
	}

	stopErr := make(chan error, 1)
	go func() { stopErr <- e.Stop() }()
	if err := recvErr(t, startErr, "Start to return"); !errors.Is(err, ErrCanceled) {
		t.Fatalf("Start error = %v, want ErrCanceled", err)
	}
	if err := recvErr(t, stopErr, "Stop to return"); err != nil {
		t.Fatalf("Stop: %v", err)
	}

	// 宿主的 OpenTun 之后才返回：Go 一侧没有、也不会对这个 fd 做 dup，
	// 所以宿主关掉自己那一端后，对端立刻读到 EOF；没有任何残留拷贝。
	close(release)
	fd := <-host.tunOwned
	peer := <-host.tunPeers
	defer peer.Close()
	if err := syscall.Close(fd); err != nil {
		t.Fatalf("host close tun fd: %v", err)
	}
	buf := make([]byte, 1)
	if _, err := peer.Read(buf); !errors.Is(err, io.EOF) {
		t.Fatalf("peer read = %v, want EOF (a leaked copy of the tun fd is still open)", err)
	}
}
