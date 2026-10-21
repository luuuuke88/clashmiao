package subscription

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"
)

func fixture(t testing.TB, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", "subscriptions", name))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func mustParse(t testing.TB, in []byte) (Profile, Warnings) {
	t.Helper()
	p, w, err := Parse(in)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	return p, w
}

func tags(list []map[string]any) []string {
	var out []string
	for _, m := range list {
		out = append(out, m["tag"].(string))
	}
	return out
}

func types(list []map[string]any) []string {
	var out []string
	for _, m := range list {
		out = append(out, m["type"].(string))
	}
	return out
}

func find(list []map[string]any, tag string) map[string]any {
	for _, m := range list {
		if m["tag"] == tag {
			return m
		}
	}
	return nil
}

func wantCode(t testing.TB, err error, code string) {
	t.Helper()
	if err == nil {
		t.Fatalf("应当失败（%s）", code)
	}
	if !Is(err, code) || !strings.HasPrefix(err.Error(), code) {
		t.Fatalf("err = %v，期望码 %s", err, code)
	}
	if CodeFromMessage(err.Error()) != code {
		t.Errorf("CodeFromMessage(%q) = %q", err.Error(), CodeFromMessage(err.Error()))
	}
}

// ---- Clash ----

func TestClashProtocols(t *testing.T) {
	p, w := mustParse(t, fixture(t, "clash-protocols.yaml"))
	if got := strings.Join(types(p.Outbounds), ","); got != "shadowsocks,vmess,vless,trojan,hysteria2,tuic" {
		t.Fatalf("出站类型 = %s", got)
	}
	if len(p.Endpoints) != 1 || p.Endpoints[0]["type"] != "wireguard" || p.Endpoints[0]["tag"] != "德国 wireguard" {
		t.Fatalf("wireguard 应进 endpoints: %v", p.Endpoints)
	}
	if p.NodeCount() != 7 {
		t.Errorf("节点数 = %d，期望 7（6 出站 + 1 端点）", p.NodeCount())
	}
	// ssr 不支持：记警告，不拖垮整份订阅。
	if w.Count("node-skipped:") != 1 || !strings.Contains(strings.Join(w, "\n"), "ssr") {
		t.Errorf("warnings = %v", w)
	}
	// 分组与规则被忽略；输出里没有 inbounds / dns / route。
	for _, o := range p.Outbounds {
		if o["type"] == "selector" || o["type"] == "urltest" {
			t.Errorf("不该带 Clash 的分组: %v", o)
		}
	}
	reality := find(p.Outbounds, "日本 vless reality")
	tls, _ := reality["tls"].(map[string]any)
	re, _ := tls["reality"].(map[string]any)
	if re == nil || re["public_key"] != "ivDROKaq354cSx7DJ6wLY49DSI3S8pMXN47fhzmty4Y" || re["short_id"] != "0123abcd" || reality["flow"] != "xtls-rprx-vision" {
		t.Errorf("reality 字段: %v", reality)
	}
	vm := find(p.Outbounds, "美国 vmess ws")
	if tr, _ := vm["transport"].(map[string]any); tr == nil || tr["type"] != "ws" || tr["path"] != "/ws" {
		t.Errorf("vmess ws 传输: %v", vm["transport"])
	}
	assertNoServiceBlocks(t, p)
	// Clash 的 wireguard 节点不写 allowed_ips（默认全部走隧道）：补上默认值，内核要求每个对端都有。
	peers := p.Endpoints[0]["peers"].([]any)
	if got := peers[0].(map[string]any)["allowed_ips"]; !reflect.DeepEqual(got, []any{"0.0.0.0/0", "::/0"}) {
		t.Errorf("allowed_ips = %v", got)
	}
}

func assertNoServiceBlocks(t testing.TB, p Profile) {
	t.Helper()
	b, _ := json.Marshal(p)
	var top map[string]any
	_ = json.Unmarshal(b, &top)
	for k := range top {
		if k != "outbounds" && k != "endpoints" {
			t.Errorf("输出不该含 %q", k)
		}
	}
}

