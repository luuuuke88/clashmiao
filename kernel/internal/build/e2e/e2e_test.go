package e2e

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	mdns "github.com/miekg/dns"
)

func httpGet(t *testing.T, c *http.Client, u string) (int, string) {
	t.Helper()
	resp, err := c.Get(u)
	if err != nil {
		t.Fatalf("GET %s: %v", u, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

func TestReqLogWaitForIsEventDriven(t *testing.T) {
	l := NewLog("x")
	ch := l.WaitFor(2)
	select {
	case <-ch:
		t.Fatal("空记录不该满足 WaitFor(2)")
	default:
	}
	l.Add(Entry{Kind: "a"})
	select {
	case <-ch:
		t.Fatal("一条记录不该满足 WaitFor(2)")
	default:
	}
	l.Add(Entry{Kind: "b"})
	select {
	case <-ch:
	case <-time.After(30 * time.Second):
		t.Fatal("第二条记录后 WaitFor(2) 应当就绪")
	}
	// 已满足的条件立刻就绪。
	select {
	case <-l.WaitFor(1):
	default:
		t.Fatal("已满足的 WaitFor 应立即就绪")
	}
}

func TestDNSAnswersUDPAndTCPWithRecords(t *testing.T) {
	d := NewDNS(t, NewRecords(map[string][]string{
		"v4.example.net":   {"192.0.2.10"},
		"dual.example.net": {"192.0.2.11", "2001:db8::11"},
		"v6.example.net":   {"2001:db8::12"},
	}))
	ask := func(network, name string, qtype uint16) *mdns.Msg {
		t.Helper()
		m := new(mdns.Msg)
		m.SetQuestion(mdns.Fqdn(name), qtype)
		resp, _, err := (&mdns.Client{Net: network}).Exchange(m, d.Addr())
		if err != nil {
			t.Fatalf("%s %s: %v", network, name, err)
		}
		return resp
	}
	for _, network := range []string{"udp", "tcp"} {
		if r := ask(network, "dual.example.net", mdns.TypeA); len(r.Answer) != 1 || r.Answer[0].(*mdns.A).A.String() != "192.0.2.11" {
			t.Errorf("%s A = %v", network, r.Answer)
		}
		if r := ask(network, "dual.example.net", mdns.TypeAAAA); len(r.Answer) != 1 || r.Answer[0].(*mdns.AAAA).AAAA.String() != "2001:db8::11" {
			t.Errorf("%s AAAA = %v", network, r.Answer)
		}
		// 已知名字没有该地址族：NOERROR + 空答案（不是 NXDOMAIN）。
		if r := ask(network, "v4.example.net", mdns.TypeAAAA); r.Rcode != mdns.RcodeSuccess || len(r.Answer) != 0 {
			t.Errorf("%s v4-only 的 AAAA = rcode %d %v", network, r.Rcode, r.Answer)
		}
		if r := ask(network, "nope.example.net", mdns.TypeA); r.Rcode != mdns.RcodeNameError {
			t.Errorf("%s 未知名字 rcode = %d，期望 NXDOMAIN", network, r.Rcode)
		}
	}
	if got := d.Queries("dual.example.net"); got != 4 {
		t.Errorf("记录里 dual.example.net 的查询数 = %d，期望 4（A / AAAA × udp / tcp）", got)
	}
	if !d.Log.Has(func(e Entry) bool { return e.Detail == "AAAA/tcp" }) {
		t.Errorf("记录应区分类型与传输: %v", d.Log.Entries())
	}
}

// 名字（doh.example.net）本机解析不了：用拨号覆盖把它指到回环，证书里的域名与 CA 都真验证。
func TestDoHAnswersOverTLSWithTestCA(t *testing.T) {
	ca := NewCA(t)
	doh := NewDoH(t, ca, "doh.example.net", NewRecords(map[string][]string{"a.example.net": {"192.0.2.20"}}))
	client := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{RootCAs: ca.Pool()},
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, fmt.Sprintf("127.0.0.1:%d", doh.Port))
		},
	}}
	m := new(mdns.Msg)
	m.SetQuestion("a.example.net.", mdns.TypeA)
	wire, _ := m.Pack()
	resp, err := client.Post(doh.URL(), "application/dns-message", strings.NewReader(string(wire)))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var out mdns.Msg
	if err := out.Unpack(body); err != nil || len(out.Answer) != 1 || out.Answer[0].(*mdns.A).A.String() != "192.0.2.20" {
		t.Fatalf("DoH 应答不对: %v %v", err, out.Answer)
	}
	if got := doh.Log.Entries(); len(got) != 1 || got[0].Target != "a.example.net" || got[0].Detail != "A/doh" {
		t.Errorf("DoH 记录 = %v", got)
	}
	// 不信任测试 CA 的客户端必须失败（证明证书校验是真的）。
	bad := &http.Client{Transport: &http.Transport{DialContext: client.Transport.(*http.Transport).DialContext}}
	if _, err := bad.Post(doh.URL(), "application/dns-message", strings.NewReader(string(wire))); err == nil {
		t.Error("没有测试 CA 的客户端不该连得上 DoH")
	}
}

