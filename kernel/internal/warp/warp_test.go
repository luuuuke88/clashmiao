package warp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 合成夹具：密钥 / 地址都是随机或保留地址，不对应任何真实账号。
const (
	peerPub  = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
	clientID = "AQID" // 01 02 03
)

type apiCall struct {
	Method, Path, Auth string
	Body               map[string]any
}

// fakeAPI 模拟 Cloudflare 的三个接口，并记录每个请求。
type fakeAPI struct {
	srv *httptest.Server

	mu    sync.Mutex
	calls []apiCall

	failRegister int // 非 0：POST /reg 返回此状态码
	failLicense  int // 非 0：PUT .../account 返回此状态码
	failDelete   int // 非 0：DELETE 返回此状态码
}

func newFakeAPI(t *testing.T) *fakeAPI {
	t.Helper()
	f := &fakeAPI{}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeAPI) record(r *http.Request) apiCall {
	c := apiCall{Method: r.Method, Path: r.URL.Path, Auth: r.Header.Get("Authorization")}
	if r.Body != nil {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		c.Body = b
	}
	f.mu.Lock()
	f.calls = append(f.calls, c)
	f.mu.Unlock()
	return c
}

func (f *fakeAPI) device(license string) map[string]any {
	return map[string]any{
		"id":      "dev-1",
		"token":   "tok-1",
		"account": map[string]any{"id": "acct-1", "license": license},
		"config": map[string]any{
			"client_id": clientID,
			"peers":     []any{map[string]any{"public_key": peerPub}},
			"interface": map[string]any{"addresses": map[string]any{"v4": "172.16.0.2", "v6": "2606:4700:110:8a36:df92:102a:9602:fa18"}},
		},
	}
}

func (f *fakeAPI) handle(w http.ResponseWriter, r *http.Request) {
	c := f.record(r)
	reply := func(status int, v any) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		if v != nil {
			_ = json.NewEncoder(w).Encode(v)
		}
	}
	switch {
	case r.Method == http.MethodPost && r.URL.Path == "/v0a2158/reg":
		if f.failRegister != 0 {
			reply(f.failRegister, map[string]any{"error": "nope"})
			return
		}
		reply(200, f.device("free-license"))
	case r.Method == http.MethodPut && strings.HasSuffix(r.URL.Path, "/account"):
		if f.failLicense != 0 {
			reply(f.failLicense, map[string]any{"error": "bad license"})
			return
		}
		lic, _ := c.Body["license"].(string)
		reply(200, f.device(lic))
	case r.Method == http.MethodGet:
		reply(200, f.device("bound-license"))
	case r.Method == http.MethodDelete:
		if f.failDelete != 0 {
			reply(f.failDelete, nil)
			return
		}
		reply(204, nil)
	default:
		reply(404, nil)
	}
}

// rewriteTransport 把发往 Cloudflare 的请求改道到 httptest 服务器。
type rewriteTransport struct{ target *url.URL }

func (rt rewriteTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	r2 := r.Clone(r.Context())
	r2.URL.Scheme, r2.URL.Host = rt.target.Scheme, rt.target.Host
	return http.DefaultTransport.RoundTrip(r2)
}

func (f *fakeAPI) client(t *testing.T) *http.Client {
	u, err := url.Parse(f.srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	return &http.Client{Transport: rewriteTransport{target: u}}
}

func (f *fakeAPI) seen() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []string
	for _, c := range f.calls {
		out = append(out, c.Method+" "+strings.TrimPrefix(c.Path, "/v0a2158"))
	}
	return out
}

func TestRegisterSuccess(t *testing.T) {
	f := newFakeAPI(t)
	acc, err := Register(context.Background(), f.client(t), "")
	if err != nil {
		t.Fatal(err)
	}
	if got := f.seen(); !reflect.DeepEqual(got, []string{"POST /reg"}) {
		t.Fatalf("calls = %v", got)
	}
	if acc.ID != "dev-1" || acc.Token != "tok-1" {
		t.Errorf("account = %+v", acc)
	}
	// 私钥是 32 字节 base64，公钥由它推出并随注册上送
	raw, err := base64.StdEncoding.DecodeString(acc.Config.PrivateKey)
	if err != nil || len(raw) != 32 {
		t.Fatalf("private key = %q (%v)", acc.Config.PrivateKey, err)
	}
	sent, _ := f.calls[0].Body["key"].(string)
	if sent == "" || sent == acc.Config.PrivateKey {
		t.Errorf("注册上送的应是公钥，而不是私钥: %q", sent)
	}
	if acc.Config.PeerPublicKey != peerPub || acc.Config.ClientID != clientID || acc.Config.LocalAddressIPv4 != "172.16.0.2" {
		t.Errorf("config = %+v", acc.Config)
	}
	if _, err := ParseConfig(mustJSON(t, acc.Config)); err != nil {
		t.Errorf("产出的配置自己都不认: %v", err)
	}
}