func TestClashAnchorsAndMergeKeys(t *testing.T) {
	p, _ := mustParse(t, fixture(t, "clash-anchors.yaml"))
	if got := strings.Join(tags(p.Outbounds), ","); got != "anchor-a,anchor-b" {
		t.Fatalf("tags = %s", got)
	}
	a, b := p.Outbounds[0], p.Outbounds[1]
	if a["server"] != "192.0.2.21" || a["server_port"] != float64(8388) || a["method"] != "aes-128-gcm" || a["password"] != "synthetic-pw" {
		t.Errorf("合并键继承: %v", a)
	}
	if b["server_port"] != float64(9443) {
		t.Errorf("显式覆盖合并键: %v", b)
	}
}

func TestClashEmptyProxies(t *testing.T) {
	_, _, err := Parse(fixture(t, "clash-empty.yaml"))
	wantCode(t, err, CodeNoOutbounds)
}

func TestClashAllProxiesFailCarriesFirstReason(t *testing.T) {
	in := "proxies:\n  - {name: a, type: ssr, server: 192.0.2.1, port: 1}\n  - {name: b, type: unknown-proto, server: 192.0.2.2, port: 2}\n"
	_, w, err := Parse([]byte(in))
	wantCode(t, err, CodeNoOutbounds)
	if !strings.Contains(err.Error(), "ssr") || !strings.Contains(err.Error(), "none of the 2 proxies") {
		t.Errorf("应带首个失败原因: %v", err)
	}
	if w.Count("node-skipped:") != 2 {
		t.Errorf("warnings = %v", w)
	}
}

// Clash 的 JSON 写法（JSON 是 YAML 的子集）。
func TestClashInJSONForm(t *testing.T) {
	p, _ := mustParse(t, []byte(`{"proxies":[{"name":"j","type":"ss","server":"192.0.2.5","port":8388,"cipher":"aes-128-gcm","password":"pw"}]}`))
	if len(p.Outbounds) != 1 || p.Outbounds[0]["tag"] != "j" {
		t.Errorf("%v", p)
	}
}

// ---- sing-box JSON ----

func TestSingBoxFullConfigKeepsOnlyNodes(t *testing.T) {
	p, _ := mustParse(t, fixture(t, "singbox-full.json"))
	if got := strings.Join(tags(p.Outbounds), ","); got != "a,b" {
		t.Errorf("只应留节点: %s", got)
	}
	assertNoServiceBlocks(t, p)
}

func TestSingBoxArrayAndSingle(t *testing.T) {
	p, _ := mustParse(t, fixture(t, "singbox-array.json"))
	if got := strings.Join(tags(p.Outbounds), ","); got != "arr-a,arr-b" {
		t.Errorf("数组形态: %s", got)
	}
	p, _ = mustParse(t, fixture(t, "singbox-single.json"))
	if got := strings.Join(tags(p.Outbounds), ","); got != "single" {
		t.Errorf("单出站对象: %s", got)
	}
	// 数组里混进非对象：跳过并警告。
	p, w := mustParse(t, []byte(`[{"type":"shadowsocks","tag":"x","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"}, 42, "str"]`))
	if len(p.Outbounds) != 1 || w.Count("entry-skipped:") != 2 {
		t.Errorf("%v %v", p, w)
	}
}

func TestSingBoxLegacy18Shape(t *testing.T) {
	p, _ := mustParse(t, fixture(t, "singbox-legacy18.json"))
	if got := strings.Join(types(p.Outbounds), ","); got != "shadowsocks,trojan" {
		t.Errorf("出站 = %s", got)
	}
	if len(p.Endpoints) != 1 || p.Endpoints[0]["tag"] != "old-wg" {
		t.Errorf("wireguard 出站应变端点: %v", p.Endpoints)
	}
	ss := find(p.Outbounds, "old-ss")
	if _, ok := ss["domain_strategy"]; ok {
		t.Error("domain_strategy 应清除")
	}
	if _, ok := ss["tls_fragment"]; ok {
		t.Error("tls_fragment 应清除")
	}
	if tls := find(p.Outbounds, "old-trojan")["tls"].(map[string]any); tls["tls_tricks"] != nil {
		t.Error("tls_tricks 应清除")
	}
}

