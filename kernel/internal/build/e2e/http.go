package e2e

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// HTTPTarget 是本地 HTTP 目标：/generate_204 回 204，其它路径回 "ok"；每个请求都记录来源与 Host。
type HTTPTarget struct {
	Port int
	Log  *Log

	srv *httptest.Server
}

func newHTTP(t testing.TB, listen string) (*HTTPTarget, error) {
	ln, err := net.Listen("tcp", listen)
	if err != nil {
		return nil, err
	}
	h := &HTTPTarget{Log: NewLog("http")}
	h.srv = httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.Log.Add(Entry{Kind: "http", Source: r.RemoteAddr, Target: r.Host + r.URL.Path})
		if r.URL.Path == "/generate_204" {
			// 模拟 3 ms 的链路延迟：测速结果按毫秒取整，本机回环太快会记成 0，与「没有结果」同值（内核也按失败处理）。
			// 这是人为注入的延迟，不是在等某件事发生。
			<-time.After(3 * time.Millisecond)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		_, _ = io.WriteString(w, "ok")
	}))
	h.srv.Listener.Close()
	h.srv.Listener = ln
	h.srv.Start()
	h.Port = ln.Addr().(*net.TCPAddr).Port
	t.Cleanup(h.srv.Close)
	return h, nil
}

// NewHTTP 在 127.0.0.1 上起一个目标。
func NewHTTP(t testing.TB) *HTTPTarget {
	t.Helper()
	h, err := newHTTP(t, "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	return h
}

// NewHTTPOnPort 在指定回环地址（"127.0.0.1" 或 "::1"）与端口上起目标；port 为 0 则随机。
// 环境不支持时返回错误，由调用方决定 t.Skip（不静默通过）。
func NewHTTPOnPort(t testing.TB, host string, port int) (*HTTPTarget, error) {
	t.Helper()
	return newHTTP(t, net.JoinHostPort(host, fmt.Sprint(port)))
}

// URL 用给定主机名拼 URL（主机名由被测配置的 DNS 解析到回环）。
func (h *HTTPTarget) URL(host, path string) string {
	return fmt.Sprintf("http://%s%s", net.JoinHostPort(host, fmt.Sprint(h.Port)), path)
}
