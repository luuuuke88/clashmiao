package e2e

import (
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singjson "github.com/sagernet/sing/common/json"
)

// ProtoServer 是假代理服务端：测试进程里再起的一个 sing-box 实例，在回环上监听某个真实代理协议的入站，
// 把进来的连接全部转给 Exit 这台假节点。Exit 的记录就是「哪些目标是经这个协议的服务端到达的」。
// 被测的客户端配置走真协议栈（握手、加密、QUIC）连它，而不是 SOCKS 替身。
type ProtoServer struct {
	Type string // shadowsocks / vmess / trojan / hysteria2 / tuic
	Port int    // 入站端口（TCP 或 UDP，视协议而定）
	Exit *Node

	// 客户端凭据（各协议只用其中一部分）。
	UUID     string
	Password string
	Method   string // 仅 shadowsocks
	SNI      string // 有 TLS 的协议：证书里的名字

	box *box.Box
}

// 固定的测试凭据：只在本机回环上有效，不对应任何真实服务。
const (
	protoUUID     = "7c1d2f3a-4b5c-4d6e-8f70-123456789abc"
	protoPassword = "proto-test-password"
	protoSNI      = "proto.example.net"
)

// NewProtoServer 起一个 typ 协议的假服务端，测试结束自动关闭。TLS 类协议用 ca 签发证书。
func NewProtoServer(t testing.TB, typ string, ca *CA, exit *Node) *ProtoServer {
	t.Helper()
	s := &ProtoServer{Type: typ, Exit: exit, UUID: protoUUID, Password: protoPassword, SNI: protoSNI}

	in := map[string]any{"type": typ, "tag": "proto-in", "listen": "127.0.0.1"}
	udp := false
	switch typ {
	case "shadowsocks":
		s.Method = "aes-128-gcm"
		in["method"] = s.Method
		in["password"] = s.Password
	case "vmess":
		in["users"] = []any{map[string]any{"uuid": s.UUID, "alterId": 0}}
	case "trojan":
		in["users"] = []any{map[string]any{"password": s.Password}}
		in["tls"] = s.serverTLS(t, ca, false)
	case "hysteria2":
		udp = true
		in["users"] = []any{map[string]any{"password": s.Password}}
		in["tls"] = s.serverTLS(t, ca, true)
	case "tuic":
		udp = true
		in["users"] = []any{map[string]any{"uuid": s.UUID, "password": s.Password}}
		in["tls"] = s.serverTLS(t, ca, true)
	default:
		t.Fatalf("NewProtoServer: 不支持的协议 %q", typ)
	}
	if udp {
		s.Port = freeUDPPort(t)
	} else {
		s.Port = freeTCPPort(t)
	}
	in["listen_port"] = s.Port

	cfg := map[string]any{
		"log":      map[string]any{"level": "error"},
		"inbounds": []any{in},
		"outbounds": []any{
			map[string]any{"type": "socks", "tag": "exit", "server": "127.0.0.1", "server_port": exit.Port, "version": "5"},
		},
		"route": map[string]any{"final": "exit"},
	}
	raw, err := json.Marshal(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx := include.Context(context.Background())
	opts, err := singjson.UnmarshalExtendedContext[option.Options](ctx, raw)
	if err != nil {
		t.Fatalf("假 %s 服务端的配置不合法: %v", typ, err)
	}
	ctx, cancel := context.WithCancel(ctx)
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		cancel()
		t.Fatalf("建假 %s 服务端: %v", typ, err)
	}
	if err := instance.Start(); err != nil {
		cancel()
		_ = instance.Close()
		t.Fatalf("启动假 %s 服务端: %v", typ, err)
	}
	s.box = instance
	t.Cleanup(func() { _ = instance.Close(); cancel() })
	return s
}

func (s *ProtoServer) serverTLS(t testing.TB, ca *CA, h3 bool) map[string]any {
	cert := ca.Issue(t, s.SNI, "127.0.0.1")
	keyDER, err := x509.MarshalECPrivateKey(cert.PrivateKey.(*ecdsa.PrivateKey))
	if err != nil {
		t.Fatal(err)
	}
	tls := map[string]any{
		"enabled":     true,
		"server_name": s.SNI,
		"certificate": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Certificate[0]})),
		"key":         string(pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})),
	}
	if h3 {
		tls["alpn"] = []any{"h3"}
	}
	return tls
}

func freeTCPPort(t testing.TB) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port
}

func (s *ProtoServer) String() string { return fmt.Sprintf("%s-server@127.0.0.1:%d", s.Type, s.Port) }