func TestSingBoxEntryShapes(t *testing.T) {
	// direct-only / group-only → no-outbounds；endpoint-only 被接受且端点保留。
	_, _, err := Parse(fixture(t, "singbox-direct-only.json"))
	wantCode(t, err, CodeNoOutbounds)
	_, _, err = Parse(fixture(t, "singbox-group-only.json"))
	wantCode(t, err, CodeNoOutbounds)
	p, _ := mustParse(t, fixture(t, "singbox-endpoint-only.json"))
	if len(p.Outbounds) != 0 || len(p.Endpoints) != 1 || p.NodeCount() != 1 {
		t.Errorf("endpoint-only: %+v", p)
	}
	// outbounds 为空数组要输出成 []，不是 null。
	b, _ := json.Marshal(p)
	if !strings.Contains(string(b), `"outbounds":[]`) {
		t.Errorf("outbounds 应是空数组: %s", b)
	}
}

// node-a → custom-direct：custom-direct 被删，node-a.detour == direct。
func TestSingBoxCustomDirectIsRemapped(t *testing.T) {
	p, w := mustParse(t, fixture(t, "singbox-custom-direct.json"))
	if find(p.Outbounds, "custom-direct") != nil {
		t.Error("custom-direct 应被删")
	}
	if got := find(p.Outbounds, "node-a")["detour"]; got != "direct" {
		t.Errorf("node-a.detour = %v", got)
	}
	if w.Count("detour-remapped:") != 1 {
		t.Errorf("warnings = %v", w)
	}
}

func TestSingBoxCommentsAreTolerated(t *testing.T) {
	p, _ := mustParse(t, fixture(t, "singbox-comments.json"))
	if len(p.Outbounds) != 1 || p.Outbounds[0]["tag"] != "url//in-string" || p.Outbounds[0]["password"] != "p/*not-a-comment*/w" {
		t.Errorf("字符串里的 // 与 /* 不是注释: %v", p.Outbounds)
	}
}

func TestJSONRejections(t *testing.T) {
	for name, in := range map[string]string{
		"空对象":     `{}`,
		"无关对象":    `{"hello":"world"}`,
		"坏 JSON":  `{"outbounds": [`,
		"空数组":     `[]`,
		"数组全是非对象": `[1,2,3]`,
	} {
		t.Run(name, func(t *testing.T) {
			_, _, err := Parse([]byte(in))
			if err == nil {
				t.Fatal("应当失败")
			}
			if c := CodeOf(err); c != CodeFormatUnknown && c != CodeNoOutbounds {
				t.Errorf("err = %v", err)
			}
		})
	}
}

// ---- URI 列表 ----

const ssLine1 = "ss://YWVzLTEyOC1nY206cHc@192.0.2.1:8388#hk-1"
const ssLine2 = "ss://YWVzLTEyOC1nY206cHc@192.0.2.2:8388#hk-2"

func TestURIListForms(t *testing.T) {
	plain := ssLine1 + "\n\n# 注释行\n" + ssLine2 + "\n"
	b64 := func(enc *base64.Encoding, s string) string { return enc.EncodeToString([]byte(s)) }
	cases := map[string][]byte{
		"明文":                       []byte(plain),
		"CRLF":                     []byte(strings.ReplaceAll(plain, "\n", "\r\n")),
		"BOM + 明文":                 append([]byte{0xEF, 0xBB, 0xBF}, plain...),
		"整体标准 base64":              []byte(b64(base64.StdEncoding, plain)),
		"整体 urlsafe base64":        []byte(b64(base64.URLEncoding, plain)),
		"标准 base64 无 padding":      []byte(b64(base64.RawStdEncoding, plain)),
		"urlsafe base64 无 padding": []byte(b64(base64.RawURLEncoding, plain)),
		"base64 夹带换行":              []byte(wrap(b64(base64.StdEncoding, plain), 20)),
		"BOM + CRLF + base64":      append([]byte{0xEF, 0xBB, 0xBF}, strings.ReplaceAll(wrap(b64(base64.StdEncoding, plain), 16), "\n", "\r\n")...),
	}
	for name, in := range cases {
		t.Run(name, func(t *testing.T) {
			p, _ := mustParse(t, in)
			if got := strings.Join(tags(p.Outbounds), ","); got != "hk-1,hk-2" {
				t.Errorf("tags = %s", got)
			}
		})
	}
}