func TestRegisterWithLicenseBindsAndRefreshes(t *testing.T) {
	f := newFakeAPI(t)
	acc, err := Register(context.Background(), f.client(t), "key-123")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"POST /reg", "PUT /reg/dev-1/account", "GET /reg/dev-1"}
	if got := f.seen(); !reflect.DeepEqual(got, want) {
		t.Fatalf("calls = %v, want %v", got, want)
	}
	if f.calls[1].Auth != "Bearer tok-1" || f.calls[1].Body["license"] != "key-123" {
		t.Errorf("PUT = %+v", f.calls[1])
	}
	if acc.License != "key-123" {
		t.Errorf("license = %q", acc.License)
	}
}

// license 无效：返回 ErrLicense（带前缀），并清掉刚注册的设备，不留孤儿。
func TestRegisterLicenseRejectedDeletesNewDevice(t *testing.T) {
	f := newFakeAPI(t)
	f.failLicense = http.StatusBadRequest
	_, err := Register(context.Background(), f.client(t), "bad-key")
	if !errors.Is(err, ErrLicense) || !strings.HasPrefix(err.Error(), PrefixLicense) {
		t.Fatalf("err = %v", err)
	}
	want := []string{"POST /reg", "PUT /reg/dev-1/account", "DELETE /reg/dev-1"}
	if got := f.seen(); !reflect.DeepEqual(got, want) {
		t.Fatalf("calls = %v, want %v", got, want)
	}
}

func TestRegisterServerErrorIsNotLicense(t *testing.T) {
	f := newFakeAPI(t)
	f.failLicense = http.StatusInternalServerError
	_, err := Register(context.Background(), f.client(t), "key")
	if errors.Is(err, ErrLicense) || !errors.Is(err, ErrRegister) {
		t.Fatalf("5xx 不该被当成 license 无效: %v", err)
	}
}

func TestRegisterNetworkFailure(t *testing.T) {
	f := newFakeAPI(t)
	c := f.client(t)
	f.srv.Close() // 对端不可达
	_, err := Register(context.Background(), c, "")
	if !errors.Is(err, ErrNetwork) || !strings.HasPrefix(err.Error(), PrefixNetwork) {
		t.Fatalf("err = %v", err)
	}
}

func TestRegisterRejectedByServer(t *testing.T) {
	f := newFakeAPI(t)
	f.failRegister = http.StatusTooManyRequests
	_, err := Register(context.Background(), f.client(t), "")
	if !errors.Is(err, ErrRegister) || !strings.HasPrefix(err.Error(), PrefixRegister) || !strings.Contains(err.Error(), "429") {
		t.Fatalf("err = %v", err)
	}
}

