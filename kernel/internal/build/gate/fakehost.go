package gate

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"syscall"

	"github.com/luuuuke88/clashmiao/kernel/engine"
)

// FakeHost 是 engine.Platform 的主机实现：没有 TUN（适配副本里本来就没有 tun-in），
// 只把回环接口报告为默认网络，让 auto_detect_interface 的直连拨号有地方绑。
type FakeHost struct {
	Logs chan string
}

// NewFakeHost 建一个宿主；日志写进带缓冲的 Logs（满了就丢，不阻塞内核）。
func NewFakeHost() *FakeHost { return &FakeHost{Logs: make(chan string, 4096)} }

func (h *FakeHost) OpenTun(string) (int32, error) {
	return -1, errors.New("gate: host has no TUN")
}
func (h *FakeHost) Protect(int32) error { return nil }
func (h *FakeHost) UseProcFS() bool     { return false }
func (h *FakeHost) FindOwner(int32, string, int32, string, int32) (string, error) {
	return `{"uid":0,"packages":[]}`, nil
}

func (h *FakeHost) StartInterfaceMonitor(l engine.InterfaceListener) error {
	go func() {
		if lo, err := loopback(); err == nil {
			l.Update(lo.Name, int32(lo.Index), false, false)
		}
	}()
	return nil
}
func (h *FakeHost) StopInterfaceMonitor() error { return nil }
func (h *FakeHost) ClearDNSCache()              {}
func (h *FakeHost) LocalDNS() engine.LocalDNS   { return nil }
func (h *FakeHost) WriteLog(line string) {
	select {
	case h.Logs <- line:
	default:
	}
}

func (h *FakeHost) InterfacesJSON() (string, error) {
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
	return nil, fmt.Errorf("gate: no loopback interface")
}

// Handler 是 engine.Handler 的空实现。
type Handler struct{}

func (Handler) OnReloadRequested()         {}
func (Handler) OnStopRequested()           {}
func (Handler) SystemProxyAvailable() bool { return false }
func (Handler) SystemProxyEnabled() bool   { return false }
func (Handler) SetSystemProxyEnabled(bool) {}