func wrap(s string, n int) string {
	var b strings.Builder
	for len(s) > n {
		b.WriteString(s[:n] + "\n")
		s = s[n:]
	}
	b.WriteString(s)
	return b.String()
}

// base64 里包的是 JSON 或 Clash 时也认（解一次后重新识别）。
func TestBase64WrappedOtherFormats(t *testing.T) {
	j := base64.StdEncoding.EncodeToString(fixture(t, "singbox-single.json"))
	p, _ := mustParse(t, []byte(j))
	if len(p.Outbounds) != 1 || p.Outbounds[0]["tag"] != "single" {
		t.Errorf("base64(JSON): %v", p)
	}
	y := base64.StdEncoding.EncodeToString(fixture(t, "clash-anchors.yaml"))
	p, _ = mustParse(t, []byte(y))
	if len(p.Outbounds) != 2 {
		t.Errorf("base64(Clash): %v", p)
	}
}

// 部分节点损坏：部分成功 + 警告计数；全部失败才报错并带首个原因。
func TestURIListPartialAndTotalFailure(t *testing.T) {
	in := strings.Join([]string{ssLine1, "ss://not-valid", "gopher://example.net", "ssconf://example.net/x", "just text", ssLine2}, "\n")
	p, w := mustParse(t, []byte(in))
	if len(p.Outbounds) != 2 || w.Count("node-skipped:") != 4 {
		t.Errorf("outbounds=%d warnings=%v", len(p.Outbounds), w)
	}
	if !strings.Contains(strings.Join(w, "\n"), "ssconf") {
		t.Errorf("ssconf:// 应明确报不支持: %v", w)
	}

	_, w, err := Parse([]byte("ss://bad1\nss://bad2\n"))
	wantCode(t, err, CodeURIInvalid)
	if !strings.Contains(err.Error(), "none of the 2 links") || !strings.Contains(err.Error(), "line 1") {
		t.Errorf("应带首个失败原因: %v", err)
	}
	if w.Count("node-skipped:") != 2 {
		t.Errorf("warnings = %v", w)
	}
}

func TestFormatUnknown(t *testing.T) {
	for name, in := range map[string]string{
		"空":              "",
		"只有空白":           "  \n\t ",
		"HTML 页面":        "<!DOCTYPE html><html><body><h1>Access denied</h1><a href=\"http://example.net\">x</a></body></html>",
		"HTML 无 doctype": "<html><head></head><body>blocked</body></html>",
		"普通文字":           "this is not a subscription",
		"YAML 无 proxies": "port: 7890\nmode: rule\n",
		"只有注释行":          "# only comments\n# nothing else\n",
		"乱码":             "!!!@@@###",
		"base64 里不是已知格式": base64.StdEncoding.EncodeToString([]byte("hello world, nothing here")),
	} {
		t.Run(name, func(t *testing.T) {
			_, _, err := Parse([]byte(in))
			wantCode(t, err, CodeFormatUnknown)
		})
	}
}

// ---- 收尾：tag 去重与补全 ----

func TestTagDedupeAndFill(t *testing.T) {
	in := `[
	 {"type":"shadowsocks","tag":"dup","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"},
	 {"type":"shadowsocks","tag":"dup","server":"192.0.2.2","server_port":1,"method":"aes-128-gcm","password":"p"},
	 {"type":"shadowsocks","tag":"dup","server":"192.0.2.3","server_port":1,"method":"aes-128-gcm","password":"p"},
	 {"type":"shadowsocks","tag":"dup (2)","server":"192.0.2.4","server_port":1,"method":"aes-128-gcm","password":"p"},
	 {"type":"trojan","server":"192.0.2.5","server_port":443,"password":"p"},
	 {"type":"trojan","tag":"","server":"192.0.2.6","server_port":443,"password":"p"}
	]`
	p, w := mustParse(t, []byte(in))
	got := tags(p.Outbounds)
	want := []string{"dup", "dup (3)", "dup (4)", "dup (2)", "trojan-5", "trojan-6"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("tags = %v，期望 %v", got, want)
	}
	if w.Count("tag-renamed:") != 2 || w.Count("tag-filled:") != 2 {
		t.Errorf("warnings = %v", w)
	}
	seen := map[string]bool{}
	for _, tag := range got {
		if seen[tag] {
			t.Errorf("tag 重复: %s", tag)
		}
		seen[tag] = true
	}
}

