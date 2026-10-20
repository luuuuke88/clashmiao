package engine

import (
	"encoding/json"
	"errors"
	"os"
	"sync"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// Platform 由宿主（Android 的 Kotlin 层）实现。复杂载荷一律用 JSON 字符串传递，
// 这样同一份接口可以原样经 gomobile 暴露（见 core 门面）。
type Platform interface {
	// OpenTun 按 TunSpec JSON（spec §4.3）建立 TUN，返回宿主持有的原始 fd。
	// Go 一侧会 dup 一份并在服务关闭时关闭自己的那份；宿主自己的那份由宿主在 teardown 时关闭。
	OpenTun(specJSON string) (int32, error)
	// Protect 把出口 socket 标记成「不走 VPN」（VpnService.protect）。
	Protect(fd int32) error
	UseProcFS() bool
	// FindOwner 返回 JSON {"uid":N,"packages":[...]}。
	FindOwner(protocol int32, srcAddr string, srcPort int32, dstAddr string, dstPort int32) (string, error)
	StartInterfaceMonitor(l InterfaceListener) error
	StopInterfaceMonitor() error
	// InterfacesJSON 返回 [{name,index,mtu,flags,type,addresses[],dns[],gateway[],metered}]。
	InterfacesJSON() (string, error)
	ClearDNSCache()
	// LocalDNS 可以返回 nil：不替换内核的本地 DNS 传输。
	LocalDNS() LocalDNS
	// WriteLog 接收内核日志的每一行。
	WriteLog(line string)
}

// InterfaceListener 由 Engine 交给宿主，宿主在默认网络变化时回调。
type InterfaceListener interface {
	Update(name string, index int32, expensive, constrained bool)
}

// Handler 是命令服务器回调给宿主的事件。
type Handler interface {
	OnReloadRequested()
	OnStopRequested()
	SystemProxyAvailable() bool
	SystemProxyEnabled() bool
	SetSystemProxyEnabled(enabled bool)
}

// ErrCanceled 表示 Start 被 Stop / Close 打断。
var ErrCanceled = errors.New("canceled: service start interrupted")

// platformAdapter 把 Platform 适配成 libbox.PlatformInterface。
// 凡是可能长时间阻塞的宿主调用（建 TUN、启动接口监视、读接口列表），都包一层
// 「等宿主返回，或等 Engine 被取消」：取消时立刻带着 ErrCanceled 返回，让 libbox 的启动流程尽快收场；
// 宿主那次调用仍在后台跑完，跑完后由适配器负责撤销（接口监视）。
type platformAdapter struct {
	host Platform

	mu      sync.Mutex
	cancel  <-chan struct{} // 当前这一代的取消信号
	monitor monitorState
	// stopErr 暂存宿主 StopInterfaceMonitor 的错误：libbox 在关服务时调用我们，并会吞掉返回值，
	// 所以留给 Engine 的「stop-interface-monitor」清理步骤取走并上报。
	stopErr error
}

type monitorState int

const (
	monitorIdle monitorState = iota
	monitorStarting
	monitorStarted
)

var _ libbox.PlatformInterface = (*platformAdapter)(nil)

func newPlatformAdapter(host Platform) *platformAdapter {
	return &platformAdapter{host: host}
}

// setCancel 在每次 Start 开始时换上新一代的取消信号。
func (p *platformAdapter) setCancel(ch <-chan struct{}) {
	p.mu.Lock()
	p.cancel = ch
	p.mu.Unlock()
}

func (p *platformAdapter) cancelCh() <-chan struct{} {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cancel
}

// callCancelable 在 goroutine 里跑 fn，等它返回或等取消。
// 取消先到时返回 ErrCanceled，fn 的结果交给 late（可为 nil）在它真正返回后处理。
func callCancelable[T any](p *platformAdapter, fn func() (T, error), late func(T, error)) (T, error) {
	type result struct {
		v   T
		err error
	}
	done := make(chan result, 1)
	cancel := p.cancelCh()
	go func() {
		v, err := fn()
		done <- result{v, err}
	}()
	select {
	case r := <-done:
		return r.v, r.err
	case <-cancel:
		if late != nil {
			go func() {
				r := <-done
				late(r.v, r.err)
			}()
		}
		var zero T
		return zero, ErrCanceled
	}
}

// ---- 自动检测接口 / TUN ----

func (p *platformAdapter) UsePlatformAutoDetectInterfaceControl() bool { return true }

func (p *platformAdapter) AutoDetectInterfaceControl(fd int32) error { return p.host.Protect(fd) }

func (p *platformAdapter) OpenTun(options libbox.TunOptions) (int32, error) {
	spec, err := tunSpecJSON(options)
	if err != nil {
		return -1, err
	}
	fd, err := callCancelable(p, func() (int32, error) { return p.host.OpenTun(spec) }, nil)
	if err != nil {
		return -1, err
	}
	return fd, nil
}

func (p *platformAdapter) UseProcFS() bool { return p.host.UseProcFS() }

// ---- 连接归属 ----

type ownerJSON struct {
	UID      int32    `json:"uid"`
	Packages []string `json:"packages"`
}

func (p *platformAdapter) FindConnectionOwner(ipProtocol int32, sourceAddress string, sourcePort int32, destinationAddress string, destinationPort int32) (*libbox.ConnectionOwner, error) {
	raw, err := p.host.FindOwner(ipProtocol, sourceAddress, sourcePort, destinationAddress, destinationPort)
	if err != nil {
		return nil, err
	}
	var o ownerJSON
	if err := json.Unmarshal([]byte(raw), &o); err != nil {
		return nil, errors.New("find owner: bad json: " + err.Error())
	}
	owner := &libbox.ConnectionOwner{UserId: o.UID}
	owner.SetAndroidPackageNames(newStringIterator(o.Packages))
	return owner, nil
}

// ---- 默认接口监视 ----

type listenerBridge struct {
	l libbox.InterfaceUpdateListener
}

func (b listenerBridge) Update(name string, index int32, expensive, constrained bool) {
	b.l.UpdateDefaultInterface(name, index, expensive, constrained)
}

func (p *platformAdapter) StartDefaultInterfaceMonitor(listener libbox.InterfaceUpdateListener) error {
	p.mu.Lock()
	p.monitor = monitorStarting
	p.mu.Unlock()
	_, err := callCancelable(p, func() (struct{}, error) {
		return struct{}{}, p.host.StartInterfaceMonitor(listenerBridge{listener})
	}, func(_ struct{}, startErr error) {
		// 宿主那次调用在取消之后才返回：没人再会来关它，这里撤销。
		p.finishLateMonitor(startErr)
	})
	if err != nil {
		if !errors.Is(err, ErrCanceled) {
			p.mu.Lock()
			p.monitor = monitorIdle
			p.mu.Unlock()
		}
		return err
	}
	p.mu.Lock()
	p.monitor = monitorStarted
	p.mu.Unlock()
	return nil
}

func (p *platformAdapter) finishLateMonitor(startErr error) {
	p.mu.Lock()
	state := p.monitor
	p.monitor = monitorIdle
	p.mu.Unlock()
	if startErr != nil || state == monitorIdle {
		return
	}
	_ = p.host.StopInterfaceMonitor()
}

func (p *platformAdapter) CloseDefaultInterfaceMonitor(listener libbox.InterfaceUpdateListener) error {
	return p.stopMonitor()
}

// stopMonitor 幂等：只有「已启动」才调宿主的停止；启动还没返回的由 finishLateMonitor 收尾。
func (p *platformAdapter) stopMonitor() error {
	p.mu.Lock()
	state := p.monitor
	if state == monitorStarted {
		p.monitor = monitorIdle
	}
	p.mu.Unlock()
	if state != monitorStarted {
		return nil
	}
	err := p.host.StopInterfaceMonitor()
	if err != nil {
		p.mu.Lock()
		p.stopErr = errors.Join(p.stopErr, err)
		p.mu.Unlock()
	}
	return err
}

// drainMonitor 是 Engine 清理步骤：确保监视已停，并取走此前（含 libbox 吞掉的）停止错误。
func (p *platformAdapter) drainMonitor() error {
	err := p.stopMonitor()
	p.mu.Lock()
	pending := p.stopErr
	p.stopErr = nil
	p.mu.Unlock()
	if pending != nil {
		return pending
	}
	return err
}

// ---- 接口列表 ----

type ifaceJSON struct {
	Name      string   `json:"name"`
	Index     int32    `json:"index"`
	MTU       int32    `json:"mtu"`
	Flags     int32    `json:"flags"`
	Type      int32    `json:"type"`
	Addresses []string `json:"addresses"`
	DNS       []string `json:"dns"`
	Gateway   []string `json:"gateway"`
	Metered   bool     `json:"metered"`
}

func (p *platformAdapter) GetInterfaces() (libbox.NetworkInterfaceIterator, error) {
	raw, err := callCancelable(p, func() (string, error) { return p.host.InterfacesJSON() }, nil)
	if err != nil {
		return nil, err
	}
	return parseInterfaces(raw)
}

func parseInterfaces(raw string) (libbox.NetworkInterfaceIterator, error) {
	var list []ifaceJSON
	if err := json.Unmarshal([]byte(raw), &list); err != nil {
		return nil, errors.New("interfaces: bad json: " + err.Error())
	}
	out := make([]*libbox.NetworkInterface, 0, len(list))
	for _, it := range list {
		out = append(out, &libbox.NetworkInterface{
			Index:     it.Index,
			MTU:       it.MTU,
			Name:      it.Name,
			Addresses: newStringIterator(it.Addresses),
			Flags:     it.Flags,
			Type:      it.Type,
			DNSServer: newStringIterator(it.DNS),
			Gateway:   newStringIterator(it.Gateway),
			Metered:   it.Metered,
		})
	}
	return &ifaceIterator{items: out}, nil
}

type ifaceIterator struct {
	items []*libbox.NetworkInterface
}

func (i *ifaceIterator) HasNext() bool { return len(i.items) > 0 }

func (i *ifaceIterator) Next() *libbox.NetworkInterface {
	if len(i.items) == 0 {
		return nil
	}
	v := i.items[0]
	i.items = i.items[1:]
	return v
}

// ---- 其余：固定答案 / 不使用 ----

func (p *platformAdapter) UnderNetworkExtension() bool { return false }
func (p *platformAdapter) IncludeAllNetworks() bool    { return false }
func (p *platformAdapter) ReadWIFIState() *libbox.WIFIState {
	return nil
}
func (p *platformAdapter) ClearDNSCache() { p.host.ClearDNSCache() }

func (p *platformAdapter) LocalDNSTransport() libbox.LocalDNSTransport {
	l := p.host.LocalDNS()
	if l == nil {
		return nil // 必须是真正的 nil 接口，libbox 靠它判断是否替换本地 DNS
	}
	return &localDNSAdapter{host: l}
}

func (p *platformAdapter) SendNotification(*libbox.Notification) error { return nil }
func (p *platformAdapter) CancelNotification(string, int32) error      { return nil }
func (p *platformAdapter) StartNeighborMonitor(libbox.NeighborUpdateListener) error {
	return os.ErrInvalid
}
func (p *platformAdapter) CloseNeighborMonitor(libbox.NeighborUpdateListener) error { return nil }
func (p *platformAdapter) RegisterMyInterface(string)                               {}
func (p *platformAdapter) UsePlatformShell() bool                                   { return false }
func (p *platformAdapter) CheckPlatformShell() error                                { return nil }
func (p *platformAdapter) OpenShellSession(*libbox.PlatformUser, string, libbox.StringIterator, string, int32, int32) (libbox.ShellSession, error) {
	return nil, os.ErrInvalid
}
func (p *platformAdapter) LookupUser(string) (*libbox.PlatformUser, error) { return nil, os.ErrInvalid }
func (p *platformAdapter) LookupSFTPServer() (string, error)               { return "", os.ErrInvalid }
func (p *platformAdapter) ReadSystemSSHHostKey() (string, error)           { return "", os.ErrInvalid }
func (p *platformAdapter) TailscaleHostname() string                       { return "" }
func (p *platformAdapter) UsePlatformBridge() bool                         { return false }
func (p *platformAdapter) CreateBridge(*libbox.BridgeOptions) (libbox.BridgeSession, error) {
	return nil, os.ErrInvalid
}

// ---- 小工具 ----

type stringIterator struct{ values []string }

func newStringIterator(values []string) *stringIterator { return &stringIterator{values: values} }

func (s *stringIterator) Len() int32    { return int32(len(s.values)) }
func (s *stringIterator) HasNext() bool { return len(s.values) > 0 }
func (s *stringIterator) Next() string {
	if len(s.values) == 0 {
		return ""
	}
	v := s.values[0]
	s.values = s.values[1:]
	return v
}

var _ libbox.StringIterator = (*stringIterator)(nil)
