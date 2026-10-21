package subscription

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// ---- Clash relay 分组不得影响解析产物 ----

const clashTwoProxies = `proxies:
  - {name: a, type: ss, server: 192.0.2.1, port: 8388, cipher: aes-128-gcm, password: p}
  - {name: b, type: ss, server: 192.0.2.2, port: 8388, cipher: aes-128-gcm, password: p}
`

func TestClashRelayGroupsDoNotChangeOutput(t *testing.T) {
	base, _ := mustParse(t, []byte(clashTwoProxies))
	if len(base.Outbounds) != 2 {
		t.Fatalf("基线应有 2 个节点: %v", tags(base.Outbounds))
	}
	groups := []string{
		"proxy-groups:\n  - {name: chain, type: relay, proxies: [a, b]}\n",
		"proxy-groups:\n  - {name: chain, type: relay, proxies: [b, a]}\n  - {name: chain2, type: relay, proxies: [a, b]}\n  - {name: pick, type: select, proxies: [chain, a, b]}\n",
	}
	for _, g := range groups {
		got, _ := mustParse(t, []byte(clashTwoProxies+g))
		if !reflect.DeepEqual(got, base) {
			t.Errorf("加了 relay 分组后产物变了:\n got %v\nbase %v", got.Outbounds, base.Outbounds)
		}
	}
}

// ---- JSON 节点校验 ----

func TestJSONBrokenNodesAreSkippedValidOnesKept(t *testing.T) {
	in := `{"outbounds":[
	  {"type":"shadowsocks","tag":"good","server":"192.0.2.1","server_port":8388,"method":"aes-128-gcm","password":"p","x_custom":{"keep":true}},
	  {},
	  {"type":"shadowsocks","tag":"no-port","server":"192.0.2.2","method":"aes-128-gcm","password":"p"},
	  {"type":"shadowsocks","tag":"port-zero","server":"192.0.2.3","server_port":0,"method":"aes-128-gcm","password":"p"},
	  {"type":"shadowsocks","tag":"port-big","server":"192.0.2.3","server_port":70000,"method":"aes-128-gcm","password":"p"},
	  {"type":"shadowsocks","tag":"port-frac","server":"192.0.2.3","server_port":8.5,"method":"aes-128-gcm","password":"p"},
	  {"type":"vmess","tag":"no-uuid","server":"192.0.2.4","server_port":443},
	  {"type":"trojan","tag":"no-server","server_port":443,"password":"p"},
	  {"type":7,"tag":"bad-type"},
	  {"type":"trojan","tag":123,"server":"192.0.2.5","server_port":443,"password":"p"},
	  {"type":"trojan","tag":"trojan-hop","server":"192.0.2.6","server_ports":["20000:30000"],"password":"p"},
	  {"type":"hysteria2","tag":"hop","server":"192.0.2.7","server_ports":["20000:30000","40000:"],"password":"p"},
	  {"type":"hysteria2","tag":"hop-single-string","server":"192.0.2.7","server_ports":"20000:30000","password":"p"},
	  {"type":"hysteria2","tag":"hop-bad-range","server":"192.0.2.7","server_ports":["30000:20000"],"password":"p"},
	  {"type":"hysteria2","tag":"hop-no-colon","server":"192.0.2.7","server_ports":["20000"],"password":"p"},
	  {"type":"hysteria2","tag":"hop-zero","server":"192.0.2.7","server_ports":["0:10"],"password":"p"},
	  {"type":"hysteria2","tag":"hop-big","server":"192.0.2.7","server_ports":["1:70000"],"password":"p"},
	  {"type":"hysteria2","tag":"hop-empty","server":"192.0.2.7","server_ports":[],"password":"p"},
	  {"type":"hysteria2","tag":"hop-nonstring","server":"192.0.2.7","server_ports":[20000],"password":"p"},
	  {"type":"tuic","tag":"tuic-hop","server":"192.0.2.8","server_ports":["20000:30000"],"uuid":"u"}
	]}`
	p, w := mustParse(t, []byte(in))
	if got := strings.Join(tags(p.Outbounds), ","); got != "good,hop,hop-single-string" {
		t.Fatalf("保留的节点 = %s，期望 good,hop,hop-single-string", got)
	}
	if w.Count("node-skipped:") != 17 {
		t.Errorf("node-skipped 警告 = %d，期望 17: %v", w.Count("node-skipped:"), w)
	}
	for _, proto := range []string{"trojan", "tuic"} {
		if !strings.Contains(strings.Join(w, "\n"), "server_ports is not supported by "+proto) {
			t.Errorf("%s 不支持端口跳跃，带 server_ports 的节点应被跳过: %v", proto, w)
		}
	}
	if !reflect.DeepEqual(find(p.Outbounds, "good")["x_custom"], map[string]any{"keep": true}) {
		t.Errorf("未知但合法的字段应原样保留: %v", find(p.Outbounds, "good"))
	}
}

