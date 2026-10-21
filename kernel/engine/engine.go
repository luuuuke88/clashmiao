// Package engine 是全仓唯一 import 官方 libbox 的包（U12 的 core 门面除外）：
// 把「命令服务器 + 服务启停 + 命令客户端」封装成一个可测试的 Engine，
// 平台回调（TUN、保护 socket、网络监听、本地 DNS）通过 Platform 接口交给宿主。
package engine

import (
	"errors"
	"os"
	"path/filepath"
	"sync"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// SetupOptions 对应 spec §4.2 的 SetupOptions。
type SetupOptions struct {
	BasePath      string // 命令服务器的 unix socket 所在目录（应用私有目录）
	WorkingPath   string // 工作目录：cache.db、崩溃报告
	TempPath      string
	Debug         bool
	LogMaxLines   int
	MemoryLimited bool
}

var (
	setupMu   sync.Mutex
	setupBase string
)

// Setup 必须在 New 之前调用一次（重复调用只是重新应用）。
func Setup(o SetupOptions) error {
	if o.LogMaxLines <= 0 {
		o.LogMaxLines = 300
	}
	setupMu.Lock()
	setupBase = o.BasePath
	setupMu.Unlock()
	err := libbox.Setup(&libbox.SetupOptions{
		BasePath:          o.BasePath,
		WorkingPath:       o.WorkingPath,
		TempPath:          o.TempPath,
		LogMaxLines:       o.LogMaxLines,
		Debug:             o.Debug,
		CrashReportSource: "clashmiao",
	})
	// libbox.Setup 会把软内存上限重置成「不限」，所以要放在它后面。
	applyMemoryLimit(o.MemoryLimited)
	return err
}

func socketPath() string {
	setupMu.Lock()
	defer setupMu.Unlock()
	return filepath.Join(setupBase, "command.sock")
}

// Engine 持有一个命令服务器与其上的服务生命周期。
// 并发约定：Start 阻塞；Stop / Close 可以在另一个 goroutine 里打断尚未完成的 Start。
type Engine struct {
	host Platform
	h    Handler
	pa   *platformAdapter

	mu      sync.Mutex
	srv     *libbox.CommandServer
	cancel  chan struct{} // 当前这一次 Start 的取消信号
	cancelD bool
	subs    map[*Subscription]struct{}
	logSub  *Subscription
	hooks   hooks
	// stepObserver 只给测试用：每个清理步骤执行完都会回调（含失败的）。
	stepObserver func(name string, err error)
}

// hooks 是清理步骤的可替换实现，只给测试注入失败用；生产路径不改它们。
type hooks struct {
	closeService func(*libbox.CommandServer) error
	closeServer  func(*libbox.CommandServer) error
	removeSocket func(path string) error
	// 订阅的「注册之后、Connect 之前」暂停点与 Connect 本身（测试用：卡住竞态窗口、注入连接失败）。
	beforeConnect func(*Subscription)
	connect       func(*Subscription) error
}

func defaultHooks() hooks {
	return hooks{
		closeService: func(s *libbox.CommandServer) error { return s.CloseService() },
		closeServer:  func(s *libbox.CommandServer) error { s.Close(); return nil },
		removeSocket: func(path string) error {
			err := os.Remove(path)
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			return err
		},
	}
}

// New 创建 Engine，并立刻起命令服务器（监听 unix socket）。失败带 PrefixCommandServer。
func New(host Platform, h Handler) (*Engine, error) {
	e := &Engine{
		host:   host,
		h:      h,
		pa:     newPlatformAdapter(host),
		subs:   map[*Subscription]struct{}{},
		hooks:  defaultHooks(),
		cancel: make(chan struct{}),
	}
	e.mu.Lock()
	err := e.ensureServerLocked()
	e.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return e, nil
}

// PrefixCommandServer 是命令服务器起不来时的前缀（Kotlin 映射 FailureCode.StartCommandServer）。
const PrefixCommandServer = "command-server:"

func (e *Engine) ensureServerLocked() error {
	if e.srv != nil {
		return nil
	}
	srv, err := libbox.NewCommandServer(&commandHandler{e: e}, e.pa)
	if err != nil {
		return &StartError{Prefix: PrefixCommandServer, Err: err}
	}
	if err := srv.Start(); err != nil {
		srv.Close()
		return &StartError{Prefix: PrefixCommandServer, Err: err}
	}
	e.srv = srv
	return nil
}

// Start 阻塞直到服务启动完成。已经在运行时等价于重载（libbox 内部先关旧实例）。
// 失败的错误以 PrefixCreateService / PrefixStartService 开头；被 Stop / Close 打断返回 ErrCanceled。
func (e *Engine) Start(configJSON string) error {
	e.mu.Lock()
	if err := e.ensureServerLocked(); err != nil {
		e.mu.Unlock()
		return err
	}
	cancel := make(chan struct{})
	e.cancel = cancel
	e.cancelD = false
	e.pa.setCancel(cancel)
	srv := e.srv
	e.mu.Unlock()

	err := srv.StartOrReloadService(configJSON, &libbox.OverrideOptions{})
	// libbox 在启动被打断时会返回 nil（并把实例收掉），所以取消要自己判断。
	select {
	case <-cancel:
		return ErrCanceled
	default:
	}
	if err != nil {
		return classifyStartError(err, configJSON)
	}
	e.ensureLogForwarder()
	return nil
}

// signalCancel 打断正在进行的 Start（幂等）。
func (e *Engine) signalCancel() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.cancelD {
		e.cancelD = true
		close(e.cancel)
	}
}

