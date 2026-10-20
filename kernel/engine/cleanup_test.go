package engine

import (
	"errors"
	"os"
	"reflect"
	"testing"
)

var errInjected = errors.New("injected failure")

type stepRecord struct {
	names []string
	errs  map[string]error
}

func (r *stepRecord) observe(name string, err error) {
	r.names = append(r.names, name)
	if r.errs == nil {
		r.errs = map[string]error{}
	}
	r.errs[name] = err
}

// realThenFail 把一个真实清理函数包成「做完真实工作，但返回注入的错误」。
func realThenFail[T any](real func(T) error, inject bool) func(T) error {
	return func(v T) error {
		err := real(v)
		if inject {
			return errors.Join(err, errInjected)
		}
		return err
	}
}

var (
	stopStepNames  = []string{"cancel-start", "close-subscriptions", "close-service", "stop-interface-monitor"}
	closeStepNames = []string{"cancel-start", "close-subscriptions", "close-service", "stop-interface-monitor", "close-command-server", "remove-socket"}
)

// 每个清理步骤依次失败：Stop / Close 仍把其余步骤全部执行，返回值里带着该步骤的错误，
// 之后 Engine 能再次 Start，且没有泄漏。
func TestCleanupStepsContinueAfterEachFailure(t *testing.T) {
	type tc struct {
		fail    string // 注入失败的步骤
		viaStop bool   // Stop 里也有这一步
	}
	cases := []tc{
		{"close-subscriptions", true},
		{"close-service", true},
		{"stop-interface-monitor", true},
		{"close-command-server", false},
		{"remove-socket", false},
	}
	for _, c := range cases {
		for _, closing := range []bool{false, true} {
			if !closing && !c.viaStop {
				continue
			}
			name := c.fail + "/Stop"
			if closing {
				name = c.fail + "/Close"
			}
			t.Run(name, func(t *testing.T) {
				host := newFakeHost()
				host.defaultReported = make(chan struct{}, 4)
				e, _ := newTestEngine(t, host)
				port := freePort(t)
				cfg := cancelConfig(t, port) // 带 auto_detect_interface：真的会启动接口监视
				if err := e.Start(cfg); err != nil {
					t.Fatalf("Start: %v", err)
				}
				recv(t, host.defaultReported, "default interface report")

				sub, err := e.SubscribeLogs(logToHost{host})
				if err != nil {
					t.Fatalf("SubscribeLogs: %v", err)
				}
				// 内部日志转发订阅也在，所以订阅至少 2 条
				if c.fail == "close-subscriptions" {
					// 做完真实的断开，再报告失败（模拟「关闭时出错但资源已释放」）
					sub.closeStep = func() error { return errors.Join(sub.client.Disconnect(), errInjected) }
				}
				if c.fail == "stop-interface-monitor" {
					host.monitorStopErr = errInjected
				}
				e.hooks.closeService = realThenFail(defaultHooks().closeService, c.fail == "close-service")
				e.hooks.closeServer = realThenFail(defaultHooks().closeServer, c.fail == "close-command-server")
				e.hooks.removeSocket = func(path string) error {
					err := defaultHooks().removeSocket(path)
					if c.fail == "remove-socket" {
						return errors.Join(err, errInjected)
					}
					return err
				}
				rec := &stepRecord{}
				e.stepObserver = rec.observe

				var got error
				want := stopStepNames
				if closing {
					got = e.Close()
					want = closeStepNames
				} else {
					got = e.Stop()
				}
				if !reflect.DeepEqual(rec.names, want) {
					t.Fatalf("steps executed = %v, want all of %v", rec.names, want)
				}
				if !errors.Is(got, errInjected) {
					t.Fatalf("returned error %v does not carry the injected failure", got)
				}
				if rec.errs[c.fail] == nil {
					t.Fatalf("step %s should have reported an error", c.fail)
				}
				for _, n := range want {
					if n != c.fail && rec.errs[n] != nil {
						t.Fatalf("unrelated step %s failed: %v", n, rec.errs[n])
					}
				}

				// 副作用都在：订阅 goroutine 退了、监视停了
				waitUntil(t, "subscription goroutines to exit", func() bool {
					return goroutineCount("libbox.(*CommandClient).handle") == 0
				})
				if got := host.monitorStops.Load(); got != 1 {
					t.Fatalf("StopInterfaceMonitor calls = %d, want 1", got)
				}
				if closing {
					if _, err := os.Stat(socketPath()); !errors.Is(err, os.ErrNotExist) {
						t.Fatalf("command.sock should be gone after Close, stat err = %v", err)
					}
					if err := e.Close(); err != nil {
						t.Fatalf("second Close should be nil, got %v", err)
					}
				}

				// 之后能再次启动并正常工作；恢复真实清理函数后收尾干净
				e.stepObserver = nil
				e.hooks = defaultHooks()
				host.monitorStopErr = nil
				tg := newTarget(t)
				if err := e.Start(cfg); err != nil {
					t.Fatalf("Start after failed cleanup: %v", err)
				}
				recv(t, host.defaultReported, "default interface report (restart)")
				if code, _ := getVia(t, proxyClient(t, port), tg.URL+"/hello"); code != 200 {
					t.Fatalf("GET after restart = %d", code)
				}
				if err := e.Close(); err != nil {
					t.Fatalf("final Close: %v", err)
				}
				if _, err := os.Stat(socketPath()); !errors.Is(err, os.ErrNotExist) {
					t.Fatalf("command.sock leaked after final Close: %v", err)
				}
				waitUntil(t, "all subscription goroutines to exit", func() bool {
					return goroutineCount("libbox.(*CommandClient).handle") == 0
				})
			})
		}
	}
}

// 一轮完全正常的 Stop / Close：每一步都执行且都没有错误；第二次 Close 返回 nil。
func TestCleanupStepsHappyPath(t *testing.T) {
	host := newFakeHost()
	host.defaultReported = make(chan struct{}, 4)
	e, _ := newTestEngine(t, host)
	if err := e.Start(cancelConfig(t, freePort(t))); err != nil {
		t.Fatal(err)
	}
	recv(t, host.defaultReported, "default interface report")
	rec := &stepRecord{}
	e.stepObserver = rec.observe
	if err := e.Stop(); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(rec.names, stopStepNames) {
		t.Fatalf("Stop steps = %v", rec.names)
	}
	rec = &stepRecord{}
	e.stepObserver = rec.observe
	if err := e.Close(); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(rec.names, closeStepNames) {
		t.Fatalf("Close steps = %v", rec.names)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("second Close = %v", err)
	}
}