func TestHTTPTargetLogsRequests(t *testing.T) {
	h := NewHTTP(t)
	c := &http.Client{}
	if code, _ := httpGet(t, c, h.URL("127.0.0.1", "/generate_204")); code != 204 {
		t.Errorf("/generate_204 = %d", code)
	}
	if code, body := httpGet(t, c, h.URL("127.0.0.1", "/x")); code != 200 || body != "ok" {
		t.Errorf("/x = %d %q", code, body)
	}
	h.Log.MustWait(t, 2)
	es := h.Log.Entries()
	if !strings.HasSuffix(es[0].Target, "/generate_204") || !strings.HasSuffix(es[1].Target, "/x") || !strings.HasPrefix(es[0].Source, "127.0.0.1:") {
		t.Errorf("HTTP 记录 = %v", es)
	}
}

// IPv6 回环不可用时显式跳过并写明原因（不静默通过）。
func TestHTTPTargetOnIPv6Loopback(t *testing.T) {
	h, err := NewHTTPOnPort(t, "::1", 0)
	if err != nil {
		t.Skipf("本机没有可用的 IPv6 回环，跳过 v6 目标: %v", err)
	}
	if code, _ := httpGet(t, &http.Client{}, h.URL("::1", "/")); code != 200 {
		t.Errorf("v6 目标 = %d", code)
	}
}

// splitFirstRecord 把客户端发出的第一条握手记录拆成两条，模拟分片。
type splitFirstRecord struct {
	net.Conn
	done bool
}

func (c *splitFirstRecord) Write(p []byte) (int, error) {
	if c.done || len(p) < 5+10 || p[0] != 22 {
		return c.Conn.Write(p)
	}
	c.done = true
	cut := 5 + 10 // 第一段只带 10 字节握手数据
	first := append([]byte{22, p[1], p[2], 0, 0}, p[5:cut]...)
	binary.BigEndian.PutUint16(first[3:], uint16(cut-5))
	second := append([]byte{22, p[1], p[2], 0, 0}, p[cut:]...)
	binary.BigEndian.PutUint16(second[3:], uint16(len(p)-cut))
	if _, err := c.Conn.Write(first); err != nil {
		return 0, err
	}
	if _, err := c.Conn.Write(second); err != nil {
		return 0, err
	}
	return len(p), nil
}

func TestTLSTargetCountsClientHelloRecords(t *testing.T) {
	ca := NewCA(t)
	target := NewTLSRec(t, ca, "tls.example.net")
	dial := func(split bool) *http.Client {
		return &http.Client{Transport: &http.Transport{
			DisableKeepAlives: true,
			TLSClientConfig:   &tls.Config{RootCAs: ca.Pool(), ServerName: "tls.example.net"},
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				c, err := (&net.Dialer{}).DialContext(ctx, network, fmt.Sprintf("127.0.0.1:%d", target.Port))
				if err != nil || !split {
					return c, err
				}
				return &splitFirstRecord{Conn: c}, nil
			},
		}}
	}
	u := "https://tls.example.net/"
	httpGet(t, dial(false), u)
	httpGet(t, dial(true), u)
	target.Log.MustWait(t, 2)
	es := target.Log.Entries()
	var recs []string
	for _, e := range es {
		recs = append(recs, e.Detail)
		if e.Target != "tls.example.net" {
			t.Errorf("SNI = %q，期望 tls.example.net", e.Target)
		}
	}
	if len(recs) != 2 || recs[0] != "records=1" || recs[1] != "records=2" {
		t.Errorf("ClientHello 记录数 = %v，期望 [records=1 records=2]", recs)
	}
}

