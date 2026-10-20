package e2e

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singjson "github.com/sagernet/sing/common/json"
	"golang.org/x/crypto/curve25519"
)

// WGPeer 是假 WARP 对端：测试进程里再起的一个 sing-box 实例，带一个 WireGuard 端点监听回环 UDP 口。
// 隧道里出来的流量只允许来自隧道内地址（10.200.0.2），并全部转给 Exit 这台假节点——
// Exit 的记录就是「哪些目标是经隧道到达的」。其它来源一律拒绝。
type WGPeer struct {
	Port int   // 对端监听的 UDP 端口（回环）
	Exit *Node // 隧道出口：隧道里的每个目标都会记在它的 Log 里

	// ClientPrivateKey / ServerPublicKey 是被测配置要用的一对（base64）。
	ClientPrivateKey string
	ServerPublicKey  string

	box *box.Box
}

// TunnelClientAddress 是隧道里客户端一侧的地址（被测配置的 local-address-ipv4 要写它）。
const TunnelClientAddress = "10.200.0.2"

// NewWGPeer 起假对端，测试结束自动关闭。exit 是隧道出口节点（需配好 Hosts，把隧道内的假目标地址映射到回环）。
func NewWGPeer(t testing.TB, exit *Node) *WGPeer {
	t.Helper()
	clientPriv, clientPub := keyPair(t)
	serverPriv, serverPub := keyPair(t)
	port := freeUDPPort(t)

	cfg := map[string]any{
		"log": map[string]any{"level": "error"},
		"endpoints": []any{map[string]any{
			"type": "wireguard", "tag": "wg-peer",
			"address":     []any{"10.200.0.1/24"},
			"private_key": serverPriv,
			"listen_port": port,
			"peers": []any{map[string]any{
				"public_key":  clientPub,
				"allowed_ips": []any{TunnelClientAddress + "/32"},
				"reserved":    []any{1, 2, 3},
			}},
		}},
		"outbounds": []any{
			map[string]any{"type": "socks", "tag": "exit", "server": "127.0.0.1", "server_port": exit.Port, "version": "5"},
			map[string]any{"type": "direct", "tag": "direct"},
		},
		"route": map[string]any{
			"rules": []any{
				map[string]any{"source_ip_cidr": []any{TunnelClientAddress + "/32"}, "action": "route", "outbound": "exit"},
				map[string]any{"action": "reject"},
			},
			"final": "direct",
		},
	}
	raw, err := json.Marshal(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx := include.Context(context.Background())
	opts, err := singjson.UnmarshalExtendedContext[option.Options](ctx, raw)
	if err != nil {
		t.Fatalf("假 WARP 对端的配置不合法: %v", err)
	}
	ctx, cancel := context.WithCancel(ctx)
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		cancel()
		t.Fatalf("建假 WARP 对端: %v", err)
	}
	if err := instance.Start(); err != nil {
		cancel()
		_ = instance.Close()
		t.Fatalf("启动假 WARP 对端: %v", err)
	}
	t.Cleanup(func() { _ = instance.Close(); cancel() })
	return &WGPeer{Port: port, Exit: exit, ClientPrivateKey: clientPriv, ServerPublicKey: serverPub, box: instance}
}

// ClientConfig 返回被测配置的 warp.wireguard-config（GenerateWarpConfig 产出里 config 那一段）。
func (p *WGPeer) ClientConfig() string {
	raw, _ := json.Marshal(map[string]string{
		"private-key":        p.ClientPrivateKey,
		"local-address-ipv4": TunnelClientAddress,
		"local-address-ipv6": "",
		"peer-public-key":    p.ServerPublicKey,
		"client-id":          "AQID", // reserved = [1,2,3]，与对端 peers[].reserved 一致
	})
	return string(raw)
}

func keyPair(t testing.TB) (priv, pub string) {
	t.Helper()
	var k [32]byte
	if _, err := rand.Read(k[:]); err != nil {
		t.Fatal(err)
	}
	k[0] &= 248
	k[31] &= 127
	k[31] |= 64
	p, err := curve25519.X25519(k[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return base64.StdEncoding.EncodeToString(k[:]), base64.StdEncoding.EncodeToString(p)
}

func freeUDPPort(t testing.TB) int {
	t.Helper()
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()
	return pc.LocalAddr().(*net.UDPAddr).Port
}

func (p *WGPeer) String() string { return fmt.Sprintf("wg-peer@127.0.0.1:%d", p.Port) }