type step struct {
	name string
	fn   func() error
}

// runSteps 逐步执行：每一步出错都记下并继续，最后合并返回。
func (e *Engine) runSteps(steps []step) error {
	var errs []error
	for _, s := range steps {
		err := s.fn()
		if err != nil {
			errs = append(errs, &stepError{name: s.name, err: err})
		}
		if e.stepObserver != nil {
			e.stepObserver(s.name, err)
		}
	}
	return errors.Join(errs...)
}

type stepError struct {
	name string
	err  error
}

func (s *stepError) Error() string { return s.name + ": " + s.err.Error() }
func (s *stepError) Unwrap() error { return s.err }

func (e *Engine) stopSteps() []step {
	e.mu.Lock()
	srv := e.srv
	e.mu.Unlock()
	return []step{
		{"cancel-start", func() error { e.signalCancel(); return nil }},
		{"close-subscriptions", e.closeSubscriptions},
		{"close-service", func() error {
			if srv == nil {
				return nil
			}
			return e.hooks.closeService(srv)
		}},
		{"stop-interface-monitor", e.pa.drainMonitor},
	}
}

// Stop 关闭服务（会打断尚未完成的 Start）。清理分步执行，每一步出错都继续后面的步骤，
// 最后返回合并后的错误；命令服务器保持运行，之后可以再次 Start。
func (e *Engine) Stop() error {
	return e.runSteps(e.stopSteps())
}

// Close 在 Stop 的基础上关闭命令服务器并删除 socket 文件。重复调用返回 nil；
// 之后仍可再次 Start（会重建命令服务器）。
func (e *Engine) Close() error {
	e.mu.Lock()
	srv := e.srv
	e.mu.Unlock()
	if srv == nil {
		return nil
	}
	steps := append(e.stopSteps(),
		step{"close-command-server", func() error {
			e.mu.Lock()
			e.srv = nil
			e.mu.Unlock()
			return e.hooks.closeServer(srv)
		}},
		step{"remove-socket", func() error { return e.hooks.removeSocket(socketPath()) }},
	)
	return e.runSteps(steps)
}

// Pause / Wake / ResetNetwork：Doze 暂停与唤醒、网络变化后重置。
func (e *Engine) Pause() {
	if s := e.server(); s != nil {
		s.Pause()
	}
}

func (e *Engine) Wake() {
	if s := e.server(); s != nil {
		s.Wake()
	}
}

func (e *Engine) ResetNetwork() {
	if s := e.server(); s != nil {
		s.ResetNetwork()
	}
}

func (e *Engine) server() *libbox.CommandServer {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.srv
}

// commandHandler 是命令服务器回调给宿主的事件。
type commandHandler struct{ e *Engine }

func (c *commandHandler) ServiceStop() error {
	c.e.h.OnStopRequested()
	return nil
}

func (c *commandHandler) ServiceReload() error {
	c.e.h.OnReloadRequested()
	return nil
}

func (c *commandHandler) GetSystemProxyStatus() (*libbox.SystemProxyStatus, error) {
	return &libbox.SystemProxyStatus{
		Available: c.e.h.SystemProxyAvailable(),
		Enabled:   c.e.h.SystemProxyEnabled(),
	}, nil
}

func (c *commandHandler) SetSystemProxyEnabled(enabled bool) error {
	c.e.h.SetSystemProxyEnabled(enabled)
	return nil
}

func (c *commandHandler) TriggerNativeCrash() error       { return os.ErrInvalid }
func (c *commandHandler) WriteDebugMessage(string)        {}
func (c *commandHandler) ConnectSSHAgent() (int32, error) { return -1, os.ErrInvalid }

// Version 是内置的 sing-box 版本串（发布构建用 -X 覆盖 constant.Version）。
func Version() string { return libbox.Version() }

// CheckConfig 只构造、不启动地检查配置（libbox.CheckConfig 的薄封装）。
// 注意它会放行「detour 指向空 direct」这类只在启动时才被拒绝的配置。
func CheckConfig(content string) error { return libbox.CheckConfig(content) }

// GoVersion 是编译所用的 Go 版本与目标平台，用于诊断。
func GoVersion() string { return libbox.GoVersion() }