// 经假节点的请求出现在假节点记录里，直连的请求不出现；两台假节点各有各的记录。
func TestNodeLogsOnlyProxiedRequests(t *testing.T) {
	target := NewHTTP(t)
	nodeA := NewNode(t, "a", map[string]string{"target.example.net": "127.0.0.1"})
	nodeB := NewNode(t, "b", nil)

	viaProxy := func(n *Node) *http.Client {
		u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", n.Port))
		return &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(u), DisableKeepAlives: true}}
	}
	// 域名由节点的 Hosts 解析到回环（本机没有真实 DNS）。
	if code, body := httpGet(t, viaProxy(nodeA), fmt.Sprintf("http://target.example.net:%d/p", target.Port)); code != 200 || body != "ok" {
		t.Fatalf("经 A 的请求 = %d %q", code, body)
	}
	nodeA.Log.MustWait(t, 1)
	if e := nodeA.Log.Entries()[0]; e.Target != fmt.Sprintf("target.example.net:%d", target.Port) || e.Detail != "a" {
		t.Errorf("节点 A 记录 = %+v", e)
	}
	if nodeB.Log.Len() != 0 {
		t.Errorf("没经过 B 的请求不该出现在 B 的记录里: %v", nodeB.Log.Entries())
	}

	// 直连：目标收到了，但没有任何节点记录。
	nodeLen := nodeA.Log.Len()
	httpGet(t, &http.Client{}, target.URL("127.0.0.1", "/direct"))
	if nodeA.Log.Len() != nodeLen || nodeB.Log.Len() != 0 {
		t.Errorf("直连的请求不该出现在节点记录里: A=%v B=%v", nodeA.Log.Entries(), nodeB.Log.Entries())
	}
	if !target.Log.Has(func(e Entry) bool { return strings.HasSuffix(e.Target, "/direct") }) {
		t.Error("直连请求应该出现在目标记录里")
	}

	// 经节点的请求目标也确实收到了。
	if got := target.Log.Count(func(e Entry) bool { return strings.HasSuffix(e.Target, "/p") }); got != 1 {
		t.Errorf("目标应收到 1 次 /p，实际 %d", got)
	}
}

// SetLatency 的节点转发得更慢：经它的请求耗时明显更长，不影响别的节点。
func TestNodeLatencyIsInjected(t *testing.T) {
	target := NewHTTP(t)
	fast, slow := NewNode(t, "fast", nil), NewNode(t, "slow", nil)
	slow.SetLatency(120 * time.Millisecond)
	took := func(n *Node) time.Duration {
		u, _ := url.Parse(fmt.Sprintf("socks5://127.0.0.1:%d", n.Port))
		c := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(u), DisableKeepAlives: true}}
		start := time.Now()
		httpGet(t, c, target.URL("127.0.0.1", "/x"))
		return time.Since(start)
	}
	if f, s := took(fast), took(slow); s < 120*time.Millisecond || f >= s {
		t.Errorf("慢节点应至少多 120ms：fast=%v slow=%v", f, s)
	}
}

// 假节点的 UDP ASSOCIATE：数据报经节点转到目标，应答经节点包回来；每个目标记一条 socks-udp；
// 域名按 Hosts 映射；控制连接关闭后关联结束。
func TestNodeRelaysUDPAssociate(t *testing.T) {
	// 本地 UDP 回声目标
	echo, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = echo.Close() })
	go func() {
		buf := make([]byte, 2048)
		for {
			n, from, err := echo.ReadFrom(buf)
			if err != nil {
				return
			}
			_, _ = echo.WriteTo(append([]byte("echo:"), buf[:n]...), from)
		}
	}()
	echoPort := echo.LocalAddr().(*net.UDPAddr).Port

	node := NewNode(t, "n", map[string]string{"udp.example.net": "127.0.0.1"})
	ctl, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", node.Port))
	if err != nil {
		t.Fatal(err)
	}
	defer ctl.Close()
	_ = ctl.SetDeadline(time.Now().Add(30 * time.Second)) // 失败兜底
	if _, err := ctl.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(ctl, make([]byte, 2)); err != nil {
		t.Fatal(err)
	}
	if _, err := ctl.Write([]byte{5, 3, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		t.Fatal(err)
	}
	rep := make([]byte, 10)
	if _, err := io.ReadFull(ctl, rep); err != nil || rep[1] != 0 {
		t.Fatalf("UDP ASSOCIATE 应答 = %v (%v)", rep, err)
	}
	relay := &net.UDPAddr{IP: net.IP(rep[4:8]), Port: int(binary.BigEndian.Uint16(rep[8:10]))}

	cli, err := net.DialUDP("udp", nil, relay)
	if err != nil {
		t.Fatal(err)
	}
	defer cli.Close()
	_ = cli.SetDeadline(time.Now().Add(30 * time.Second))
	host := "udp.example.net"
	pkt := append([]byte{0, 0, 0, 3, byte(len(host))}, host...)
	pkt = append(pkt, byte(echoPort>>8), byte(echoPort))
	pkt = append(pkt, "ping"...)
	if _, err := cli.Write(pkt); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 2048)
	n, err := cli.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	got, gh, gp, ok := buf[:n], "", 0, false
	if h, p, payload, k := parseUDPRequest(got); k {
		gh, gp, got, ok = h, p, payload, true
	}
	if !ok || gh != host || gp != echoPort || string(got) != "echo:ping" {
		t.Fatalf("应答 = host %q port %d payload %q ok=%v", gh, gp, got, ok)
	}
	node.Log.MustWaitMatch(t, "socks-udp 记录", func(e Entry) bool {
		return e.Kind == "socks-udp" && e.Target == fmt.Sprintf("%s:%d", host, echoPort)
	})
}
