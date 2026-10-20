package engine

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

// TestMain：libbox.Setup 只做一次，所有测试共用同一个 base 目录（命令服务器的 unix socket 在里面，
// 路径要短，所以放在系统临时目录下的短名字目录里）。测试必须串行：同一时刻只有一个 Engine 占着 command.sock。
var testWorkDir string

func TestMain(m *testing.M) {
	base, err := os.MkdirTemp("", "ce")
	if err != nil {
		panic(err)
	}
	testWorkDir = base + "/work"
	if err := Setup(SetupOptions{
		BasePath:    base,
		WorkingPath: base + "/work",
		TempPath:    base + "/tmp",
		LogMaxLines: 300,
	}); err != nil {
		panic(err)
	}
	code := m.Run()
	_ = os.RemoveAll(base)
	os.Exit(code)
}

// fakeHost 是 Platform 的测试实现，记录所有调用；阻塞点用 channel 控制，不用延时。
type fakeHost struct {
	mu sync.Mutex

	protectCalls atomic.Int32
	logs         chan string

	// StartInterfaceMonitor 的阻塞控制：非 nil 时先向 monitorEntered 发信号，再等 monitorRelease。
	monitorEntered chan struct{}
	monitorRelease chan struct{}
	monitorStarts  atomic.Int32
	monitorStops   atomic.Int32
	monitorStopped chan struct{} // 每次 StopInterfaceMonitor 都会尝试发一个信号（带缓冲）
	monitorStopErr error
	monitorLister  InterfaceListener

	localDNS LocalDNS

	// 非 nil 时，StartInterfaceMonitor 返回后会报告回环为默认接口，并向它发一个信号。
	defaultReported chan struct{}

	// OpenTun 的阻塞控制与记录：非 nil 时先向 tunEntered 发信号，再等 tunRelease。
	tunEntered chan struct{}
	tunRelease chan struct{}
	tunSpecs   chan string
	tunOwned   chan int // 宿主这一侧持有的原始 fd（宿主负责关）
	tunPeers   chan *os.File
}

// setMonitorBlock 设置（或清除）接口监视启动时的阻塞点。
func (f *fakeHost) setMonitorBlock(entered, release chan struct{}) {
	f.mu.Lock()
	f.monitorEntered, f.monitorRelease = entered, release
	f.mu.Unlock()
}

func (f *fakeHost) setTunBlock(entered, release chan struct{}) {
	f.mu.Lock()
	f.tunEntered, f.tunRelease = entered, release
	f.mu.Unlock()
}

func newFakeHost() *fakeHost {
	return &fakeHost{logs: make(chan string, 4096), monitorStopped: make(chan struct{}, 16)}
}

// OpenTun：记录 spec，必要时阻塞，返回一个真实的 socketpair fd（宿主一端），对端交给测试，
// 用对端读到 EOF 来证明「持有这个 fd 的其它拷贝都已关闭」。
func (f *fakeHost) OpenTun(spec string) (int32, error) {
	f.mu.Lock()
	entered, release := f.tunEntered, f.tunRelease
	f.mu.Unlock()
	if f.tunSpecs != nil {
		f.tunSpecs <- spec
	}
	if entered != nil {
		entered <- struct{}{}
		<-release
	}
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err != nil {
		return -1, err
	}
	if f.tunOwned != nil {
		f.tunOwned <- fds[0]
	}
	if f.tunPeers != nil {
		f.tunPeers <- os.NewFile(uintptr(fds[1]), "tun-peer")
	}
	return int32(fds[0]), nil
}
func (f *fakeHost) Protect(int32) error { f.protectCalls.Add(1); return nil }
func (f *fakeHost) UseProcFS() bool     { return false }
func (f *fakeHost) FindOwner(int32, string, int32, string, int32) (string, error) {
	return `{"uid":10001,"packages":["com.example.app"]}`, nil
}

func (f *fakeHost) StartInterfaceMonitor(l InterfaceListener) error {
	f.monitorStarts.Add(1)
	f.mu.Lock()
	f.monitorLister = l
	entered, release := f.monitorEntered, f.monitorRelease
	f.mu.Unlock()
	if entered != nil {
		entered <- struct{}{}
		<-release
	}
	if f.defaultReported != nil {
		// 像真实宿主一样：启动返回之后，由网络回调报告默认接口（这里用回环）。
		go func() {
			if lo, err := loopbackInterface(); err == nil {
				l.Update(lo.Name, int32(lo.Index), false, false)
			}
			select {
			case f.defaultReported <- struct{}{}:
			default:
			}
		}()
	}
	return nil
}

func (f *fakeHost) StopInterfaceMonitor() error {
	f.monitorStops.Add(1)
	select {
	case f.monitorStopped <- struct{}{}:
	default:
	}
	return f.monitorStopErr
}

// InterfacesJSON 只报告回环接口：这是主机上唯一「默认接口」测试需要的，也让 auto_detect_interface 的直连拨号有地方绑。
func (f *fakeHost) InterfacesJSON() (string, error) {
	lo, err := loopbackInterface()
	if err != nil {
		return "", err
	}
	var addrs []string
	if a, err := lo.Addrs(); err == nil {
		for _, ad := range a {
			addrs = append(addrs, ad.String())
		}
	}
	if addrs == nil {
		addrs = []string{}
	}
	list := []map[string]any{{
		"name": lo.Name, "index": lo.Index, "mtu": lo.MTU,
		"flags":     syscall.IFF_UP | syscall.IFF_LOOPBACK | syscall.IFF_RUNNING,
		"type":      3, // InterfaceTypeOther
		"addresses": addrs, "dns": []string{}, "gateway": []string{}, "metered": false,
	}}
	raw, _ := json.Marshal(list)
	return string(raw), nil
}

