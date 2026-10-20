package e2e

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
)

// Node 是假节点：本地 SOCKS5 上游（无认证，支持 CONNECT）。被测配置把它当作订阅里的一个 socks 节点；
// 每个经它转出的连接都记入 Log（Source 是来者，Target 是请求的 host:port）。
// 可以起多个，各有各的记录。
type Node struct {
	Name string
	Port int
	Log  *Log
	// Hosts 把请求里的域名映射成回环 IP（本机没有真实 DNS）；没有映射的域名按系统解析。
	Hosts map[string]string

	ln    net.Listener
	mu    sync.Mutex
	conns map[net.Conn]struct{}
}

// NewNode 起一个假节点，测试结束自动关闭。
func NewNode(t testing.TB, name string, hosts map[string]string) *Node {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	n := &Node{Name: name, Port: ln.Addr().(*net.TCPAddr).Port, Log: NewLog("node " + name), Hosts: hosts, ln: ln, conns: map[net.Conn]struct{}{}}
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

func (n *Node) track(c net.Conn) {
	n.mu.Lock()
	n.conns[c] = struct{}{}
	n.mu.Unlock()
}

func (n *Node) untrack(c net.Conn) {
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
	if req[1] != 1 { // 只支持 CONNECT
		_, _ = c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	target := net.JoinHostPort(host, fmt.Sprint(port))
	n.Log.Add(Entry{Kind: "socks", Source: c.RemoteAddr().String(), Target: target, Detail: n.Name})

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
