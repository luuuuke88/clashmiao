//go:build !race

package gate

import (
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

// 混合订阅：有效节点（含只带 server_ports 的 hysteria2）与各种必然无效的节点放在一起。
// 解析保留下来的产物必须整体通过配置闸门并能真启动——否则「单节点隔离」只是把坏节点留到了后面。
func TestMixedJSONRetainedNodesPassConfigGate(t *testing.T) {
	in := `{"outbounds":[
	  {"type":"shadowsocks","tag":"ss-ok","server":"192.0.2.1","server_port":8388,"method":"aes-128-gcm","password":"p"},
	  {"type":"hysteria2","tag":"hy2-hop","server":"192.0.2.2","server_ports":["20000:30000","40000:"],"password":"p","tls":{"enabled":true,"server_name":"h.example.net"}},
	  {"type":"hysteria2","tag":"hy2-port","server":"192.0.2.3","server_port":443,"password":"p","tls":{"enabled":true,"server_name":"h.example.net"}},
	  {"type":"trojan","tag":"trojan-hop","server":"192.0.2.4","server_ports":["20000:30000"],"password":"p"},
	  {"type":"tuic","tag":"tuic-hop","server":"192.0.2.5","server_ports":["20000:30000"],"uuid":"11111111-2222-4333-8444-555555555555"},
	  {"type":"hysteria2","tag":"hop-bad","server":"192.0.2.6","server_ports":["30000:20000"],"password":"p"},
	  {"type":"shadowsocks","tag":"no-port","server":"192.0.2.7","method":"aes-128-gcm","password":"p"},
	  {}
	]}`
	p, w, err := subscription.Parse([]byte(in))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	var kept []string
	for _, o := range p.Outbounds {
		kept = append(kept, o["tag"].(string))
	}
	if got := strings.Join(kept, ","); got != "ss-ok,hy2-hop,hy2-port" {
		t.Fatalf("保留的节点 = %s，期望 ss-ok,hy2-hop,hy2-port（警告 %v）", got, w)
	}

	o := Option("O1")
	o.EnableTun = false
	raw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if vs := CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
		t.Errorf("不变量违规: %v", vs)
	}
	adapted, _, err := HostAdapt(raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if err := CheckConfig(adapted); err != nil {
		t.Fatalf("保留下来的混合产物没有通过配置闸门: %v", err)
	}
	eng, _ := NewEngine(t)
	if err := eng.Start(string(adapted)); err != nil {
		t.Fatalf("Start: %v", err)
	}
	t.Cleanup(func() { _ = eng.Stop() })
}