func loopbackInterface() (*net.Interface, error) {
	all, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for i := range all {
		if all[i].Flags&net.FlagLoopback != 0 {
			return &all[i], nil
		}
	}
	return nil, fmt.Errorf("no loopback interface")
}
func (f *fakeHost) ClearDNSCache()     {}
func (f *fakeHost) LocalDNS() LocalDNS { return f.localDNS }
func (f *fakeHost) WriteLog(line string) {
	select {
	case f.logs <- line:
	default:
	}
}

// fakeHandler 是 Handler 的测试实现。
type fakeHandler struct {
	reloads, stops atomic.Int32
	proxyEnabled   atomic.Bool
}

func (h *fakeHandler) OnReloadRequested()           { h.reloads.Add(1) }
func (h *fakeHandler) OnStopRequested()             { h.stops.Add(1) }
func (h *fakeHandler) SystemProxyAvailable() bool   { return true }
func (h *fakeHandler) SystemProxyEnabled() bool     { return h.proxyEnabled.Load() }
func (h *fakeHandler) SetSystemProxyEnabled(b bool) { h.proxyEnabled.Store(b) }

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

// target 是本地 HTTP 目标：/generate_204 回 204，/hello 回 hello，记录收到的请求路径。
type target struct {
	*httptest.Server
	hits chan string
}

func newTarget(t *testing.T) *target {
	t.Helper()
	tg := &target{hits: make(chan string, 256)}
	tg.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case tg.hits <- r.URL.Path:
		default:
		}
		if r.URL.Path == "/generate_204" {
			// 模拟 3 ms 的链路延迟：测速结果的精度是 1 ms，本机回环太快会记成 0（与「没有数据」混淆）。
			// 这是人为注入的延迟，不是在等某件事发生。
			<-time.After(3 * time.Millisecond)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		io.WriteString(w, "hello")
	}))
	t.Cleanup(tg.Close)
	return tg
}

// testConfig 生成最小可启动配置：mixed 入站 + 两个 direct 出站 + select。
// urltestURL 非空时再加一个 urltest 组 auto（探测地址指向本地目标，不联网）；
// 带 urltest 的配置在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh），只在 !race 的测试里用。
func testConfig(mixedPort int, urltestURL string) string {
	members, def, auto := `"a", "b"`, "a", ""
	if urltestURL != "" {
		members, def = `"auto", "a", "b"`, "auto"
		auto = fmt.Sprintf(`,
    {"type": "urltest", "tag": "auto", "outbounds": ["a", "b"], "url": %q, "interval": "10m"}`, urltestURL)
	}
	return fmt.Sprintf(`{
  "log": {"level": "warn"},
  "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": %d}],
  "outbounds": [
    {"type": "direct", "tag": "a"},
    {"type": "direct", "tag": "b"},
    {"type": "selector", "tag": "select", "outbounds": [%s], "default": %q}%s
  ],
  "route": {"final": "select"}
}`, mixedPort, members, def, auto)
}

func proxyClient(t *testing.T, port int) *http.Client {
	t.Helper()
	u, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	return &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(u), DisableKeepAlives: true},
		Timeout:   30 * time.Second,
	}
}

func getVia(t *testing.T, client *http.Client, target string) (int, string) {
	t.Helper()
	resp, err := client.Get(target)
	if err != nil {
		t.Fatalf("GET %s: %v", target, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

// newTestEngine 建 Engine 并在测试结束时 Close（失败也要释放 socket）。
func newTestEngine(t *testing.T, host *fakeHost) (*Engine, *fakeHandler) {
	t.Helper()
	// libbox 总会创建 cache.db（记住选择组的选择）；每个测试都从干净状态开始，免得上一个测试的选择漏进来。
	_ = os.Remove(testWorkDir + "/cache.db")
	h := &fakeHandler{}
	e, err := New(host, h)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { _ = e.Close() })
	return e, h
}

// goroutineCount 数当前包含 substr 的 goroutine 数（用 runtime 的全量栈）。
func goroutineCount(substr string) int {
	buf := make([]byte, 1<<20)
	for {
		n := runtime.Stack(buf, true)
		if n < len(buf) {
			buf = buf[:n]
			break
		}
		buf = make([]byte, len(buf)*2)
	}
	n := 0
	for _, g := range strings.Split(string(buf), "\n\n") {
		if strings.Contains(g, substr) {
			n++
		}
	}
	return n
}

// waitUntil 在 timeout 内自旋（只让出调度，不睡眠）直到 cond 为真；超时只作失败兜底。
func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timeout waiting for %s", what)
		}
		runtime.Gosched()
	}
}

func replaceOnce(t *testing.T, s, old, new string) string {
	t.Helper()
	if strings.Count(s, old) != 1 {
		t.Fatalf("expected exactly one %q in config", old)
	}
	return strings.Replace(s, old, new, 1)
}