func TestRegisterContextCancelled(t *testing.T) {
	f := newFakeAPI(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Register(ctx, f.client(t), ""); !errors.Is(err, ErrNetwork) {
		t.Fatalf("err = %v", err)
	}
	if len(f.seen()) != 0 {
		t.Fatalf("已取消的上下文不该发出请求: %v", f.seen())
	}
}

func TestDelete(t *testing.T) {
	f := newFakeAPI(t)
	if err := Delete(context.Background(), f.client(t), "dev-9", "tok-9"); err != nil {
		t.Fatal(err)
	}
	if f.calls[0].Auth != "Bearer tok-9" || f.calls[0].Path != "/v0a2158/reg/dev-9" {
		t.Errorf("DELETE = %+v", f.calls[0])
	}
	f.failDelete = http.StatusNotFound
	if err := Delete(context.Background(), f.client(t), "dev-9", "tok-9"); err != nil {
		t.Errorf("设备已不存在应按成功处理: %v", err)
	}
	f.failDelete = http.StatusUnauthorized
	if err := Delete(context.Background(), f.client(t), "dev-9", "tok-9"); !errors.Is(err, ErrRegister) {
		t.Errorf("401 应报错: %v", err)
	}
	if err := Delete(context.Background(), f.client(t), "", ""); err == nil {
		t.Error("缺少 id / token 应报错")
	}
}

// GenerateWarpConfig 的返回键集合与旧 Dart 契约一致；有旧账号时注册成功后才删旧设备。
func TestGenerateMatchesLegacyContract(t *testing.T) {
	f := newFakeAPI(t)
	out, err := Generate(context.Background(), f.client(t), "", "old-dev", "old-tok")
	if err != nil {
		t.Fatal(err)
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal([]byte(out), &top); err != nil {
		t.Fatal(err)
	}
	if got := keys(top); !reflect.DeepEqual(got, []string{"access-token", "account-id", "config", "log"}) {
		t.Errorf("顶层键 = %v", got)
	}
	var cfg map[string]json.RawMessage
	if err := json.Unmarshal(top["config"], &cfg); err != nil {
		t.Fatal(err)
	}
	if got := keys(cfg); !reflect.DeepEqual(got, []string{"client-id", "local-address-ipv4", "local-address-ipv6", "peer-public-key", "private-key"}) {
		t.Errorf("config 键 = %v", got)
	}
	if want := []string{"POST /reg", "DELETE /reg/old-dev"}; !reflect.DeepEqual(f.seen(), want) {
		t.Errorf("calls = %v, want %v（先注册、后删旧）", f.seen(), want)
	}
	if f.calls[1].Auth != "Bearer old-tok" {
		t.Errorf("删旧设备应带旧令牌: %+v", f.calls[1])
	}
	// 能被 ParseConfig 接受（Dart 原样存回，构建器再解析）
	var res GenerateResult
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatal(err)
	}
	if _, err := ParseConfig(mustJSON(t, res.Config)); err != nil {
		t.Errorf("ParseConfig: %v", err)
	}
}

func TestGenerateKeepsOldAccountWhenRegistrationFails(t *testing.T) {
	f := newFakeAPI(t)
	f.failRegister = http.StatusInternalServerError
	if _, err := Generate(context.Background(), f.client(t), "", "old-dev", "old-tok"); err == nil {
		t.Fatal("注册失败应报错")
	}
	for _, c := range f.seen() {
		if strings.HasPrefix(c, "DELETE") {
			t.Fatalf("注册失败时不能删除旧设备: %v", f.seen())
		}
	}
}

func TestGenerateOldDeleteFailureIsOnlyLogged(t *testing.T) {
	f := newFakeAPI(t)
	f.failDelete = http.StatusInternalServerError
	out, err := Generate(context.Background(), f.client(t), "", "old-dev", "old-tok")
	if err != nil {
		t.Fatalf("删旧设备失败不该让整个生成失败: %v", err)
	}
	var res GenerateResult
	_ = json.Unmarshal([]byte(out), &res)
	if !strings.Contains(res.Log, "was not deleted") {
		t.Errorf("log = %q", res.Log)
	}
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func validConfig(t *testing.T) WireguardConfig {
	t.Helper()
	priv, _, err := newKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	return WireguardConfig{PrivateKey: priv, LocalAddressIPv4: "172.16.0.2", LocalAddressIPv6: "2606:4700:110:8a36::2", PeerPublicKey: peerPub, ClientID: clientID}
}

func TestParseConfig(t *testing.T) {
	good := validConfig(t)
	if _, err := ParseConfig(mustJSON(t, good)); err != nil {
		t.Fatal(err)
	}
	mut := func(f func(*WireguardConfig)) string { c := good; f(&c); return mustJSON(t, c) }
	cases := map[string]string{
		"empty":         "",
		"not json":      "nope",
		"short key":     mut(func(c *WireguardConfig) { c.PrivateKey = "AAAA" }),
		"key not b64":   mut(func(c *WireguardConfig) { c.PrivateKey = "!!!" }),
		"peer key":      mut(func(c *WireguardConfig) { c.PeerPublicKey = "" }),
		"v4 empty":      mut(func(c *WireguardConfig) { c.LocalAddressIPv4 = "" }),
		"v4 is v6":      mut(func(c *WireguardConfig) { c.LocalAddressIPv4 = "2606:4700::1" }),
		"v6 is v4":      mut(func(c *WireguardConfig) { c.LocalAddressIPv6 = "172.16.0.2" }),
		"client id b64": mut(func(c *WireguardConfig) { c.ClientID = "!!" }),
		"client id len": mut(func(c *WireguardConfig) { c.ClientID = "AQI=" }),
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := ParseConfig(raw)
			if !errors.Is(err, ErrConfig) || !strings.HasPrefix(err.Error(), "warp-config-invalid:") {
				t.Fatalf("err = %v", err)
			}
		})
	}
}

