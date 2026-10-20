package engine

import (
	"errors"
	"reflect"
	"runtime/debug"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// libbox.PlatformInterface 的方法数随上游版本变化（v1.14.3 是 27 个），
// 适配器必须全部实现；上游新增方法时这里与编译期断言一起失败，提醒我们逐个决定。
func TestPlatformAdapterImplementsEveryLibboxMethod(t *testing.T) {
	var _ libbox.PlatformInterface = (*platformAdapter)(nil)
	want := reflect.TypeOf((*libbox.PlatformInterface)(nil)).Elem()
	got := reflect.TypeOf(&platformAdapter{})
	if want.NumMethod() != 27 {
		t.Fatalf("libbox.PlatformInterface has %d methods; review the new ones and update the adapter + this number", want.NumMethod())
	}
	for i := 0; i < want.NumMethod(); i++ {
		if _, ok := got.MethodByName(want.Method(i).Name); !ok {
			t.Errorf("adapter lacks %s", want.Method(i).Name)
		}
	}
}

// spec §4.3 的示例 JSON 逐字节一致。
func TestTunSpecMatchesSpecExample(t *testing.T) {
	got, err := buildTunSpec(tunInput{
		MTU: 9000, AutoRoute: true, StrictRoute: true, DNSMode: "hijack",
		DNSServers:      []string{"172.19.0.2"},
		Inet4Address:    []string{"172.19.0.1/28"},
		Inet4RouteRange: []string{"0.0.0.0/1", "128.0.0.0/1"},
	})
	if err != nil {
		t.Fatal(err)
	}
	const want = `{"mtu":9000,"auto_route":true,"strict_route":true,"dns_mode":"hijack",` +
		`"dns_servers":["172.19.0.2"],` +
		`"inet4_address":["172.19.0.1/28"],"inet6_address":[],` +
		`"inet4_route":[],"inet6_route":[],"inet4_route_exclude":[],"inet6_route_exclude":[],` +
		`"inet4_route_range":["0.0.0.0/1","128.0.0.0/1"],"inet6_route_range":[],` +
		`"include_package":[],"exclude_package":[],` +
		`"http_proxy":{"enabled":false,"server":"","port":0,"bypass":[],"match":[]}}`
	if got != want {
		t.Fatalf("TunSpec\n got: %s\nwant: %s", got, want)
	}
}

func TestTunSpecVariants(t *testing.T) {
	// 空 dns_mode 补成内核默认的 hijack；http_proxy 打开时带上全部字段
	got, err := buildTunSpec(tunInput{
		MTU:          1500,
		Inet6Address: []string{"fdfe:dcba:9876::1/126"},
		HTTPProxy:    &httpProxy{Enabled: true, Server: "127.0.0.1", Port: 2080, Bypass: []string{"*.lan"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		`"dns_mode":"hijack"`, `"inet6_address":["fdfe:dcba:9876::1/126"]`, `"inet4_address":[]`,
		`"http_proxy":{"enabled":true,"server":"127.0.0.1","port":2080,"bypass":["*.lan"],"match":[]}`,
	} {
		if !contains(got, want) {
			t.Errorf("%s lacks %s", got, want)
		}
	}
	// disabled 原样透传
	got, _ = buildTunSpec(tunInput{DNSMode: "disabled"})
	if !contains(got, `"dns_mode":"disabled"`) {
		t.Errorf("dns_mode disabled not preserved: %s", got)
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func TestInterfacesJSONRoundTrip(t *testing.T) {
	const in = `[{"name":"wlan0","index":3,"mtu":1500,"flags":69,"type":0,"addresses":["192.0.2.10/24","2001:db8::10/64"],"dns":["192.0.2.1"],"gateway":["192.0.2.1"],"metered":true},` +
		`{"name":"lo","index":1,"mtu":65536,"flags":73,"type":3,"addresses":[],"dns":[],"gateway":[],"metered":false}]`
	it, err := parseInterfaces(in)
	if err != nil {
		t.Fatal(err)
	}
	var got []*libbox.NetworkInterface
	for it.HasNext() {
		got = append(got, it.Next())
	}
	if len(got) != 2 {
		t.Fatalf("got %d interfaces", len(got))
	}
	w := got[0]
	if w.Name != "wlan0" || w.Index != 3 || w.MTU != 1500 || w.Flags != 69 || w.Type != 0 || !w.Metered {
		t.Fatalf("scalar fields wrong: %+v", w)
	}
	drain := func(it libbox.StringIterator) []string {
		var out []string
		for it.HasNext() {
			out = append(out, it.Next())
		}
		return out
	}
	if !reflect.DeepEqual(drain(w.Addresses), []string{"192.0.2.10/24", "2001:db8::10/64"}) ||
		!reflect.DeepEqual(drain(w.DNSServer), []string{"192.0.2.1"}) ||
		!reflect.DeepEqual(drain(w.Gateway), []string{"192.0.2.1"}) {
		t.Fatalf("list fields wrong: %+v", w)
	}
	if got[1].Name != "lo" || got[1].Addresses.HasNext() {
		t.Fatalf("second interface wrong: %+v", got[1])
	}
	if _, err := parseInterfaces(`not json`); err == nil {
		t.Fatal("bad JSON must fail")
	}
}

func TestFindConnectionOwner(t *testing.T) {
	pa := newPlatformAdapter(newFakeHost())
	o, err := pa.FindConnectionOwner(6, "10.0.0.2", 1234, "192.0.2.1", 443)
	if err != nil {
		t.Fatal(err)
	}
	if o.UserId != 10001 {
		t.Fatalf("uid = %d", o.UserId)
	}
	pk := o.AndroidPackageNames()
	if !pk.HasNext() || pk.Next() != "com.example.app" {
		t.Fatal("package names not carried over")
	}
}

type badOwnerHost struct{ *fakeHost }

func (badOwnerHost) FindOwner(int32, string, int32, string, int32) (string, error) {
	return "not json", nil
}

type failOwnerHost struct{ *fakeHost }

func (failOwnerHost) FindOwner(int32, string, int32, string, int32) (string, error) {
	return "", errors.New("android: connection owner not found")
}

func TestFindConnectionOwnerErrors(t *testing.T) {
	if _, err := newPlatformAdapter(badOwnerHost{newFakeHost()}).FindConnectionOwner(6, "a", 1, "b", 2); err == nil {
		t.Fatal("bad JSON must fail")
	}
	if _, err := newPlatformAdapter(failOwnerHost{newFakeHost()}).FindConnectionOwner(6, "a", 1, "b", 2); err == nil {
		t.Fatal("host error must propagate")
	}
}

type fakeLocalDNS struct{}

func (fakeLocalDNS) Raw() bool                            { return true }
func (fakeLocalDNS) Exchange(c *DNSCall, m []byte) error  { c.ErrorCode(2); return nil }
func (fakeLocalDNS) Lookup(c *DNSCall, n, d string) error { c.Success("192.0.2.1\n"); return nil }

func TestLocalDNSTransportNilnessAndForwarding(t *testing.T) {
	host := newFakeHost()
	if pa := newPlatformAdapter(host); pa.LocalDNSTransport() != nil {
		t.Fatal("no host LocalDNS must give a true nil interface (libbox keys off it)")
	}
	host.localDNS = fakeLocalDNS{}
	tr := newPlatformAdapter(host).LocalDNSTransport()
	if tr == nil || !tr.Raw() {
		t.Fatal("LocalDNS not wired")
	}
	ctx := &libbox.ExchangeContext{}
	if err := tr.Exchange(ctx, nil); err != nil {
		t.Fatal(err)
	}
	if err := tr.Lookup(ctx, "ip4", "example.com."); err != nil {
		t.Fatal(err)
	}
}

func TestMemoryLimitApplied(t *testing.T) {
	prevGC := debug.SetGCPercent(100)
	prevLimit := debug.SetMemoryLimit(-1)
	defer func() { debug.SetGCPercent(prevGC); debug.SetMemoryLimit(prevLimit) }()
	applyMemoryLimit(false)
	if got := debug.SetGCPercent(100); got != 100 {
		t.Fatalf("unlimited mode must not touch GC percent, got %d", got)
	}
	applyMemoryLimit(true)
	if got := debug.SetGCPercent(100); got != memoryLimitedGCPercent {
		t.Fatalf("GC percent = %d, want %d", got, memoryLimitedGCPercent)
	}
	if got := debug.SetMemoryLimit(-1); got != memoryLimitedSoftLimit {
		t.Fatalf("soft limit = %d, want %d", got, memoryLimitedSoftLimit)
	}
}
