package core

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
)

// 门面的 GenerateWarpConfig 经注入的客户端改道到本地假服务器：返回旧 Dart 契约的 JSON，
// 先注册、后删旧设备；失败时错误前缀可识别。（注册流程本身的细节在 internal/warp 的测试里。）
type rewrite struct{ to *url.URL }

func (r rewrite) RoundTrip(req *http.Request) (*http.Response, error) {
	c := req.Clone(req.Context())
	c.URL.Scheme, c.URL.Host = r.to.Scheme, r.to.Host
	return http.DefaultTransport.RoundTrip(c)
}

func withFakeCloudflare(t *testing.T, status int) *[]string {
	t.Helper()
	var mu sync.Mutex
	var calls []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		calls = append(calls, r.Method)
		mu.Unlock()
		if status != 0 && r.Method == http.MethodPost {
			w.WriteHeader(status)
			return
		}
		if r.Method == http.MethodDelete {
			w.WriteHeader(204)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": "dev-1", "token": "tok-1",
			"account": map[string]any{"license": "l"},
			"config": map[string]any{
				"client_id": "AQID",
				"peers":     []any{map[string]any{"public_key": "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8="}},
				"interface": map[string]any{"addresses": map[string]any{"v4": "172.16.0.2", "v6": "2001:db8::2"}},
			},
		})
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	old := warpClient
	warpClient = &http.Client{Transport: rewrite{to: u}}
	t.Cleanup(func() { warpClient = old })
	return &calls
}

func TestGenerateWarpConfigFacade(t *testing.T) {
	calls := withFakeCloudflare(t, 0)
	out, err := GenerateWarpConfig("", "old-dev", "old-tok")
	if err != nil {
		t.Fatal(err)
	}
	var res map[string]json.RawMessage
	if err := json.Unmarshal([]byte(out), &res); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"account-id", "access-token", "log", "config"} {
		if _, ok := res[k]; !ok {
			t.Errorf("缺少键 %s: %s", k, out)
		}
	}
	if got := strings.Join(*calls, ","); got != "POST,DELETE" {
		t.Errorf("调用序列 = %s，期望先注册后删旧设备", got)
	}
}

func TestGenerateWarpConfigFacadeErrorPrefix(t *testing.T) {
	withFakeCloudflare(t, http.StatusTooManyRequests)
	_, err := GenerateWarpConfig("", "", "")
	if err == nil || !strings.HasPrefix(err.Error(), "warp-register-failed:") {
		t.Fatalf("err = %v", err)
	}
}
