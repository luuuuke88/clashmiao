package e2e

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

// Node 是假节点：本地 SOCKS5 上游（无认证，支持 CONNECT 与 UDP ASSOCIATE）。被测配置把它当作订阅里的一个 socks 节点；
// 每个经它转出的连接都记入 Log（Source 是来者，Target 是请求的 host:port）。
// 可以起多个，各有各的记录。
type Node struct {
	Name string
	Port int
	Log  *Log
	// Hosts 把请求里的域名映射成回环 IP（本机没有真实 DNS）；没有映射的域名按系统解析。
	Hosts map[string]string

	ln      net.Listener
	mu      sync.Mutex
	conns   map[io.Closer]struct{}
	latency time.Duration
}

// SetLatency 让这台节点在建立上游连接前多等 d：人为注入的链路延迟（不是用来等某件事发生），
// 用来造「这台比那台慢」的测速差异。0 表示不加。
func (n *Node) SetLatency(d time.Duration) {
	n.mu.Lock()
	n.latency = d
	n.mu.Unlock()
}

// NewNode 起一个假节点，测试结束自动关闭。
func NewNode(t testing.TB, name string, hosts map[string]string) *Node {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	n := &Node{Name: name, Port: ln.Addr().(*net.TCPAddr).Port, Log: NewLog("node " + name), Hosts: hosts, ln: ln, conns: map[io.Closer]struct{}{}}
	go n.serve()
	t.Cleanup(n.Close)
	return n
}

// Close 关闭监听与所有在途连接。
func (n *Node) Close() {
	_ = n.ln.Close()
	n.mu.Lock()
	for c := range n.conns {
		_ = c.Close()
	}
	n.mu.Unlock()
}

// Outbound 是订阅里这个节点的 sing-box 出站定义。
func (n *Node) Outbound(tag string) map[string]any {
	return map[string]any{"type": "socks", "tag": tag, "server": "127.0.0.1", "server_port": n.Port, "version": "5"}
}

func (n *Node) track(c io.Closer) {
	n.mu.Lock()
	n.conns[c] = struct{}{}
	n.mu.Unlock()
}

func (n *Node) untrack(c io.Closer) {
	n.mu.Lock()
	delete(n.conns, c)
	n.mu.Unlock()
}

func (n *Node) serve() {
	for {
		c, err := n.ln.Accept()
		if err != nil {
			return
		}
		n.track(c)
		go n.handle(c)
	}
}

