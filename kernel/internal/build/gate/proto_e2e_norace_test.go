//go:build !race

// 各代理协议的真流量测试：分享链接 → Parse → Build → 适配 → 真启动，经 mixed-in 发请求，
// 由测试进程里的真协议服务端（e2e.ProtoServer）接住，再转给记录用的假出口。
// 覆盖 shadowsocks / vmess / trojan / hysteria2 / tuic（VLESS、WireGuard 在别处有各自的端到端测试）。
// 放在 !race 文件里：配置里的 urltest 组在 -race 下会撞上游的数据竞争（见 tools/kernel/gotest.sh）。

package gate

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

// protoShareLink 拼出指向该服务端的分享链接。TLS 类协议用 insecure（证书由测试 CA 签发，客户端不带这个 CA）。
func protoShareLink(t *testing.T, s *e2e.ProtoServer) string {
	t.Helper()
	switch s.Type {
	case "shadowsocks":
		userinfo := base64.RawURLEncoding.EncodeToString([]byte(s.Method + ":" + s.Password))
		return fmt.Sprintf("ss://%s@127.0.0.1:%d#proto", userinfo, s.Port)
	case "vmess":
		j, _ := json.Marshal(map[string]any{"v": "2", "ps": "proto", "add": "127.0.0.1", "port": s.Port, "id": s.UUID,
			"aid": 0, "scy": "auto", "net": "tcp", "type": "none", "tls": ""})
		return "vmess://" + base64.StdEncoding.EncodeToString(j)
	case "trojan":
		return fmt.Sprintf("trojan://%s@127.0.0.1:%d?sni=%s&allowInsecure=1#proto", s.Password, s.Port, s.SNI)
	case "hysteria2":
		return fmt.Sprintf("hysteria2://%s@127.0.0.1:%d?sni=%s&insecure=1#proto", s.Password, s.Port, s.SNI)
	case "tuic":
		return fmt.Sprintf("tuic://%s:%s@127.0.0.1:%d?sni=%s&allow_insecure=1&alpn=h3&congestion_control=bbr&udp_relay_mode=native#proto",
			s.UUID, s.Password, s.Port, s.SNI)
	}
	t.Fatalf("没有 %s 的分享链接模板", s.Type)
	return ""
}

func TestProtocolsCarryRealTraffic(t *testing.T) {
	ca := e2e.NewCA(t)
	for _, typ := range []string{"shadowsocks", "vmess", "trojan", "hysteria2", "tuic"} {
		t.Run(typ, func(t *testing.T) {
			const fakeHost = "origin.proto.test" // 本机解析不了；只有服务端的假出口能把它映射到回环
			exit := e2e.NewNode(t, "exit-"+typ, map[string]string{fakeHost: "127.0.0.1"})
			srv := e2e.NewProtoServer(t, typ, ca, exit)
			target := e2e.NewHTTP(t)

			p, _, err := subscription.Parse([]byte(protoShareLink(t, srv)))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			if len(p.Outbounds) != 1 || p.Outbounds[0]["type"] != typ {
				t.Fatalf("分享链接应转成一个 %s 节点: %+v", typ, p.Outbounds)
			}
			o := Option("O1")
			o.EnableTun = false
			raw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			adapted, ap, err := HostAdapt(raw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			eng, _ := NewEngine(t)
			if err := eng.Start(string(adapted)); err != nil {
				t.Fatalf("Start: %v", err)
			}
			t.Cleanup(func() { _ = eng.Stop() })
			FirstGroups(t, eng)
			if err := eng.SelectOutbound("select", "proto"); err != nil {
				t.Fatalf("SelectOutbound: %v", err)
			}

			url := target.URL(fakeHost, "/hello")
			status, body := Get(t, ProxyClient(ap.MixedPort), url)
			if status != 200 || body != "ok" {
				t.Fatalf("经 %s 的请求 = %d %q", typ, status, body)
			}
			want := fmt.Sprintf("%s:%d", fakeHost, target.Port)
			if got := exit.Log.Count(func(e e2e.Entry) bool { return e.Target == want }); got != 1 {
				t.Errorf("服务端的出口应恰好记到一条 %s，实际 %d: %v", want, got, exit.Log.Entries())
			}
			if target.Log.Len() != 1 {
				t.Errorf("目标应恰好收到一个请求: %v", target.Log.Entries())
			}
		})
	}
}
