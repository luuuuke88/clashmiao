package core_test

import (
	"encoding/json"
	"errors"
	"net"
	"os"
	"sync/atomic"
	"syscall"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/core"
)

// testHost 是 core.Platform 的测试实现：没有 TUN，只把回环接口报告为默认网络；阻塞点用 channel 控制。
type testHost struct {
	logs chan string

	// 非 nil 时，StartInterfaceMonitor 先向 monitorEntered 发信号，再等 monitorRelease。
	monitorEntered chan struct{}
	monitorRelease chan struct{}
	monitorStops   atomic.Int32
	monitorStopped chan struct{}

	localDNS core.LocalDNS
}

func newTestHost() *testHost {
	return &testHost{logs: make(chan string, 4096), monitorStopped: make(chan struct{}, 16)}
}

func (h *testHost) OpenTun(string) (int32, error) { return -1, errors.New("test host has no TUN") }
func (h *testHost) Protect(int32) error           { return nil }
func (h *testHost) UseProcFS() bool               { return false }
func (h *testHost) FindOwner(int32, string, int32, string, int32) (string, error) {
	return `{"uid":0,"packages":[]}`, nil
}

func (h *testHost) StartInterfaceMonitor(l core.InterfaceListener) error {
	if h.monitorEntered != nil {
		h.monitorEntered <- struct{}{}
		<-h.monitorRelease
		// 这一次启动已被取消：迟到的默认接口上报会和下一轮启动的初始化争同一个字段（官方 libbox 的已知形状），
		// 真实宿主在 stop 之后同样不该再上报，所以这里不报。
		return nil
	}
	go func() {
		if lo, err := loopback(); err == nil {
			l.Update(lo.Name, int32(lo.Index), false, false)
		}
	}()
	return nil
}

func (h *testHost) StopInterfaceMonitor() error {
	h.monitorStops.Add(1)
	select {
	case h.monitorStopped <- struct{}{}:
	default:
	}
	return nil
}

func (h *testHost) ClearDNSCache()          {}
func (h *testHost) LocalDNS() core.LocalDNS { return h.localDNS }
func (h *testHost) WriteLog(line string) {
	select {
	case h.logs <- line:
	default:
	}
}

func (h *testHost) InterfacesJSON() (string, error) {
	lo, err := loopback()
	if err != nil {
		return "", err
	}
	addrs := []string{}
	if a, err := lo.Addrs(); err == nil {
		for _, ad := range a {
			addrs = append(addrs, ad.String())
		}
	}
	raw, _ := json.Marshal([]map[string]any{{
		"name": lo.Name, "index": lo.Index, "mtu": lo.MTU,
		"flags": syscall.IFF_UP | syscall.IFF_LOOPBACK | syscall.IFF_RUNNING,
		"type":  3, "addresses": addrs, "dns": []string{}, "gateway": []string{}, "metered": false,
	}})
	return string(raw), nil
}

func loopback() (*net.Interface, error) {
	all, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for i := range all {
		if all[i].Flags&net.FlagLoopback != 0 {
			return &all[i], nil
		}
	}
	return nil, errors.New("no loopback interface")
}

// testHandler 是 core.EngineHandler 的测试实现。
type testHandler struct{}

func (testHandler) OnReloadRequested()         {}
func (testHandler) OnStopRequested()           {}
func (testHandler) SystemProxyAvailable() bool { return false }
func (testHandler) SystemProxyEnabled() bool   { return false }
func (testHandler) SetSystemProxyEnabled(bool) {}

func newCoreEngine(t *testing.T, host core.Platform) *core.Engine {
	t.Helper()
	_ = os.Remove(workDir + "/cache.db")
	e, err := core.NewEngine(host, testHandler{})
	if err != nil {
		t.Fatalf("NewEngine: %v", err)
	}
	t.Cleanup(func() { _ = e.Close() })
	return e
}

func freeTCPPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}