// 端口跳跃未启用（null / 空列表）等同没带 server_ports：回落到 server_port，节点不能被丢掉；
// 只有非空合法列表才能代替缺失的 server_port。
func TestJSONEmptyServerPortsFallsBackToServerPort(t *testing.T) {
	in := `{"outbounds":[
	  {"type":"hysteria2","tag":"hy2-empty","server":"192.0.2.1","server_port":443,"server_ports":[],"password":"p"},
	  {"type":"hysteria2","tag":"hy2-null","server":"192.0.2.2","server_port":443,"server_ports":null,"password":"p"},
	  {"type":"hysteria","tag":"hy1-empty","server":"192.0.2.3","server_port":443,"server_ports":[],"auth_str":"p"},
	  {"type":"hysteria2","tag":"empty-no-port","server":"192.0.2.4","server_ports":[],"password":"p"},
	  {"type":"hysteria2","tag":"null-no-port","server":"192.0.2.5","server_ports":null,"password":"p"},
	  {"type":"hysteria2","tag":"hop-only","server":"192.0.2.6","server_ports":["20000:30000"],"password":"p"},
	  {"type":"trojan","tag":"trojan-empty","server":"192.0.2.7","server_port":443,"server_ports":[],"password":"p"}
	]}`
	p, w := mustParse(t, []byte(in))
	if got := strings.Join(tags(p.Outbounds), ","); got != "hy2-empty,hy2-null,hy1-empty,hop-only" {
		t.Fatalf("保留的节点 = %s（警告 %v）", got, w)
	}
	for _, idx := range []string{"outbounds[3]: missing server_port", "outbounds[4]: missing server_port"} {
		if !strings.Contains(strings.Join(w, "\n"), idx) {
			t.Errorf("没有 server_port 又没启用跳跃的节点应被跳过（%s）: %v", idx, w)
		}
	}
}

func TestJSONAllNodesBrokenIsNoOutbounds(t *testing.T) {
	for _, in := range []string{
		`[{}]`,
		`{"outbounds":[{"type":"shadowsocks","tag":"x"}]}`,
		`{"type":"vless","tag":"x","server":"","server_port":443,"uuid":"u"}`,
		`{"endpoints":[{"type":"wireguard","tag":"w","private_key":"k","peers":[]}]}`,
	} {
		_, _, err := Parse([]byte(in))
		wantCode(t, err, CodeNoOutbounds)
	}
}

// ---- 资源上限 ----

func TestInputOverLimitIsRejected(t *testing.T) {
	big := make([]byte, MaxInputBytes+1)
	for i := range big {
		big[i] = ' '
	}
	_, _, err := Parse(big)
	wantCode(t, err, CodeLimitExceeded)

	dir := t.TempDir()
	in, out := filepath.Join(dir, "in"), filepath.Join(dir, "out.json")
	f, err := os.Create(in)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(MaxInputBytes + 1); err != nil { // 稀疏文件：不真写 16 MB
		t.Fatal(err)
	}
	f.Close()
	wantCode(t, ParseFile(out, in, false), CodeLimitExceeded)
	if _, statErr := os.Stat(out); statErr == nil {
		t.Error("超限时不该落盘")
	}
}

func TestDeepNestingIsRejected(t *testing.T) {
	deepJSON := strings.Repeat("[", MaxNestingDepth+5) + strings.Repeat("]", MaxNestingDepth+5)
	_, _, err := Parse([]byte(deepJSON))
	wantCode(t, err, CodeLimitExceeded)

	// 字符串里的括号不算深度
	ok := `{"outbounds":[{"type":"shadowsocks","tag":"` + strings.Repeat("[", 500) + `","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"}]}`
	if _, _, err := Parse([]byte(ok)); err != nil {
		t.Errorf("字符串里的括号不该触发深度限制: %v", err)
	}

	deepYAML := "proxies: " + strings.Repeat("[", MaxNestingDepth+5) + strings.Repeat("]", MaxNestingDepth+5) + "\n"
	_, _, err = Parse([]byte(deepYAML))
	wantCode(t, err, CodeLimitExceeded)
}

func TestYAMLAliasBombIsRejected(t *testing.T) {
	var b strings.Builder
	b.WriteString("a0: &a0 [x, x, x, x, x, x, x, x, x, x]\n")
	for i := 1; i <= 9; i++ {
		fmt.Fprintf(&b, "a%d: &a%d [%s]\n", i, i, strings.TrimSuffix(strings.Repeat(fmt.Sprintf("*a%d, ", i-1), 10), ", "))
	}
	b.WriteString("proxies:\n  - {name: a, type: ss, server: 192.0.2.1, port: 8388, cipher: aes-128-gcm, password: p}\n")
	_, _, err := Parse([]byte(b.String()))
	wantCode(t, err, CodeLimitExceeded)

	// 普通的锚点 / 别名复用不受影响（clash-anchors.yaml 夹具）。
	mustParse(t, fixture(t, "clash-anchors.yaml"))
}

