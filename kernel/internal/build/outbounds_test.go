package build_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func ssNode(tag string) map[string]any {
	return map[string]any{"type": "shadowsocks", "tag": tag, "server": "192.0.2.10", "server_port": 8388, "method": "aes-128-gcm", "password": "x"}
}

func trojanNode(tag string) map[string]any {
	return map[string]any{"type": "trojan", "tag": tag, "server": "192.0.2.11", "server_port": 443, "password": "x",
		"tls": map[string]any{"enabled": true, "server_name": "t.example.net"}}
}

func wgEndpoint(tag string) map[string]any {
	return map[string]any{"type": "wireguard", "tag": tag, "address": []any{"10.8.0.2/32"}, "private_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
		"peers": []any{map[string]any{"address": "192.0.2.12", "port": 51820, "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "allowed_ips": []any{"0.0.0.0/0"}}}}
}

func outbound(t testing.TB, c *cfg.Config, tag string) cfg.Outbound {
	t.Helper()
	for _, o := range c.Outbounds {
		if o.Tag() == tag {
			return o
		}
	}
	t.Fatalf("没有出站 %s", tag)
	return nil
}

func members(t testing.TB, c *cfg.Config, group string) []string {
	t.Helper()
	var out []string
	for _, m := range outbound(t, c, group)["outbounds"].([]any) {
		out = append(out, m.(string))
	}
	return out
}

func buildProfile(t testing.TB, p build.Profile, o *options.Options) (*cfg.Config, []string, error) {
	t.Helper()
	raw, w, err := build.Build(p, o, build.AndroidEnv())
	if err != nil {
		return nil, w, err
	}
	var c cfg.Config
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	return &c, w, nil
}

func TestAssemblySelectAndAuto(t *testing.T) {
	c, _, err := buildProfile(t, build.Profile{Outbounds: []map[string]any{ssNode("a"), ssNode("b")}}, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(members(t, c, "select"), ","); got != "auto,a,b" {
		t.Errorf("select 成员 = %s", got)
	}
	if got := strings.Join(members(t, c, "auto"), ","); got != "a,b" {
		t.Errorf("auto 成员 = %s", got)
	}
	if outbound(t, c, "select")["default"] != "auto" {
		t.Errorf("默认应是 auto")
	}
	auto := outbound(t, c, "auto")
	if auto["type"] != "urltest" || auto["interval"] != "600s" || auto["idle_timeout"] != "6000s" || auto["url"] != options.Default().ConnectionTestURL {
		t.Errorf("auto = %v", auto)
	}
	// 预置出站齐全，且 direct-fragment 非空（可作 detour 目标）、没有 block / dns 出站。
	for _, tag := range []string{"direct", "direct-fragment", "bypass"} {
		if outbound(t, c, tag)["type"] != "direct" {
			t.Errorf("%s 应是 direct", tag)
		}
	}
	if len(outbound(t, c, "direct-fragment")) < 3 {
		t.Error("direct-fragment 必须带选项")
	}
	for _, o := range c.Outbounds {
		if o.Type() == "block" || o.Type() == "dns" {
			t.Errorf("不该生成 %s 出站", o.Type())
		}
	}
}

// 订阅自带的 selector / urltest / direct / block / dns 一律丢弃。
func TestAssemblyDropsSubscriptionGroups(t *testing.T) {
	p := build.Profile{Outbounds: []map[string]any{
		{"type": "selector", "tag": "我的选择", "outbounds": []any{"a"}},
		{"type": "urltest", "tag": "我的测速", "outbounds": []any{"a"}},
		{"type": "url-test", "tag": "另一种写法", "outbounds": []any{"a"}},
		{"type": "direct", "tag": "my-direct"},
		{"type": "block", "tag": "my-block"},
		{"type": "dns", "tag": "dns-out"},
		ssNode("a"),
	}}
	c, _, err := buildProfile(t, p, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	for _, tag := range []string{"我的选择", "我的测速", "另一种写法", "my-direct", "my-block", "dns-out"} {
		for _, o := range c.Outbounds {
			if o.Tag() == tag {
				t.Errorf("%s 应被丢弃", tag)
			}
		}
	}
	if got := strings.Join(members(t, c, "select"), ","); got != "auto,a" {
		t.Errorf("select 成员 = %s", got)
	}
}

// tag 与预置 tag 冲突（含 warp）、重复 tag：改名而不是丢弃，给 warning；别的节点对它的 detour 同步改写。
func TestAssemblyRenamesConflictingTags(t *testing.T) {
	cases := []struct {
		name      string
		nodes     []map[string]any
		wantTags  []string
		wantWarns int
	}{
		{"与 select 冲突", []map[string]any{ssNode("select")}, []string{"select (2)"}, 1},
		{"与 auto 冲突", []map[string]any{ssNode("auto")}, []string{"auto (2)"}, 1},
		{"与 direct 冲突", []map[string]any{ssNode("direct")}, []string{"direct (2)"}, 1},
		{"与 bypass 冲突", []map[string]any{ssNode("bypass")}, []string{"bypass (2)"}, 1},
		{"与 direct-fragment 冲突", []map[string]any{ssNode("direct-fragment")}, []string{"direct-fragment (2)"}, 1},
		{"与 block 冲突", []map[string]any{ssNode("block")}, []string{"block (2)"}, 1},
		{"与 warp 冲突", []map[string]any{ssNode("warp")}, []string{"warp (2)"}, 1},
		{"重复 tag", []map[string]any{ssNode("a"), ssNode("a"), ssNode("a")}, []string{"a", "a (2)", "a (3)"}, 2},
		{"改名结果也已被占用", []map[string]any{ssNode("direct"), ssNode("direct (2)")}, []string{"direct (3)", "direct (2)"}, 1},
		{"无冲突", []map[string]any{ssNode("a"), ssNode("b")}, []string{"a", "b"}, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, w, err := buildProfile(t, build.Profile{Outbounds: tc.nodes}, gate.Option("O1"))
			if err != nil {
				t.Fatal(err)
			}
			var got []string
			for _, o := range c.Outbounds {
				if o.Type() == "shadowsocks" {
					got = append(got, o.Tag())
				}
			}
			if strings.Join(got, "|") != strings.Join(tc.wantTags, "|") {
				t.Errorf("节点 tag = %v，期望 %v", got, tc.wantTags)
			}
			if len(w) != tc.wantWarns {
				t.Errorf("warnings = %v，期望 %d 条", w, tc.wantWarns)
			}
			for _, x := range w {
				if !strings.HasPrefix(x, "tag-renamed:") {
					t.Errorf("警告前缀不对: %s", x)
				}
			}
		})
	}
}

// 与预置 tag 冲突而被改名的节点：别的节点的 detour 引用同步改写；重复 tag 的引用保持指向第一个。
func TestAssemblyRewritesDetourReferencesToRenamedNodes(t *testing.T) {
	a := ssNode("direct") // 订阅里叫 direct 的代理节点
	b := ssNode("b")
	b["detour"] = "direct"
	c, _, err := buildProfile(t, build.Profile{Outbounds: []map[string]any{a, b}}, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	if got := outbound(t, c, "b")["detour"]; got != "direct (2)" {
		t.Errorf("b.detour = %v，应跟着改名", got)
	}
	if outbound(t, c, "direct (2)")["type"] != "shadowsocks" {
		t.Error("改名后的节点应还是代理节点")
	}
	if outbound(t, c, "direct")["type"] != "direct" {
		t.Error("预置 direct 不该被订阅节点顶替")
	}
}

// 不修改调用方的 profile（构建器要在节点上改 tls / multiplex）。
func TestAssemblyDoesNotMutateProfile(t *testing.T) {
	p := build.Profile{Outbounds: []map[string]any{trojanNode("t")}}
	before, _ := json.Marshal(p)
	o := gate.Option("O4")
	if _, _, err := buildProfile(t, p, o); err != nil {
		t.Fatal(err)
	}
	after, _ := json.Marshal(p)
	if string(before) != string(after) {
		t.Errorf("profile 被修改:\n%s\n%s", before, after)
	}
}

// 隐藏节点不进 select / auto，但仍作为出站存在（可被别的节点 detour）。
func TestAssemblyHiddenNodes(t *testing.T) {
	hidden := ssNode("剩余流量 §hide§")
	via := ssNode("via")
	via["detour"] = "剩余流量 §hide§"
	c, _, err := buildProfile(t, build.Profile{Outbounds: []map[string]any{hidden, ssNode("a"), via}}, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(members(t, c, "select"), ","); got != "auto,a,via" {
		t.Errorf("select 成员 = %s", got)
	}
	if got := strings.Join(members(t, c, "auto"), ","); got != "a,via" {
		t.Errorf("auto 成员 = %s", got)
	}
	outbound(t, c, "剩余流量 §hide§") // 仍存在
}

func TestAssemblyAllHiddenIsNoOutbounds(t *testing.T) {
	_, _, err := buildProfile(t, build.Profile{Outbounds: []map[string]any{ssNode("x §hide§")}}, gate.Option("O1"))
	if err == nil || !strings.HasPrefix(err.Error(), build.PrefixNoOutbounds) {
		t.Fatalf("err = %v", err)
	}
}

// 默认标记：取含标记的节点 / 端点的真实 tag；标在端点上同样；没有则 auto；多个取第一个。
func TestAssemblyDefaultMarker(t *testing.T) {
	cases := []struct {
		name string
		p    build.Profile
		want string
	}{
		{"无标记", build.Profile{Outbounds: []map[string]any{ssNode("a")}}, "auto"},
		{"标在节点上", build.Profile{Outbounds: []map[string]any{ssNode("a"), ssNode("b§default§")}}, "b§default§"},
		{"标在端点上", build.Profile{Outbounds: []map[string]any{ssNode("a")}, Endpoints: []map[string]any{wgEndpoint("wg§default§")}}, "wg§default§"},
		{"端点独占且带标记", build.Profile{Endpoints: []map[string]any{wgEndpoint("wg-1"), wgEndpoint("wg-2§default§")}}, "wg-2§default§"},
		{"多个取第一个", build.Profile{Outbounds: []map[string]any{ssNode("a§default§"), ssNode("b§default§")}}, "a§default§"},
		{"隐藏节点上的标记不算", build.Profile{Outbounds: []map[string]any{ssNode("a"), ssNode("x§hide§§default§")}}, "auto"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, _, err := buildProfile(t, tc.p, gate.Option("O1"))
			if err != nil {
				t.Fatal(err)
			}
			if got := outbound(t, c, "select")["default"]; got != tc.want {
				t.Errorf("select.default = %v，期望 %s", got, tc.want)
			}
			if tc.want != "auto" && !containsString(members(t, c, "select"), tc.want) {
				t.Errorf("默认值 %s 必须是 select 的成员", tc.want)
			}
		})
	}
}

func containsString(list []string, s string) bool {
	for _, e := range list {
		if e == s {
			return true
		}
	}
	return false
}

// 端点：独占 / 与出站混合 / 仅一个节点；端点进 select 与 auto，顺序在出站之后。
func TestAssemblyEndpointForms(t *testing.T) {
	cases := []struct {
		name      string
		p         build.Profile
		wantMembs string
		wantEPs   int
	}{
		{"端点独占", build.Profile{Endpoints: []map[string]any{wgEndpoint("wg-1")}}, "wg-1", 1},
		{"端点与出站混合", build.Profile{Outbounds: []map[string]any{ssNode("a")}, Endpoints: []map[string]any{wgEndpoint("wg-1"), wgEndpoint("wg-0")}}, "a,wg-1,wg-0", 2},
		{"仅一个节点", build.Profile{Outbounds: []map[string]any{ssNode("only")}}, "only", 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, _, err := buildProfile(t, tc.p, gate.Option("O1"))
			if err != nil {
				t.Fatal(err)
			}
			if got := strings.Join(members(t, c, "auto"), ","); got != tc.wantMembs {
				t.Errorf("auto 成员 = %s，期望 %s", got, tc.wantMembs)
			}
			if got := strings.Join(members(t, c, "select"), ","); got != "auto,"+tc.wantMembs {
				t.Errorf("select 成员 = %s", got)
			}
			if len(c.Endpoints) != tc.wantEPs {
				t.Errorf("端点数 = %d，期望 %d", len(c.Endpoints), tc.wantEPs)
			}
		})
	}
}

// 端点的类型引用：端点不出现在 outbounds 里（避免同 tag 两处）。
func TestAssemblyEndpointsAreNotOutbounds(t *testing.T) {
	c, _, err := buildProfile(t, build.Profile{Endpoints: []map[string]any{wgEndpoint("wg-1")}}, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	for _, o := range c.Outbounds {
		if o.Tag() == "wg-1" {
			t.Error("端点不该同时出现在 outbounds 里")
		}
	}
}

func TestAssemblyNoUsableOutbound(t *testing.T) {
	for name, p := range map[string]build.Profile{
		"空":              {},
		"只有 direct":      {Outbounds: []map[string]any{{"type": "direct", "tag": "d"}}},
		"只有分组":           {Outbounds: []map[string]any{{"type": "selector", "tag": "s", "outbounds": []any{}}, {"type": "urltest", "tag": "u"}}},
		"只有 block / dns": {Outbounds: []map[string]any{{"type": "block", "tag": "b"}, {"type": "dns", "tag": "d"}}},
	} {
		t.Run(name, func(t *testing.T) {
			_, _, err := buildProfile(t, p, gate.Option("O1"))
			if err == nil || !strings.HasPrefix(err.Error(), build.PrefixNoOutbounds) {
				t.Fatalf("err = %v，期望 no-outbounds:", err)
			}
		})
	}
}

// 分片：tls.enabled 的出站设 fragment 与 record_fragment；reality 与 UDP 类跳过；关闭时一个都不写。
func TestFragmentInjection(t *testing.T) {
	reality := map[string]any{"type": "vless", "tag": "r", "server": "192.0.2.20", "server_port": 443, "uuid": "u",
		"tls": map[string]any{"enabled": true, "reality": map[string]any{"enabled": true, "public_key": "k", "short_id": "ab"}}}
	hy2 := map[string]any{"type": "hysteria2", "tag": "h", "server": "192.0.2.21", "server_port": 443, "password": "x",
		"tls": map[string]any{"enabled": true, "server_name": "h.example.net"}}
	plainTLSOff := map[string]any{"type": "trojan", "tag": "off", "server": "192.0.2.22", "server_port": 443, "password": "x",
		"tls": map[string]any{"enabled": false}}
	p := build.Profile{Outbounds: []map[string]any{trojanNode("t"), reality, hy2, plainTLSOff, ssNode("s")}}

	frag := func(c *cfg.Config, tag string) (bool, bool) {
		tls, ok := outbound(t, c, tag)["tls"].(map[string]any)
		if !ok {
			return false, false
		}
		f, _ := tls["fragment"].(bool)
		rf, _ := tls["record_fragment"].(bool)
		return f, rf
	}

	off, _, err := buildProfile(t, p, gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	for _, tag := range []string{"t", "r", "h", "off"} {
		if f, rf := frag(off, tag); f || rf {
			t.Errorf("关闭分片时 %s 不该有 fragment 字段", tag)
		}
	}

	on, _, err := buildProfile(t, p, gate.Option("O4"))
	if err != nil {
		t.Fatal(err)
	}
	if f, rf := frag(on, "t"); !f || !rf {
		t.Error("trojan + tls 应有 fragment 与 record_fragment")
	}
	for _, tag := range []string{"r", "h", "off"} {
		if f, rf := frag(on, tag); f || rf {
			t.Errorf("%s 不该分片（reality / UDP 类 / tls 未启用）", tag)
		}
	}
	if _, ok := outbound(t, on, "s")["tls"]; ok {
		t.Error("没有 tls 的节点不该被凭空加上 tls 块")
	}
}

// 多路复用：只对 vmess / vless / trojan / shadowsocks 且无自带 multiplex；reality 与带 flow 的跳过。
func TestMuxInjection(t *testing.T) {
	vmess := map[string]any{"type": "vmess", "tag": "vm", "server": "192.0.2.30", "server_port": 443, "uuid": "u"}
	own := ssNode("own")
	own["multiplex"] = map[string]any{"enabled": true, "protocol": "smux"}
	reality := map[string]any{"type": "vless", "tag": "r", "server": "192.0.2.31", "server_port": 443, "uuid": "u",
		"tls": map[string]any{"enabled": true, "reality": map[string]any{"enabled": true, "public_key": "k", "short_id": "ab"}}}
	vision := map[string]any{"type": "vless", "tag": "v", "server": "192.0.2.32", "server_port": 443, "uuid": "u", "flow": "xtls-rprx-vision"}
	tuic := map[string]any{"type": "tuic", "tag": "tu", "server": "192.0.2.33", "server_port": 443, "uuid": "u", "password": "x"}
	p := build.Profile{Outbounds: []map[string]any{ssNode("s"), trojanNode("t"), vmess, own, reality, vision, tuic}}

	o := gate.Option("O1")
	off, _, _ := buildProfile(t, p, o)
	for _, tag := range []string{"s", "t", "vm", "r", "v", "tu"} {
		if _, ok := outbound(t, off, tag)["multiplex"]; ok {
			t.Errorf("关闭 mux 时 %s 不该有 multiplex", tag)
		}
	}

	o.Mux = options.Mux{Enable: true, Padding: true, MaxStreams: 4, Protocol: "smux"}
	on, _, _ := buildProfile(t, p, o)
	for _, tag := range []string{"s", "t", "vm"} {
		m, ok := outbound(t, on, tag)["multiplex"].(map[string]any)
		if !ok || m["enabled"] != true || m["protocol"] != "smux" || m["max_streams"] != float64(4) || m["padding"] != true {
			t.Errorf("%s 的 multiplex = %v", tag, outbound(t, on, tag)["multiplex"])
		}
	}
	if m := outbound(t, on, "own")["multiplex"].(map[string]any); m["protocol"] != "smux" || m["enabled"] != true || len(m) != 2 {
		t.Errorf("自带 multiplex 不该被覆盖: %v", m)
	}
	for _, tag := range []string{"r", "v", "tu"} {
		if _, ok := outbound(t, on, tag)["multiplex"]; ok {
			t.Errorf("%s 不该注入 multiplex（reality / flow / UDP 类）", tag)
		}
	}
}

// 不能兑现的 tls-tricks 键：用户打开了就给 warning。
func TestTLSTricksWarnings(t *testing.T) {
	p := build.Profile{Outbounds: []map[string]any{trojanNode("t")}}
	_, w, _ := buildProfile(t, p, gate.Option("O4"))
	if len(w) != 0 {
		t.Errorf("默认的分片参数不该有警告: %v", w)
	}
	o := gate.Option("O4")
	o.TLSTricks.MixedSNICase, o.TLSTricks.EnablePadding, o.TLSTricks.FragmentSize = true, true, "20-50"
	_, w, _ = buildProfile(t, p, o)
	joined := strings.Join(w, "\n")
	for _, want := range []string{"mixed-sni-case", "enable-padding", "fragment-size"} {
		if !strings.Contains(joined, want) {
			t.Errorf("应有关于 %s 的警告: %v", want, w)
		}
	}
}

// ---- detour 校验 ----

func TestValidateDetoursClasses(t *testing.T) {
	withDetour := func(tag, detour string) map[string]any {
		n := ssNode(tag)
		n["detour"] = detour
		return n
	}
	cases := []struct {
		name   string
		nodes  []map[string]any
		eps    []map[string]any
		wantIs error
	}{
		{"detour 指向 direct-fragment 合法", []map[string]any{withDetour("node-a", "direct-fragment")}, nil, nil},
		{"detour 指向另一个节点合法", []map[string]any{ssNode("x"), withDetour("node-a", "x")}, nil, nil},
		{"detour 指向端点合法", []map[string]any{withDetour("node-a", "wg-1")}, []map[string]any{wgEndpoint("wg-1")}, nil},
		{"detour 指向自定义直连（被丢弃）悬空", []map[string]any{{"type": "direct", "tag": "custom-direct"}, withDetour("node-a", "custom-direct")}, nil, build.ErrDetourDangling},
		{"detour 指向不存在的 tag 悬空", []map[string]any{withDetour("node-b", "ghost")}, nil, build.ErrDetourDangling},
		{"detour 指向被丢弃的 selector 悬空", []map[string]any{{"type": "selector", "tag": "grp", "outbounds": []any{}}, withDetour("node-a", "grp")}, nil, build.ErrDetourDangling},
		{"detour 指向被丢弃的 block 悬空", []map[string]any{{"type": "block", "tag": "blk"}, withDetour("node-a", "blk")}, nil, build.ErrDetourDangling},
		{"两节点成环", []map[string]any{withDetour("a", "b"), withDetour("b", "a")}, nil, build.ErrDetourCycle},
		{"自环", []map[string]any{withDetour("a", "a")}, nil, build.ErrDetourCycle},
		{"三节点成环", []map[string]any{withDetour("a", "b"), withDetour("b", "c"), withDetour("c", "a")}, nil, build.ErrDetourCycle},
		{"端点参与成环", []map[string]any{withDetour("a", "wg-1")}, []map[string]any{func() map[string]any { e := wgEndpoint("wg-1"); e["detour"] = "a"; return e }()}, build.ErrDetourCycle},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, _, err := buildProfile(t, build.Profile{Outbounds: tc.nodes, Endpoints: tc.eps}, gate.Option("O1"))
			if tc.wantIs == nil {
				if err != nil {
					t.Fatalf("不该失败: %v", err)
				}
				return
			}
			if err == nil || !errors.Is(err, tc.wantIs) || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
				t.Fatalf("err = %v，期望 build-failed: 且 errors.Is(%v)", err, tc.wantIs)
			}
		})
	}
}

// 反例：绕过装配步骤的坏配置（detour 成环 / 悬空 / selector 默认值非成员）被最终图校验 ValidateGraph 抓住，
// 也被闸门的不变量抓住——两道独立检查互为印证。
func TestValidateGraphCatchesWhatAssemblySkipped(t *testing.T) {
	base := func() *cfg.Config {
		return &cfg.Config{Outbounds: []cfg.Outbound{
			{"type": "selector", "tag": "select", "outbounds": []any{"a"}, "default": "a"},
			{"type": "shadowsocks", "tag": "a", "server": "192.0.2.1", "server_port": 1},
			{"type": "shadowsocks", "tag": "b", "server": "192.0.2.2", "server_port": 1},
		}}
	}
	if err := build.ValidateGraph(base()); err != nil {
		t.Fatalf("基线应合法: %v", err)
	}
	cases := []struct {
		name   string
		mutate func(c *cfg.Config)
		want   error
		substr string
	}{
		{"成环", func(c *cfg.Config) { c.Outbounds[1]["detour"] = "b"; c.Outbounds[2]["detour"] = "a" }, build.ErrDetourCycle, ""},
		{"悬空", func(c *cfg.Config) { c.Outbounds[1]["detour"] = "ghost" }, build.ErrDetourDangling, ""},
		{"§default§ 指向不存在的节点", func(c *cfg.Config) { c.Outbounds[0]["default"] = "§default§" }, nil, "is not a member"},
		{"成员不存在", func(c *cfg.Config) { c.Outbounds[0]["outbounds"] = []any{"a", "ghost"} }, nil, "does not exist"},
		{"重复 tag", func(c *cfg.Config) { c.Outbounds[2]["tag"] = "a" }, nil, "duplicate tag"},
		{"route.final 不存在", func(c *cfg.Config) { c.Route = &cfg.Route{Final: "ghost"} }, nil, "route.final"},
		{"DNS detour 指向空 direct", func(c *cfg.Config) {
			c.Outbounds = append(c.Outbounds, cfg.Outbound{"type": "direct", "tag": "direct"})
			c.DNS = &cfg.DNS{Servers: []cfg.DNSServer{{Type: "udp", Tag: "dns-direct", Server: "223.5.5.5", Detour: "direct"}}}
		}, nil, "empty direct"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := base()
			tc.mutate(c)
			err := build.ValidateGraph(c)
			if err == nil {
				t.Fatal("应当失败")
			}
			if tc.want != nil && !errors.Is(err, tc.want) {
				t.Errorf("err = %v，期望 errors.Is(%v)", err, tc.want)
			}
			if tc.substr != "" && !strings.Contains(err.Error(), tc.substr) {
				t.Errorf("err = %v，期望含 %q", err, tc.substr)
			}
		})
	}
}

// 把 PatchWarp 钩子钉住：WARP 未启用时原样返回。
func TestPatchWarpIsNoOpWhenDisabled(t *testing.T) {
	in := []cfg.Endpoint{{"type": "wireguard", "tag": "wg-1"}}
	out, err := build.PatchWarp(in, gate.Option("O1"))
	if err != nil || len(out) != 1 || out[0].Tag() != "wg-1" {
		t.Fatalf("out=%v err=%v", out, err)
	}
}