// 端点与出站之间的 tag 也要唯一。
func TestTagDedupeAcrossOutboundsAndEndpoints(t *testing.T) {
	in := `{"outbounds":[{"type":"shadowsocks","tag":"x","server":"192.0.2.1","server_port":1,"method":"aes-128-gcm","password":"p"}],
	        "endpoints":[{"type":"wireguard","tag":"x","address":["10.0.0.2/32"],"private_key":"k","peers":[{"address":"192.0.2.9","port":51820,"public_key":"pk"}]}]}`
	p, _ := mustParse(t, []byte(in))
	if p.Outbounds[0]["tag"] != "x" || p.Endpoints[0]["tag"] != "x (2)" {
		t.Errorf("%v %v", p.Outbounds, p.Endpoints)
	}
}

// ---- 幂等 ----

func TestParseIsIdempotent(t *testing.T) {
	names := []string{"clash-protocols.yaml", "clash-anchors.yaml", "singbox-full.json", "singbox-array.json", "singbox-single.json",
		"singbox-legacy18.json", "singbox-endpoint-only.json", "singbox-custom-direct.json", "singbox-comments.json"}
	for _, name := range names {
		t.Run(name, func(t *testing.T) {
			first, _ := mustParse(t, fixture(t, name))
			raw, _ := json.Marshal(first)
			second, w := mustParse(t, raw)
			again, _ := json.Marshal(second)
			if !bytes.Equal(raw, again) {
				t.Errorf("Parse(Parse(x)) 不同:\n%s\n%s", raw, again)
			}
			if len(w) != 0 {
				t.Errorf("第二遍不该有警告: %v", w)
			}
		})
	}
}

// ---- 文件版 ----

func TestParseFile(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "out.json")
	if err := ParseFile(out, filepath.Join("testdata", "subscriptions", "singbox-endpoint-only.json"), false); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(out)
	var got Profile
	if err := json.Unmarshal(raw, &got); err != nil || len(got.Endpoints) != 1 {
		t.Fatalf("%v %s", err, raw)
	}
	// debug 输出缩进。
	if err := ParseFile(out, filepath.Join("testdata", "subscriptions", "singbox-single.json"), true); err != nil {
		t.Fatal(err)
	}
	raw, _ = os.ReadFile(out)
	if !strings.Contains(string(raw), "\n  \"outbounds\"") {
		t.Errorf("debug 应缩进: %s", raw)
	}
	// 失败不写、不留临时文件，并保持稳定码。
	bad := filepath.Join(dir, "bad.txt")
	_ = os.WriteFile(bad, []byte("<html></html>"), 0o644)
	out2 := filepath.Join(dir, "never.json")
	wantCode(t, ParseFile(out2, bad, false), CodeFormatUnknown)
	if _, err := os.Stat(out2); err == nil {
		t.Error("失败时不该写出文件")
	}
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".parse-") {
			t.Errorf("残留临时文件 %s", e.Name())
		}
	}
	wantCode(t, ParseFile(out2, filepath.Join(dir, "missing"), false), CodeBuildFailed)
}

// ---- 节点计数 ----