func TestEndpointShape(t *testing.T) {
	c := validConfig(t)
	o := options.Default().Warp

	ep, err := Endpoint(c, o, "")
	if err != nil {
		t.Fatal(err)
	}
	if Tag != "warp" || ep["type"] != "wireguard" || ep["tag"] != "warp" {
		t.Errorf("type/tag = %v/%v", ep["type"], ep["tag"])
	}
	if !reflect.DeepEqual(ep["address"], []any{"172.16.0.2/24", "2606:4700:110:8a36::2/128"}) {
		t.Errorf("address = %v", ep["address"])
	}
	if ep["mtu"] != 1330 {
		t.Errorf("直连时 mtu = %v", ep["mtu"])
	}
	if _, has := ep["detour"]; has {
		t.Error("无 detour 时不该写 detour 字段")
	}
	peer := ep["peers"].([]any)[0].(map[string]any)
	if peer["address"] != DefaultEntry || peer["port"] != DefaultEntryPort || peer["public_key"] != peerPub {
		t.Errorf("peer = %v", peer)
	}
	if !reflect.DeepEqual(peer["reserved"], []any{1, 2, 3}) {
		t.Errorf("reserved = %v", peer["reserved"])
	}
	if !reflect.DeepEqual(peer["allowed_ips"], []any{"0.0.0.0/0", "::/0"}) {
		t.Errorf("allowed_ips = %v", peer["allowed_ips"])
	}

	// 有 detour：写入 detour，MTU 让出外层开销
	ep, err = Endpoint(c, o, "select")
	if err != nil {
		t.Fatal(err)
	}
	if ep["detour"] != "select" || ep["mtu"] != 1280 {
		t.Errorf("detour/mtu = %v/%v", ep["detour"], ep["mtu"])
	}

	// 干净 IP / 端口
	o.CleanIP, o.CleanPort = "203.0.113.9", 4500
	ep, _ = Endpoint(c, o, "")
	peer = ep["peers"].([]any)[0].(map[string]any)
	if peer["address"] != "203.0.113.9" || peer["port"] != 4500 {
		t.Errorf("clean ip/port 没有生效: %v", peer)
	}

	// 没有 v6、没有 client-id
	c.LocalAddressIPv6, c.ClientID = "", ""
	ep, err = Endpoint(c, o, "")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(ep["address"], []any{"172.16.0.2/24"}) {
		t.Errorf("address = %v", ep["address"])
	}
	if _, has := ep["peers"].([]any)[0].(map[string]any)["reserved"]; has {
		t.Error("没有 client-id 不该写 reserved")
	}
}

func TestEndpointRejectsBadConfig(t *testing.T) {
	c := validConfig(t)
	c.LocalAddressIPv4 = "not-an-ip"
	if _, err := Endpoint(c, options.Default().Warp, ""); !errors.Is(err, ErrConfig) {
		t.Fatalf("err = %v", err)
	}
}

func TestNoiseWarningsOnlyWhenNonDefault(t *testing.T) {
	def := options.Default().Warp
	if w := NoiseWarnings(def, def); len(w) != 0 {
		t.Fatalf("默认值不该有警告: %v", w)
	}
	o := def
	o.Noise, o.NoiseMode = "5-9", "m4"
	w := NoiseWarnings(o, def)
	if len(w) != 2 || !strings.Contains(w[0], "warp.noise") || !strings.Contains(w[1], "warp.noise-mode") {
		t.Fatalf("warnings = %v", w)
	}
}
