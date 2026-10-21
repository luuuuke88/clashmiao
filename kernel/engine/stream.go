package engine

import (
	"encoding/json"
	"errors"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// ---- 线格式（Go 一侧产出，Kotlin / Dart 的测试读同一份夹具） ----

type groupWire struct {
	Tag      string     `json:"tag"`
	Type     string     `json:"type"`
	Selected string     `json:"selected"`
	Items    []itemWire `json:"items"`
}

type itemWire struct {
	Tag          string `json:"tag"`
	Type         string `json:"type"`
	URLTestDelay int32  `json:"url-test-delay"`
}

// statsWire 的键名与顺序是契约（Kotlin 解析成数字 Map 再发给 Dart，Dart 只认 Map）。
type statsWire struct {
	ConnectionsIn  int32 `json:"connections-in"`
	ConnectionsOut int32 `json:"connections-out"`
	Uplink         int64 `json:"uplink"`
	Downlink       int64 `json:"downlink"`
	UplinkTotal    int64 `json:"uplink-total"`
	DownlinkTotal  int64 `json:"downlink-total"`
}

func groupsJSON(it libbox.OutboundGroupIterator) string {
	groups := []groupWire{}
	for it != nil && it.HasNext() {
		g := it.Next()
		w := groupWire{Tag: g.Tag, Type: g.Type, Selected: g.Selected, Items: []itemWire{}}
		items := g.GetItems()
		for items.HasNext() {
			item := items.Next()
			w.Items = append(w.Items, itemWire{Tag: item.Tag, Type: item.Type, URLTestDelay: item.URLTestDelay})
		}
		groups = append(groups, w)
	}
	raw, _ := json.Marshal(groups)
	return string(raw)
}

// ---- 订阅 ----

type GroupsHandler interface{ OnGroups(json string) }
type StatsHandler interface{ OnStats(json string) }
type LogHandler interface{ OnLog(line string) }

// DisconnectListener 是处理器可选实现的接口：订阅断线（服务停止、命令服务器关闭等）时收到一次通知。
// 重连策略留在调用方（Kotlin 的 CoreStream 跟随内核实例重连），所以这里只上抛，不自己重连。
type DisconnectListener interface{ OnDisconnected(message string) }

// Subscription 是一条命令流订阅。Close 幂等；关闭后不会再有回调。
type Subscription struct {
	e      *Engine
	client *libbox.CommandClient

	closed   atomic.Bool
	done     chan struct{} // 流 goroutine 全部结束（每条流结束时都会调一次 Disconnected）；Connect 失败时也会关闭
	doneOnce sync.Once
	pending  atomic.Int32
	// connectDone 在 Connect 返回（成败都算）时关闭：Close 要等它，才知道有没有流要断开。
	// 注册进 Engine.subs 与 Connect 之间有一个窗口，Stop 可以在窗口里调 Close；没有这个同步，
	// Close 先 Disconnect、Connect 随后才建起连接，流就泄漏了（Close 还白等 30 s）。
	connectDone chan struct{}
	connectErr  error
	once        sync.Once
	closeErr    error
	// closeStep 只给测试注入失败用。
	closeStep func() error
}

var errSubscriptionDrain = errors.New("subscription goroutines did not exit in time")

// finishDone 关闭 done（幂等：正常结束与 Connect 失败的收尾都可能走到）。
func (s *Subscription) finishDone() { s.doneOnce.Do(func() { close(s.done) }) }

// Close 断开并等流 goroutine 退出（事件同步，30 s 兜底）。Connect 还在进行时先等它返回，再决定断开什么。
func (s *Subscription) Close() error {
	s.once.Do(func() {
		s.closed.Store(true)
		var errs []error
		if s.connectDone != nil {
			select {
			case <-s.connectDone:
			case <-time.After(30 * time.Second):
				errs = append(errs, errSubscriptionDrain)
			}
		}
		if s.connectErr != nil {
			// 没有连上：没有流 goroutine，不会再有 Disconnected。
			s.finishDone()
		} else {
			step := func() error { return s.client.Disconnect() }
			if s.closeStep != nil {
				step = s.closeStep
			}
			if err := step(); err != nil {
				errs = append(errs, err)
			}
		}
		select {
		case <-s.done:
		case <-time.After(30 * time.Second):
			errs = append(errs, errSubscriptionDrain)
		}
		s.e.removeSub(s)
		s.closeErr = errors.Join(errs...)
	})
	return s.closeErr
}

// clientHandler 实现 libbox.CommandClientHandler，只转发我们关心的三类事件。
type clientHandler struct {
	sub *Subscription

	onGroups func(string)
	onStats  func(*libbox.StatusMessage)
	onLog    func(string)
	h        any // 用户处理器，用来识别 DisconnectListener

	lastTotals struct {
		mu       sync.Mutex
		at       time.Time
		up, down int64
	}
}

var _ libbox.CommandClientHandler = (*clientHandler)(nil)

func (c *clientHandler) Connected() {}

func (c *clientHandler) Disconnected(message string) {
	s := c.sub
	if s.pending.Add(-1) == 0 {
		s.finishDone()
	}
	if s.closed.Load() {
		return
	}
	if l, ok := c.h.(DisconnectListener); ok {
		l.OnDisconnected(message)
	}
}

func (c *clientHandler) SetDefaultLogLevel(int32) {}
func (c *clientHandler) ClearLogs()               {}
func (c *clientHandler) WriteLogs(list libbox.LogIterator) {
	if c.onLog == nil || c.sub.closed.Load() {
		return
	}
	for list.HasNext() {
		c.onLog(list.Next().Message)
	}
}

func (c *clientHandler) WriteStatus(m *libbox.StatusMessage) {
	if c.onStats == nil || c.sub.closed.Load() || m == nil {
		return
	}
	c.onStats(m)
}

func (c *clientHandler) WriteGroups(it libbox.OutboundGroupIterator) {
	if c.onGroups == nil || c.sub.closed.Load() {
		return
	}
	c.onGroups(groupsJSON(it))
}

func (c *clientHandler) WriteOutbounds(libbox.OutboundGroupItemIterator)   {}
func (c *clientHandler) InitializeClashMode(libbox.StringIterator, string) {}
func (c *clientHandler) UpdateClashMode(string)                            {}
func (c *clientHandler) WriteConnectionEvents(*libbox.ConnectionEvents)    {}

func (e *Engine) subscribe(command int32, intervalNanos int64, h *clientHandler) (*Subscription, error) {
	e.mu.Lock()
	if e.srv == nil {
		e.mu.Unlock()
		return nil, os.ErrClosed
	}
	e.mu.Unlock()

	sub := &Subscription{e: e, done: make(chan struct{}), connectDone: make(chan struct{})}
	sub.pending.Store(1)
	h.sub = sub
	opts := &libbox.CommandClientOptions{StatusInterval: intervalNanos}
	opts.AddCommand(command)
	sub.client = libbox.NewCommandClient(h, opts)

	e.mu.Lock()
	e.subs[sub] = struct{}{}
	e.mu.Unlock()

	e.mu.Lock()
	beforeConnect, connect := e.hooks.beforeConnect, e.hooks.connect
	e.mu.Unlock()
	if beforeConnect != nil {
		beforeConnect(sub)
	}
	var err error
	if connect != nil {
		err = connect(sub)
	} else {
		err = sub.client.Connect()
	}
	sub.connectErr = err
	close(sub.connectDone)
	if err != nil {
		// 连不上：没有流 goroutine（Disconnected 不会被调到），收尾要自己把 done 关上。
		sub.closed.Store(true)
		sub.finishDone()
		_ = sub.client.Disconnect()
		e.removeSub(sub)
		return nil, err
	}
	if sub.closed.Load() {
		// Connect 期间 Stop / Close 已经把它标成关闭：断开与等待由 Close 完成，调用方拿不到这条流。
		_ = sub.Close()
		return nil, os.ErrClosed
	}
	return sub, nil
}

func (e *Engine) removeSub(s *Subscription) {
	e.mu.Lock()
	delete(e.subs, s)
	if e.logSub == s {
		e.logSub = nil
	}
	e.mu.Unlock()
}

func (e *Engine) closeSubscriptions() error {
	e.mu.Lock()
	subs := make([]*Subscription, 0, len(e.subs))
	for s := range e.subs {
		subs = append(subs, s)
	}
	e.mu.Unlock()
	var errs []error
	for _, s := range subs {
		if err := s.Close(); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// SubscribeGroups 订阅分组流：连上后立刻推一次当前值，之后每次分组 / 延迟变化再推。
func (e *Engine) SubscribeGroups(h GroupsHandler) (*Subscription, error) {
	return e.subscribe(libbox.CommandGroup, 0, &clientHandler{
		onGroups: h.OnGroups,
		h:        h,
	})
}

// SubscribeStats 订阅统计流。速率（uplink / downlink）是每秒字节数，按两帧累计值之差与实际间隔算出，
// 与旧内核「当前速率」的语义一致；libbox 自己给的是「一个间隔内的增量」，间隔不是 1 s 时不能直接用。
func (e *Engine) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) {
	if intervalMillis <= 0 {
		intervalMillis = 1000
	}
	ch := &clientHandler{h: h}
	ch.onStats = func(m *libbox.StatusMessage) {
		now := time.Now()
		var up, down int64
		ch.lastTotals.mu.Lock()
		if !ch.lastTotals.at.IsZero() {
			if secs := now.Sub(ch.lastTotals.at).Seconds(); secs > 0 {
				up = int64(float64(m.UplinkTotal-ch.lastTotals.up) / secs)
				down = int64(float64(m.DownlinkTotal-ch.lastTotals.down) / secs)
			}
			if up < 0 {
				up = 0
			}
			if down < 0 {
				down = 0
			}
		}
		ch.lastTotals.at, ch.lastTotals.up, ch.lastTotals.down = now, m.UplinkTotal, m.DownlinkTotal
		ch.lastTotals.mu.Unlock()
		raw, _ := json.Marshal(statsWire{
			ConnectionsIn:  m.ConnectionsIn,
			ConnectionsOut: m.ConnectionsOut,
			Uplink:         up,
			Downlink:       down,
			UplinkTotal:    m.UplinkTotal,
			DownlinkTotal:  m.DownlinkTotal,
		})
		h.OnStats(string(raw))
	}
	return e.subscribe(libbox.CommandStatus, intervalMillis*int64(time.Millisecond), ch)
}

// SubscribeLogs 订阅内核日志：先回放环形缓冲里的历史行，再推新行。
func (e *Engine) SubscribeLogs(h LogHandler) (*Subscription, error) {
	return e.subscribe(libbox.CommandLog, 0, &clientHandler{onLog: h.OnLog, h: h})
}

type logToHost struct{ host Platform }

func (l logToHost) OnLog(line string) { l.host.WriteLog(line) }

// ensureLogForwarder 在第一次启动成功后挂一条内部日志订阅，把每行转给 Platform.WriteLog。
// 订阅跨重载一直活着（命令服务器的日志环形缓冲不随实例重置），Stop / Close 时随所有订阅一起关闭。
func (e *Engine) ensureLogForwarder() {
	e.mu.Lock()
	has := e.logSub != nil
	e.mu.Unlock()
	if has {
		return
	}
	sub, err := e.SubscribeLogs(logToHost{e.host})
	if err != nil {
		return
	}
	e.mu.Lock()
	if e.logSub == nil {
		e.logSub = sub
		e.mu.Unlock()
		return
	}
	e.mu.Unlock()
	_ = sub.Close()
}

// ---- 一次性命令 ----

// SelectOutbound 在选择组 group 里选中 tag。
func (e *Engine) SelectOutbound(group, tag string) error {
	c := libbox.NewStandaloneCommandClient()
	defer c.Disconnect()
	return c.SelectOutbound(group, tag)
}

// URLTest 对 tag（组或单个出站）发起一次测速；结果经分组流推送。
func (e *Engine) URLTest(tag string) error {
	c := libbox.NewStandaloneCommandClient()
	defer c.Disconnect()
	return c.URLTest(tag)
}
