package e2e

import (
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"

	mdns "github.com/miekg/dns"
)

// DoH 是本地 DNS-over-HTTPS 服务器（HTTP/1.1 over TLS，路径 /dns-query）。
// 它的域名（如 doh.example.net）不会被系统解析：被测配置里由 dns-bootstrap 指向的本地 DNS 解析到回环。
type DoH struct {
	Name string // 证书里的域名
	Port int
	Log  *Log
	CA   *CA

	srv *httptest.Server
}

// NewDoH 起一个 DoH 服务器：证书由 ca 签发（含 name 与 127.0.0.1），答案取自 records。
func NewDoH(t testing.TB, ca *CA, name string, records *Records) *DoH {
	t.Helper()
	d := &DoH{Name: name, Log: NewLog("doh"), CA: ca}
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/dns-query" {
			http.NotFound(w, r)
			return
		}
		var wire []byte
		switch r.Method {
		case http.MethodPost:
			wire, _ = io.ReadAll(r.Body)
		case http.MethodGet:
			wire, _ = base64.RawURLEncoding.DecodeString(r.URL.Query().Get("dns"))
		default:
			http.Error(w, "method", http.StatusMethodNotAllowed)
			return
		}
		req := new(mdns.Msg)
		if err := req.Unpack(wire); err != nil {
			http.Error(w, "bad dns message", http.StatusBadRequest)
			return
		}
		qname, qtype := "", ""
		if len(req.Question) > 0 {
			qname, qtype = normName(req.Question[0].Name), mdns.TypeToString[req.Question[0].Qtype]
		}
		d.Log.Add(Entry{Kind: "dns", Source: r.RemoteAddr, Target: qname, Detail: qtype + "/doh"})
		out, err := records.answer(req).Pack()
		if err != nil {
			http.Error(w, "pack", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/dns-message")
		_, _ = w.Write(out)
	})
	d.srv = httptest.NewUnstartedServer(h)
	d.srv.TLS = &tls.Config{Certificates: []tls.Certificate{ca.Issue(t, name, "127.0.0.1")}, NextProtos: []string{"http/1.1"}}
	d.srv.Listener.Close()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	d.srv.Listener = ln
	d.srv.StartTLS()
	d.Port = ln.Addr().(*net.TCPAddr).Port
	t.Cleanup(d.srv.Close)
	return d
}

// URL 是用域名写的 DoH 地址（需要解析到回环才能连上）。
func (d *DoH) URL() string { return fmt.Sprintf("https://%s:%d/dns-query", d.Name, d.Port) }
