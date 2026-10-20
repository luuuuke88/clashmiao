package gate

import (
	"errors"
	"fmt"
	"io"
	"net"
	"testing"
	"time"

	mdns "github.com/miekg/dns"
)

// DialViaMixed 经 mixed-in（SOCKS5，无认证）CONNECT 到 host:port，返回已建立隧道的连接。
// 目标可以是任意地址：路由规则（例如 hijack-dns）可能在到达目标之前就接管这条连接。
func DialViaMixed(mixedPort int, host string, port int) (net.Conn, error) {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort), 30*time.Second)
	if err != nil {
		return nil, err
	}
	fail := func(err error) (net.Conn, error) { _ = c.Close(); return nil, err }
	_ = c.SetDeadline(time.Now().Add(30 * time.Second))
	if _, err := c.Write([]byte{5, 1, 0}); err != nil {
		return fail(err)
	}
	reply := make([]byte, 2)
	if _, err := io.ReadFull(c, reply); err != nil || reply[0] != 5 || reply[1] != 0 {
		return fail(fmt.Errorf("socks5 greeting failed: %v %v", reply, err))
	}
	req := []byte{5, 1, 0}
	if ip := net.ParseIP(host); ip != nil {
		if v4 := ip.To4(); v4 != nil {
			req = append(req, 1)
			req = append(req, v4...)
		} else {
			req = append(req, 4)
			req = append(req, ip.To16()...)
		}
	} else {
		req = append(req, 3, byte(len(host)))
		req = append(req, host...)
	}
	req = append(req, byte(port>>8), byte(port))
	if _, err := c.Write(req); err != nil {
		return fail(err)
	}
	head := make([]byte, 4)
	if _, err := io.ReadFull(c, head); err != nil {
		return fail(err)
	}
	if head[1] != 0 {
		return fail(fmt.Errorf("socks5 connect refused: code %d", head[1]))
	}
	var skip int
	switch head[3] {
	case 1:
		skip = 4 + 2
	case 4:
		skip = 16 + 2
	case 3:
		l := make([]byte, 1)
		if _, err := io.ReadFull(c, l); err != nil {
			return fail(err)
		}
		skip = int(l[0]) + 2
	default:
		return fail(errors.New("socks5: bad address type"))
	}
	if _, err := io.CopyN(io.Discard, c, int64(skip)); err != nil {
		return fail(err)
	}
	_ = c.SetDeadline(time.Time{})
	return c, nil
}

// hijackTarget 是随便一个不会真的被连上的地址（RFC 5737）：DNS 连接会被 hijack-dns 接管。
const hijackTarget = "192.0.2.53"

// QueryDNSViaMixed 经 mixed-in 发起一条 TCP DNS 查询（连到 192.0.2.53:53，被路由里的 hijack-dns 接管），
// 返回应答；这样 DNS 规则、dns-remote / dns-direct 的选择与出口都被真实走一遍。
func QueryDNSViaMixed(t testing.TB, mixedPort int, name string, qtype uint16) (*mdns.Msg, error) {
	t.Helper()
	conn, err := DialViaMixed(mixedPort, hijackTarget, 53)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(30 * time.Second)) // 失败兜底，不是等待手段
	co := &mdns.Conn{Conn: conn}
	m := new(mdns.Msg)
	m.SetQuestion(mdns.Fqdn(name), qtype)
	if err := co.WriteMsg(m); err != nil {
		return nil, err
	}
	return co.ReadMsg()
}

// FreeUDPPort 返回一个当前没人监听的 UDP 端口（用来造「不可达的自举解析器」）。
func FreeUDPPort(t testing.TB) int {
	t.Helper()
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()
	return pc.LocalAddr().(*net.UDPAddr).Port
}
