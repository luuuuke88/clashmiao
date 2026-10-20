package e2e

import (
	"fmt"
	"net"
	"net/netip"
	"strings"
	"sync"
	"testing"

	mdns "github.com/miekg/dns"
)

// Records 是名称 → IP 的映射；同一个名字可以同时有 A 与 AAAA。
type Records struct {
	mu sync.RWMutex
	m  map[string][]netip.Addr
}

// NewRecords 用 {"name": {"ip", ...}} 初始化（名字大小写不敏感、末尾的点可有可无）。
func NewRecords(init map[string][]string) *Records {
	r := &Records{m: map[string][]netip.Addr{}}
	for name, ips := range init {
		r.Set(name, ips...)
	}
	return r
}

func normName(n string) string { return strings.ToLower(strings.TrimSuffix(n, ".")) }

// Set 覆盖一个名字的全部地址。
func (r *Records) Set(name string, ips ...string) {
	var addrs []netip.Addr
	for _, s := range ips {
		a, err := netip.ParseAddr(s)
		if err != nil {
			panic(fmt.Sprintf("e2e: bad IP %q", s))
		}
		addrs = append(addrs, a)
	}
	r.mu.Lock()
	r.m[normName(name)] = addrs
	r.mu.Unlock()
}

func (r *Records) lookup(name string) ([]netip.Addr, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	a, ok := r.m[normName(name)]
	return a, ok
}

// answer 按记录给一条查询生成应答：未知名字 NXDOMAIN；已知但没有该地址族的是 NOERROR + 空答案。
func (r *Records) answer(req *mdns.Msg) *mdns.Msg {
	resp := new(mdns.Msg)
	resp.SetReply(req)
	resp.Authoritative = true
	if len(req.Question) == 0 {
		resp.Rcode = mdns.RcodeFormatError
		return resp
	}
	q := req.Question[0]
	addrs, known := r.lookup(q.Name)
	if !known {
		resp.Rcode = mdns.RcodeNameError
		return resp
	}
	for _, a := range addrs {
		switch {
		case q.Qtype == mdns.TypeA && a.Is4():
			resp.Answer = append(resp.Answer, &mdns.A{Hdr: mdns.RR_Header{Name: q.Name, Rrtype: mdns.TypeA, Class: mdns.ClassINET, Ttl: 60}, A: a.AsSlice()})
		case q.Qtype == mdns.TypeAAAA && a.Is6():
			resp.Answer = append(resp.Answer, &mdns.AAAA{Hdr: mdns.RR_Header{Name: q.Name, Rrtype: mdns.TypeAAAA, Class: mdns.ClassINET, Ttl: 60}, AAAA: a.AsSlice()})
		}
	}
	return resp
}

// DNS 是同端口的本地 UDP + TCP DNS 服务器。
type DNS struct {
	Records *Records
	Log     *Log
	Port    int

	udp *mdns.Server
	tcp *mdns.Server
}

// NewDNS 在 127.0.0.1 上起 DNS 服务器，测试结束自动关闭。
func NewDNS(t testing.TB, records *Records) *DNS {
	t.Helper()
	d := &DNS{Records: records, Log: NewLog("dns")}
	var pc net.PacketConn
	var ln net.Listener
	for attempt := 0; attempt < 20; attempt++ {
		var err error
		pc, err = net.ListenPacket("udp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		port := pc.LocalAddr().(*net.UDPAddr).Port
		ln, err = net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
		if err == nil {
			d.Port = port
			break
		}
		pc.Close()
		pc = nil
	}
	if pc == nil {
		t.Fatal("e2e: cannot find a port free for both UDP and TCP")
	}
	handler := func(network string) mdns.HandlerFunc {
		return func(w mdns.ResponseWriter, req *mdns.Msg) {
			qname, qtype := "", ""
			if len(req.Question) > 0 {
				qname, qtype = normName(req.Question[0].Name), mdns.TypeToString[req.Question[0].Qtype]
			}
			d.Log.Add(Entry{Kind: "dns", Source: w.RemoteAddr().String(), Target: qname, Detail: qtype + "/" + network})
			_ = w.WriteMsg(d.Records.answer(req))
		}
	}
	started := make(chan struct{}, 2)
	d.udp = &mdns.Server{PacketConn: pc, Handler: handler("udp"), NotifyStartedFunc: func() { started <- struct{}{} }}
	d.tcp = &mdns.Server{Listener: ln, Handler: handler("tcp"), NotifyStartedFunc: func() { started <- struct{}{} }}
	go func() { _ = d.udp.ActivateAndServe() }()
	go func() { _ = d.tcp.ActivateAndServe() }()
	<-started
	<-started
	t.Cleanup(func() { _ = d.udp.Shutdown(); _ = d.tcp.Shutdown() })
	return d
}

// Addr 是 host:port 形式的监听地址。
func (d *DNS) Addr() string { return fmt.Sprintf("127.0.0.1:%d", d.Port) }

// Queries 返回某个名字被查询过的次数（不区分类型与传输）。
func (d *DNS) Queries(name string) int {
	name = normName(name)
	return d.Log.Count(func(e Entry) bool { return e.Target == name })
}