func TestNodeCount(t *testing.T) {
	mk := func(types ...string) []map[string]any {
		var out []map[string]any
		for i, ty := range types {
			out = append(out, map[string]any{"type": ty, "tag": fmt.Sprint(i)})
		}
		return out
	}
	cases := []struct {
		name string
		p    Profile
		want int
	}{
		{"空", Profile{}, 0},
		{"只有节点", Profile{Outbounds: mk("shadowsocks", "vmess")}, 2},
		{"分组 / direct / block / dns 不算", Profile{Outbounds: mk("selector", "urltest", "direct", "block", "dns", "shadowsocks")}, 1},
		{"写法不同的分组也不算", Profile{Outbounds: mk("url-test", "URLTest", "select", "custom")}, 0},
		{"端点独占", Profile{Outbounds: []map[string]any{}, Endpoints: mk("wireguard")}, 1},
		{"出站与端点混合", Profile{Outbounds: mk("trojan"), Endpoints: mk("wireguard", "wireguard")}, 3},
		{"只有分组 + 端点", Profile{Outbounds: mk("selector"), Endpoints: mk("wireguard")}, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.p.NodeCount(); got != tc.want {
				t.Errorf("NodeCount = %d，期望 %d", got, tc.want)
			}
		})
	}
}

// ---- 错误码 ----

func TestErrorCodes(t *testing.T) {
	e := fail(CodeNoOutbounds, "x %d", 1)
	if e.Error() != "no-outbounds: x 1" || CodeOf(e) != CodeNoOutbounds || !Is(e, CodeNoOutbounds) || Is(e, CodeURIInvalid) {
		t.Errorf("%v", e)
	}
	if CodeOf(fmt.Errorf("plain")) != "" || CodeFromMessage("something else") != "" {
		t.Error("没有稳定前缀应返回空串")
	}
	for _, c := range []string{CodeFormatUnknown, CodeNoOutbounds, CodeURIInvalid, CodeBuildFailed} {
		if CodeFromMessage("  "+c+" detail") != c {
			t.Errorf("CodeFromMessage(%q)", c)
		}
	}
	wrapped := fmt.Errorf("wrapped: %w", e)
	if CodeOf(wrapped) != CodeNoOutbounds {
		t.Error("应能穿过 %w 取到码")
	}
}

// ---- 规模 ----

// 5000 节点：耗时与内存上限断言，防回退。
func TestParseFiveThousandNodes(t *testing.T) {
	var sb strings.Builder
	for i := 0; i < 5000; i++ {
		fmt.Fprintf(&sb, "ss://YWVzLTEyOC1nY206cHc@192.0.2.%d:%d#node-%d\n", i%250+1, 10000+i, i)
	}
	text := sb.String()
	enc := base64.StdEncoding.EncodeToString([]byte(text))

	for name, in := range map[string]string{"明文": text, "base64": enc} {
		t.Run(name, func(t *testing.T) {
			var before, after runtime.MemStats
			runtime.GC()
			runtime.ReadMemStats(&before)
			start := time.Now()
			p, w := mustParse(t, []byte(in))
			elapsed := time.Since(start)
			runtime.ReadMemStats(&after)
			alloc := after.TotalAlloc - before.TotalAlloc
			if p.NodeCount() != 5000 || len(w) != 0 {
				t.Fatalf("节点数 = %d warnings=%d", p.NodeCount(), len(w))
			}
			t.Logf("%s：5000 节点 %v，分配 %.1f MiB", name, elapsed.Round(time.Millisecond), float64(alloc)/(1<<20))
			// 上限留足余量（CI 机器与 -race 都要过），只防数量级的回退。
			if elapsed > 10*time.Second {
				t.Errorf("耗时 %v 超过上限 10s", elapsed)
			}
			if alloc > 400<<20 {
				t.Errorf("分配 %d MiB 超过上限 400 MiB", alloc>>20)
			}
		})
	}
}

// 5000 个 Clash 节点同样要在上限内。
func TestParseFiveThousandClashProxies(t *testing.T) {
	var sb strings.Builder
	sb.WriteString("proxies:\n")
	for i := 0; i < 5000; i++ {
		fmt.Fprintf(&sb, "  - {name: n%d, type: ss, server: 192.0.2.%d, port: %d, cipher: aes-128-gcm, password: pw}\n", i, i%250+1, 10000+i)
	}
	start := time.Now()
	p, _ := mustParse(t, []byte(sb.String()))
	if p.NodeCount() != 5000 {
		t.Fatalf("节点数 = %d", p.NodeCount())
	}
	if d := time.Since(start); d > 10*time.Second {
		t.Errorf("耗时 %v 超过上限 10s", d)
	}
}
