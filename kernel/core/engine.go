package core

import (
	"errors"

	"github.com/luuuuke88/clashmiao/kernel/engine"
)

// ---- 由 Kotlin 实现的接口（回调方向：Go → Java） ----

// Platform 由宿主（Android 的 Kotlin 层）实现。
type Platform interface {
	// OpenTun 按 TunSpec JSON（spec §4.3）建立 TUN，返回宿主持有的原始 fd。
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
	// LocalDNS 可以返回 null：不替换内核的本地 DNS 传输。
	LocalDNS() LocalDNS
	// WriteLog 接收内核日志的每一行。
	WriteLog(line string)
}

// LocalDNS 由宿主实现：本地 DNS 走系统解析器（与 Kotlin 的 SystemDnsBridge 一一对应）。
type LocalDNS interface {
	Raw() bool
	Exchange(call *DNSCall, message []byte) error
	Lookup(call *DNSCall, network, domain string) error
}

// Func 是一次性回调。
type Func interface {
	Invoke() error
}

// DNSCall 是一次 DNS 请求的结果通道。
type DNSCall struct{ inner *engine.DNSCall }

func (c *DNSCall) OnCancel(callback Func)   { c.inner.OnCancel(callback) }
func (c *DNSCall) Success(result string)    { c.inner.Success(result) }
func (c *DNSCall) RawSuccess(result []byte) { c.inner.RawSuccess(result) }
func (c *DNSCall) ErrorCode(code int32)     { c.inner.ErrorCode(code) }
func (c *DNSCall) ErrnoCode(code int32)     { c.inner.ErrnoCode(code) }

// InterfaceListener 由 Engine 交给宿主，宿主在默认网络变化时回调。
type InterfaceListener interface {
	Update(name string, index int32, expensive, constrained bool)
}

// EngineHandler 是命令服务器回调给宿主的事件。
type EngineHandler interface {
	OnReloadRequested()
	OnStopRequested()
	SystemProxyAvailable() bool
	SystemProxyEnabled() bool
	SetSystemProxyEnabled(enabled bool)
}

// 三类流的处理器。OnDisconnected 在订阅断线（服务停止、命令服务器关闭等）时调一次：
// 重连策略留在 Kotlin（CoreStream 跟随内核实例重连），Go 这边不自己重连。
// （gomobile 的 Java 代理只实现接口里声明的方法，所以「可选的断线通知」必须直接写进接口。）

// GroupsHandler 接收分组 JSON（线格式见 spec §2.3）。
type GroupsHandler interface {
	OnGroups(json string)
	OnDisconnected(message string)
}

// StatsHandler 接收统计 JSON。
type StatsHandler interface {
	OnStats(json string)
	OnDisconnected(message string)
}

// LogHandler 接收内核日志的每一行。
type LogHandler interface {
	OnLog(line string)
	OnDisconnected(message string)
}

// ---- Go 实现、Kotlin 调用 ----

// Engine 是一个内核实例：命令服务器 + 服务生命周期 + 命令客户端。
// 并发约定：Start 阻塞；Stop / Close 可以在另一个线程里打断尚未完成的 Start。
type Engine struct{ inner *engine.Engine }

// NewEngine 创建 Engine 并立刻起命令服务器；失败的错误以 command-server: 开头。
func NewEngine(host Platform, h EngineHandler) (*Engine, error) {
	if host == nil || h == nil {
		return nil, errors.New("command-server: host and handler must not be null")
	}
	e, err := engine.New(platformShim{host}, h)
	if err != nil {
		return nil, err
	}
	return &Engine{inner: e}, nil
}

// Start 阻塞直到服务启动完成；失败的错误以 create-service: / start-service: 开头，
// 被 Stop / Close 打断时为 canceled:。
func (e *Engine) Start(configJSON string) error { return e.inner.Start(configJSON) }

// Stop 停止服务；会打断尚未完成的 Start。
func (e *Engine) Stop() error { return e.inner.Stop() }

// Close 与 Stop 一样分步清理，任一步出错继续后面的步骤，返回合并后的错误；重复调用返回 nil。
func (e *Engine) Close() error { return e.inner.Close() }

func (e *Engine) Pause()        { e.inner.Pause() }
func (e *Engine) Wake()         { e.inner.Wake() }
func (e *Engine) ResetNetwork() { e.inner.ResetNetwork() }

func (e *Engine) SelectOutbound(group, tag string) error { return e.inner.SelectOutbound(group, tag) }
func (e *Engine) URLTest(tag string) error               { return e.inner.URLTest(tag) }

func (e *Engine) SubscribeGroups(h GroupsHandler) (*Subscription, error) {
	return wrapSub(e.inner.SubscribeGroups(h))
}

func (e *Engine) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) {
	return wrapSub(e.inner.SubscribeStats(h, intervalMillis))
}

func (e *Engine) SubscribeLogs(h LogHandler) (*Subscription, error) {
	return wrapSub(e.inner.SubscribeLogs(h))
}

// Subscription 是一条命令流订阅。Close 幂等；关闭后不会再有回调。
type Subscription struct{ inner *engine.Subscription }

func (s *Subscription) Close() error { return s.inner.Close() }

func wrapSub(s *engine.Subscription, err error) (*Subscription, error) {
	if err != nil {
		return nil, err
	}
	return &Subscription{inner: s}, nil
}

// ---- 适配：core.Platform → engine.Platform ----

// platformShim 唯一的差别在 LocalDNS：它的方法签名里有 *DNSCall，两个包各有一个同名类型。
type platformShim struct{ Platform }

func (s platformShim) StartInterfaceMonitor(l engine.InterfaceListener) error {
	return s.Platform.StartInterfaceMonitor(l)
}

func (s platformShim) LocalDNS() engine.LocalDNS {
	l := s.Platform.LocalDNS()
	if l == nil {
		return nil
	}
	return localDNSShim{l}
}

type localDNSShim struct{ l LocalDNS }

func (s localDNSShim) Raw() bool { return s.l.Raw() }
func (s localDNSShim) Exchange(call *engine.DNSCall, message []byte) error {
	return s.l.Exchange(&DNSCall{inner: call}, message)
}
func (s localDNSShim) Lookup(call *engine.DNSCall, network, domain string) error {
	return s.l.Lookup(&DNSCall{inner: call}, network, domain)
}

// 编译期断言：门面的处理器接口满足 engine 对「可选断线通知」的识别（见 engine.DisconnectListener）。
var (
	_ engine.Platform           = platformShim{}
	_ engine.Handler            = EngineHandler(nil)
	_ engine.DisconnectListener = GroupsHandler(nil)
	_ engine.DisconnectListener = StatsHandler(nil)
	_ engine.DisconnectListener = LogHandler(nil)
)