func (n *Node) handle(c net.Conn) {
	defer func() { n.untrack(c); _ = c.Close() }()
	// 问候：VER NMETHODS METHODS...
	head := make([]byte, 2)
	if _, err := io.ReadFull(c, head); err != nil || head[0] != 5 {
		return
	}
	if _, err := io.CopyN(io.Discard, c, int64(head[1])); err != nil {
		return
	}
	if _, err := c.Write([]byte{5, 0}); err != nil {
		return
	}
	// 请求：VER CMD RSV ATYP ADDR PORT
	req := make([]byte, 4)
	if _, err := io.ReadFull(c, req); err != nil || req[0] != 5 {
		return
	}
	var host string
	switch req[3] {
	case 1:
		b := make([]byte, 4)
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = net.IP(b).String()
	case 4:
		b := make([]byte, 16)
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = net.IP(b).String()
	case 3:
		l := make([]byte, 1)
		if _, err := io.ReadFull(c, l); err != nil {
			return
		}
		b := make([]byte, l[0])
		if _, err := io.ReadFull(c, b); err != nil {
			return
		}
		host = string(b)
	default:
		return
	}
	pb := make([]byte, 2)
	if _, err := io.ReadFull(c, pb); err != nil {
		return
	}
	port := int(binary.BigEndian.Uint16(pb))
	switch req[1] {
	case 1: // CONNECT
	case 3: // UDP ASSOCIATE
		n.handleUDP(c)
		return
	default:
		_, _ = c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	target := net.JoinHostPort(host, fmt.Sprint(port))
	n.Log.Add(Entry{Kind: "socks", Source: c.RemoteAddr().String(), Target: target, Detail: n.Name})

	n.mu.Lock()
	d := n.latency
	n.mu.Unlock()
	if d > 0 {
		<-time.After(d)
	}

	dialHost := host
	if ip, ok := n.Hosts[strings.ToLower(host)]; ok {
		dialHost = ip
	}
	up, err := net.Dial("tcp", net.JoinHostPort(dialHost, fmt.Sprint(port)))
	if err != nil {
		_, _ = c.Write([]byte{5, 4, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	n.track(up)
	defer func() { n.untrack(up); _ = up.Close() }()
	if _, err := c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}
	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(up, c); done <- struct{}{} }()
	go func() { _, _ = io.Copy(c, up); done <- struct{}{} }()
	<-done
}

// handleUDP 处理 UDP ASSOCIATE：开一个回环 UDP 口，按 SOCKS5 的 UDP 封装收发数据报，
// 每个目标记一条 socks-udp 记录（Target 是请求的 host:port）。控制连接关闭时整个关联结束。
func (n *Node) handleUDP(ctl net.Conn) {
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		_, _ = ctl.Write([]byte{5, 1, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	n.track(pc)
	defer func() { n.untrack(pc); _ = pc.Close() }()
	port := pc.LocalAddr().(*net.UDPAddr).Port
	if _, err := ctl.Write([]byte{5, 0, 0, 1, 127, 0, 0, 1, byte(port >> 8), byte(port)}); err != nil {
		return
	}
	// 控制连接一断，关联结束。
	go func() { _, _ = io.Copy(io.Discard, ctl); _ = pc.Close() }()

	var (
		mu       sync.Mutex
		client   net.Addr
		upstream = map[string]net.Conn{}
	)
	defer func() {
		mu.Lock()
		for _, u := range upstream {
			_ = u.Close()
		}
		mu.Unlock()
	}()
	buf := make([]byte, 64*1024)
	for {
		nr, from, err := pc.ReadFrom(buf)
		if err != nil {
			return
		}
		mu.Lock()
		if client == nil {
			client = from
		}
		isClient := from.String() == client.String()
		mu.Unlock()
		if !isClient {
			continue
		}
		host, tport, payload, ok := parseUDPRequest(buf[:nr])
		if !ok {
			continue
		}
		target := net.JoinHostPort(host, fmt.Sprint(tport))
		n.Log.Add(Entry{Kind: "socks-udp", Source: from.String(), Target: target, Detail: n.Name})

		dialHost := host
		if ip, ok := n.Hosts[strings.ToLower(host)]; ok {
			dialHost = ip
		}
		mu.Lock()
		up := upstream[target]
		if up == nil {
			up, err = net.Dial("udp", net.JoinHostPort(dialHost, fmt.Sprint(tport)))
			if err != nil {
				mu.Unlock()
				continue
			}
			upstream[target] = up
			go func(up net.Conn, host string, tport int) {
				rb := make([]byte, 64*1024)
				for {
					m, err := up.Read(rb)
					if err != nil {
						return
					}
					mu.Lock()
					cl := client
					mu.Unlock()
					_, _ = pc.WriteTo(wrapUDPReply(host, tport, rb[:m]), cl)
				}
			}(up, host, tport)
		}
		mu.Unlock()
		_, _ = up.Write(payload)
	}
}

// parseUDPRequest 解 SOCKS5 的 UDP 封装：RSV(2) FRAG(1) ATYP ADDR PORT DATA。不支持分片。
func parseUDPRequest(b []byte) (host string, port int, payload []byte, ok bool) {
	if len(b) < 4 || b[0] != 0 || b[1] != 0 || b[2] != 0 {
		return
	}
	i := 4
	switch b[3] {
	case 1:
		if len(b) < i+4 {
			return
		}
		host = net.IP(b[i : i+4]).String()
		i += 4
	case 4:
		if len(b) < i+16 {
			return
		}
		host = net.IP(b[i : i+16]).String()
		i += 16
	case 3:
		if len(b) < i+1 || len(b) < i+1+int(b[i]) {
			return
		}
		l := int(b[i])
		host = string(b[i+1 : i+1+l])
		i += 1 + l
	default:
		return
	}
	if len(b) < i+2 {
		return
	}
	port = int(binary.BigEndian.Uint16(b[i : i+2]))
	return host, port, b[i+2:], true
}

// wrapUDPReply 把上游的应答按 SOCKS5 的 UDP 封装包回去（来源地址写成请求时的目标）。
func wrapUDPReply(host string, port int, payload []byte) []byte {
	out := []byte{0, 0, 0}
	if ip := net.ParseIP(host); ip != nil {
		if v4 := ip.To4(); v4 != nil {
			out = append(out, 1)
			out = append(out, v4...)
		} else {
			out = append(out, 4)
			out = append(out, ip.To16()...)
		}
	} else {
		out = append(out, 3, byte(len(host)))
		out = append(out, host...)
	}
	out = append(out, byte(port>>8), byte(port))
	return append(out, payload...)
}