func TestNodeCountOverLimitIsRejected(t *testing.T) {
	var js strings.Builder
	js.WriteString(`{"outbounds":[`)
	for i := 0; i <= MaxNodes; i++ {
		if i > 0 {
			js.WriteString(",")
		}
		fmt.Fprintf(&js, `{"type":"shadowsocks","tag":"n%d","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"}`, i)
	}
	js.WriteString(`]}`)
	_, _, err := Parse([]byte(js.String()))
	wantCode(t, err, CodeLimitExceeded)

	var yml strings.Builder
	yml.WriteString("proxies:\n")
	for i := 0; i <= MaxNodes; i++ {
		fmt.Fprintf(&yml, "  - {name: n%d, type: ss, server: 192.0.2.1, port: 1, cipher: aes-128-gcm, password: p}\n", i)
	}
	_, _, err = Parse([]byte(yml.String()))
	wantCode(t, err, CodeLimitExceeded)

	links := strings.Repeat("ss://bad\n", MaxNodes+1)
	_, _, err = Parse([]byte(links))
	wantCode(t, err, CodeLimitExceeded)
}

func TestOutputOverLimitIsRejected(t *testing.T) {
	old := maxOutputBytes
	maxOutputBytes = 64
	defer func() { maxOutputBytes = old }()
	dir := t.TempDir()
	in, out := filepath.Join(dir, "in.json"), filepath.Join(dir, "out.json")
	if err := os.WriteFile(in, fixture(t, "singbox-full.json"), 0o644); err != nil {
		t.Fatal(err)
	}
	wantCode(t, ParseFile(out, in, false), CodeLimitExceeded)
	if _, err := os.Stat(out); err == nil {
		t.Error("输出超限时不该落盘")
	}
}

// 混合列表里一条 vmess 的 tls 值未知：这一条被跳过并警告，其余照常解析；单独一条时报 uri-invalid。
func TestVMessUnknownTLSInMixedList(t *testing.T) {
	good := "ss://" + base64NoPad("aes-128-gcm:p") + "@192.0.2.1:8388#good"
	bad := "vmess://" + base64Std(`{"ps":"bad","add":"a.example.net","port":"443","id":"11111111-1111-4111-8111-111111111111","tls":"xtls"}`)
	p, w := mustParse(t, []byte(good+"\n"+bad+"\n"))
	if got := strings.Join(tags(p.Outbounds), ","); got != "good" {
		t.Fatalf("节点 = %s，期望只剩 good", got)
	}
	if w.Count("node-skipped:") != 1 || !strings.Contains(strings.Join(w, "\n"), "unsupported tls value") {
		t.Errorf("warnings = %v", w)
	}
	_, _, err := Parse([]byte(bad))
	wantCode(t, err, CodeURIInvalid)
}

func base64NoPad(s string) string { return base64.RawURLEncoding.EncodeToString([]byte(s)) }
func base64Std(s string) string   { return base64.StdEncoding.EncodeToString([]byte(s)) }

// 预算按原始条目数计，先于校验与过滤：被过滤掉的条目也算数，不能靠「全是废条目」绕过上限，
// 也不能先产生海量警告再成功。
func TestJSONEntryBudgetCountsRawEntries(t *testing.T) {
	good := `{"type":"shadowsocks","tag":"good","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"}`
	repeat := func(entry string, n int) string { return strings.TrimSuffix(strings.Repeat(entry+",", n), ",") }
	cases := map[string]string{
		"混合：一个有效节点 + 超限的 {}":               `{"outbounds":[` + good + `,` + repeat("{}", MaxNodes) + `]}`,
		"全坏：超限的 {}（不能先于预算返回 no-outbounds）": `{"outbounds":[` + repeat("{}", MaxNodes+1) + `]}`,
		"非对象条目超限":                          `{"outbounds":[` + repeat("7", MaxNodes+1) + `]}`,
		"顶层数组":                             `[` + good + `,` + repeat("null", MaxNodes) + `]`,
		"出站与端点合计超限":                        `{"outbounds":[` + repeat("{}", MaxNodes) + `],"endpoints":[{}]}`,
	}
	for name, in := range cases {
		t.Run(name, func(t *testing.T) {
			_, warnings, err := Parse([]byte(in))
			wantCode(t, err, CodeLimitExceeded)
			if len(warnings) != 0 {
				t.Errorf("超限应在逐条校验之前拒绝，实际已产生 %d 条警告", len(warnings))
			}
		})
	}
	// 恰好等于上限不算超限（有效节点照常解析）。
	in := `{"outbounds":[` + good + `,` + repeat("{}", MaxNodes-1) + `]}`
	if p, _, err := Parse([]byte(in)); err != nil || len(p.Outbounds) != 1 {
		t.Fatalf("恰好 %d 条应放行并只保留有效节点: %v %v", MaxNodes, p.Outbounds, err)
	}
}
