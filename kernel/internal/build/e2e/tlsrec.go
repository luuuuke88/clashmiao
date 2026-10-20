package e2e

import (
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"net"
	"net/http"
	"sync"
	"testing"
)

// TLSRecTarget 是 HTTPS 目标，并记录每个连接上 ClientHello 被拆成了几条 TLS 记录
// （分片开启时应 >= 2，关闭时恰好 1）。记录的 Detail 是 "records=N"，Target 是 SNI。
type TLSRecTarget struct {
	Port int
	Log  *Log
	CA   *CA
}

// NewTLSRec 起一个由 ca 签发证书的 HTTPS 目标（证书含 name 与 127.0.0.1）。
func NewTLSRec(t testing.TB, ca *CA, name string) *TLSRecTarget {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	target := &TLSRecTarget{Log: NewLog("tls"), CA: ca, Port: ln.Addr().(*net.TCPAddr).Port}
	tlsLn := tls.NewListener(&recListener{Listener: ln, log: target.Log}, &tls.Config{
		Certificates: []tls.Certificate{ca.Issue(t, name, "127.0.0.1")},
		NextProtos:   []string{"http/1.1"},
	})
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("ok")) })}
	go func() { _ = srv.Serve(tlsLn) }()
	t.Cleanup(func() { _ = srv.Close() })
	return target
}

type recListener struct {
	net.Listener
	log *Log
}

func (l *recListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &recConn{Conn: c, log: l.log}, nil
}

// recConn 旁路累积第一段入站字节，解析 TLS 记录层，数出装下 ClientHello 握手消息用了几条记录。
type recConn struct {
	net.Conn
	log *Log

	mu   sync.Mutex
	buf  []byte
	done bool
}

func (c *recConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	if n > 0 {
		c.mu.Lock()
		if !c.done {
			c.buf = append(c.buf, p[:n]...)
			c.scan()
		}
		c.mu.Unlock()
	}
	return n, err
}

func (c *recConn) scan() {
	records, handshake, need := 0, 0, -1
	var first []byte
	for pos := 0; pos+5 <= len(c.buf); {
		typ := c.buf[pos]
		l := int(binary.BigEndian.Uint16(c.buf[pos+3:]))
		if pos+5+l > len(c.buf) {
			return // 记录还没收齐
		}
		if typ != 22 {
			c.done = true
			return
		}
		records++
		payload := c.buf[pos+5 : pos+5+l]
		handshake += len(payload)
		if first == nil {
			first = payload
		}
		if need < 0 && handshake >= 4 {
			need = 4 + int(first[1])<<16 + int(first[2])<<8 + int(first[3])
		}
		if need >= 0 && handshake >= need {
			c.done = true
			c.log.Add(Entry{Kind: "tls", Source: c.RemoteAddr().String(), Target: sniOf(c.buf), Detail: fmt.Sprintf("records=%d", records)})
			return
		}
		pos += 5 + l
	}
}

// sniOf 尽力从（可能被分片的）ClientHello 里取 SNI；取不到返回空串。
func sniOf(buf []byte) string {
	var hs []byte
	for pos := 0; pos+5 <= len(buf); {
		l := int(binary.BigEndian.Uint16(buf[pos+3:]))
		if pos+5+l > len(buf) || buf[pos] != 22 {
			break
		}
		hs = append(hs, buf[pos+5:pos+5+l]...)
		pos += 5 + l
	}
	// handshake header(4) + version(2) + random(32) + session id + cipher suites + compression + extensions
	if len(hs) < 4+2+32+1 {
		return ""
	}
	p := 4 + 2 + 32
	p += 1 + int(hs[p])
	if p+2 > len(hs) {
		return ""
	}
	p += 2 + int(binary.BigEndian.Uint16(hs[p:]))
	if p+1 > len(hs) {
		return ""
	}
	p += 1 + int(hs[p])
	if p+2 > len(hs) {
		return ""
	}
	end := p + 2 + int(binary.BigEndian.Uint16(hs[p:]))
	p += 2
	for p+4 <= end && p+4 <= len(hs) {
		typ := binary.BigEndian.Uint16(hs[p:])
		l := int(binary.BigEndian.Uint16(hs[p+2:]))
		p += 4
		if typ == 0 && p+5 <= len(hs) { // server_name
			nameLen := int(binary.BigEndian.Uint16(hs[p+3:]))
			if p+5+nameLen <= len(hs) {
				return string(hs[p+5 : p+5+nameLen])
			}
			return ""
		}
		p += l
	}
	return ""
}
