package build_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// WARP 出站图的单元测试（spec §5.2.2）。断言来自 build.CheckWarpGraph——与装配（ApplyWarp）读同一张策略表。
// 每个模式、每类输入各写明预期；没有「对两种模式一刀切」的断言。

const (
	proxyOverWarp = "O5a"
	warpOverProxy = "O5b"
)

func warpOptions(name string) (*options.Options, build.WarpPolicy) {
	o := gate.Option(name)
	p, ok := build.PolicyFor(o)
	if !ok {
		panic("选项夹具 " + name + " 没有启用 WARP")
	}
	return o, p
}

// ss 节点的 JSON 形态；detour 为空则不写。
func node(tag, detour string) map[string]any {
	m := map[string]any{"type": "shadowsocks", "tag": tag, "server": "192.0.2.10", "server_port": 8388, "method": "aes-128-gcm", "password": "x"}
	if detour != "" {
		m["detour"] = detour
	}
	return m
}

func wgSub(tag, detour string) map[string]any {
	m := wgEndpoint(tag)
	if detour != "" {
		m["detour"] = detour
	}
	return m
}

func profileJSON(t testing.TB, outbounds []map[string]any, endpoints []map[string]any) []byte {
	t.Helper()
	b, err := json.Marshal(map[string]any{"outbounds": outbounds, "endpoints": endpoints})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// buildJSON 走真实的「读订阅文件 → 清洗 → 构建」入口。
func buildJSON(t testing.TB, profile []byte, o *options.Options) ([]byte, []string, error) {
	t.Helper()
	return build.BuildJSON(profile, o, build.AndroidEnv())
}

type builtConfig struct {
	Outbounds []map[string]any `json:"outbounds"`
	Endpoints []map[string]any `json:"endpoints"`
	Route     struct {
		Final string           `json:"final"`
		Rules []map[string]any `json:"rules"`
	} `json:"route"`
	DNS struct {
		Servers []map[string]any `json:"servers"`
	} `json:"dns"`
}

func decode(t testing.TB, raw []byte) *builtConfig {
	t.Helper()
	var c builtConfig
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	return &c
}

func (c *builtConfig) entity(tag string) map[string]any {
	for _, o := range c.Outbounds {
		if o["tag"] == tag {
			return o
		}
	}
	for _, e := range c.Endpoints {
		if e["tag"] == tag {
			return e
		}
	}
	return nil
}

func (c *builtConfig) detour(tag string) string {
	e := c.entity(tag)
	if e == nil {
		return "<没有这个实体>"
	}
	d, _ := e["detour"].(string)
	return d
}

func (c *builtConfig) dnsRemoteDetour() string {
	for _, s := range c.DNS.Servers {
		if s["tag"] == "dns-remote" {
			d, _ := s["detour"].(string)
			return d
		}
	}
	return "<没有 dns-remote>"
}

func rewriteWarnings(ws []string) []string {
	var out []string
	for _, w := range ws {
		if strings.HasPrefix(w, "warp-chain-rewritten:") || strings.HasPrefix(w, "detour-remapped:") {
			out = append(out, w)
		}
	}
	return out
}

// mustCheck 跑图断言，期望零违规。
func mustCheck(t testing.TB, raw []byte, p build.WarpPolicy) {
	t.Helper()
	vs, err := build.CheckWarpGraph(raw, p)
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) != 0 {
		t.Fatalf("WARP 图断言（%s）违规:\n  %s", p.Mode, strings.Join(vs, "\n  "))
	}
}

// mustViolate 跑图断言，期望至少有一条违规含 want。
func mustViolate(t testing.TB, raw []byte, p build.WarpPolicy, want string) {
	t.Helper()
	vs, err := build.CheckWarpGraph(raw, p)
	if err != nil {
		t.Fatal(err)
	}
	for _, v := range vs {
		if strings.Contains(v, want) {
			return
		}
	}
	t.Fatalf("期望图断言报出含 %q 的违规，实际: %v", want, vs)
}

// 策略表本身：两个模式的装配参数与 spec §5.2.2 的表一致（表是唯一事实来源，这里钉住它的值）。
func TestWarpPolicyTable(t *testing.T) {
	_, over := warpOptions(warpOverProxy)
	if over.Egress != "warp" || over.WarpDetour != "select" || over.NodeDial != build.NodeDialKeep {
		t.Errorf("warp_over_proxy 策略 = %+v", over)
	}
	_, under := warpOptions(proxyOverWarp)
	if under.Egress != "select" || under.WarpDetour != "" || under.NodeDial != build.NodeDialTerminateAtWarp {
		t.Errorf("proxy_over_warp 策略 = %+v", under)
	}
	if _, on := build.PolicyFor(gate.Option("O1")); on {
		t.Error("WARP 未启用时不该有策略")
	}
}

// 图矩阵：两种模式 × 有 / 无订阅端点 × 节点 detour 的七类输入；全部过各自模式的图断言。
func TestWarpGraphMatrix(t *testing.T) {
	type input struct {
		name      string
		outbounds []map[string]any
		wantErr   error
	}
	inputs := []input{
		{"无 detour", []map[string]any{node("node-a", "")}, nil},
		{"代理链", []map[string]any{node("node-a", "carrier"), node("carrier", "")}, nil},
		{"以 direct-fragment 终止", []map[string]any{node("node-a", "direct-fragment")}, nil},
		{"以 direct 终止", []map[string]any{node("node-a", "direct")}, nil},
		{"以 bypass 终止", []map[string]any{node("node-a", "bypass")}, nil},
		{"成环", []map[string]any{node("a", "b"), node("b", "a")}, build.ErrDetourCycle},
		{"悬空", []map[string]any{node("node-b", "ghost")}, build.ErrDetourDangling},
	}
	for _, mode := range []string{proxyOverWarp, warpOverProxy} {
		o, p := warpOptions(mode)
		for _, withEndpoint := range []bool{false, true} {
			for _, in := range inputs {
				name := fmt.Sprintf("%s/endpoint=%v/%s", p.Mode, withEndpoint, in.name)
				t.Run(name, func(t *testing.T) {
					var eps []map[string]any
					if withEndpoint {
						eps = []map[string]any{wgSub("wg-1", "")}
					}
					raw, _, err := buildJSON(t, profileJSON(t, in.outbounds, eps), o)
					if in.wantErr != nil {
						if !errors.Is(err, in.wantErr) || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
							t.Fatalf("err = %v，期望 errors.Is(%v) 且以 %s 开头", err, in.wantErr, build.PrefixBuildFailed)
						}
						return
					}
					if err != nil {
						t.Fatal(err)
					}
					mustCheck(t, raw, p)
				})
			}
		}
	}
}

// warp_over_proxy：既有 detour 链原样保留（含以 direct-fragment 终止），无 warning，业务入口的第一跳是 warp。
func TestWarpOverProxyKeepsChains(t *testing.T) {
	o, p := warpOptions(warpOverProxy)
	raw, warnings, err := buildJSON(t, profileJSON(t,
		[]map[string]any{node("node-a", "direct-fragment"), node("node-b", "carrier"), node("carrier", "")},
		[]map[string]any{wgSub("wg-1", "carrier")}), o)
	if err != nil {
		t.Fatal(err)
	}
	mustCheck(t, raw, p)
	c := decode(t, raw)
	if got := c.detour("node-a"); got != "direct-fragment" {
		t.Errorf("node-a.detour = %q，应保持 direct-fragment", got)
	}
	if got := c.detour("node-b"); got != "carrier" {
		t.Errorf("node-b.detour = %q", got)
	}
	if got := c.detour("carrier"); got != "" {
		t.Errorf("carrier 不该被改写: %q", got)
	}
	if got := c.detour("wg-1"); got != "carrier" {
		t.Errorf("订阅端点的链也应保持: %q", got)
	}
	if got := c.detour("warp"); got != "select" {
		t.Errorf("warp.detour = %q", got)
	}
	if c.Route.Final != "warp" || c.dnsRemoteDetour() != "warp" {
		t.Errorf("route.final = %q，dns-remote.detour = %q，都应是 warp", c.Route.Final, c.dnsRemoteDetour())
	}
	if ws := rewriteWarnings(warnings); len(ws) != 0 {
		t.Errorf("warp_over_proxy 不改写链，不该有改写 warning: %v", ws)
	}
	// 预置 direct-fragment 本身不变
	if e := c.entity("direct-fragment"); e == nil || e["udp_fragment"] != true {
		t.Errorf("direct-fragment 被改动: %v", e)
	}
}

// proxy_over_warp：每个节点 / 端点的链终点都是 warp；预置出站不动；被改写的既有链各记一条 warning，共享末端只改一次，幂等。
func TestProxyOverWarpTerminatesEveryChainAtWarp(t *testing.T) {
	o, p := warpOptions(proxyOverWarp)
	prof := profileJSON(t,
		[]map[string]any{
			node("node-a", "direct-fragment"),
			node("node-b", "carrier-1"), node("carrier-1", "carrier-2"), node("carrier-2", ""),
			node("node-c", ""),
		},
		[]map[string]any{wgSub("wg-1", "carrier-1")})
	raw, warnings, err := buildJSON(t, prof, o)
	if err != nil {
		t.Fatal(err)
	}
	mustCheck(t, raw, p)
	c := decode(t, raw)

	want := map[string]string{
		"node-a": "warp", "node-b": "carrier-1", "carrier-1": "carrier-2", "carrier-2": "warp", "node-c": "warp", "wg-1": "carrier-1",
	}
	for tag, d := range want {
		if got := c.detour(tag); got != d {
			t.Errorf("%s.detour = %q，期望 %q", tag, got, d)
		}
	}
	if got := c.detour("warp"); got != "" {
		t.Errorf("warp 自己不该有 detour: %q", got)
	}
	if c.Route.Final != "select" || c.dnsRemoteDetour() != "select" {
		t.Errorf("route.final = %q，dns-remote.detour = %q，都应是 select", c.Route.Final, c.dnsRemoteDetour())
	}
	// 预置 direct-fragment 本身不变（别的规则 / 节点仍可直连）
	if e := c.entity("direct-fragment"); e == nil || e["udp_fragment"] != true || e["detour"] != nil {
		t.Errorf("direct-fragment 被改动: %v", e)
	}

	// 有既有 detour 的实体：node-a、node-b、carrier-1、wg-1 → 各一条；无 detour 的 carrier-2 / node-c 不记。
	ws := rewriteWarnings(warnings)
	if len(ws) != 4 {
		t.Fatalf("改写 warning 应恰好 4 条（每条被改写的既有链一条），实际 %d: %v", len(ws), ws)
	}
	for _, tag := range []string{"node-a", "node-b", "carrier-1", "wg-1"} {
		n := 0
		for _, w := range ws {
			if strings.Contains(w, fmt.Sprintf("%q dial chain", tag)) {
				n++
			}
		}
		if n != 1 {
			t.Errorf("%s 应恰好 1 条 warning，实际 %d: %v", tag, n, ws)
		}
	}
	for _, w := range ws {
		if strings.Contains(w, `"node-a"`) && !strings.Contains(w, "fragmentation dropped") {
			t.Errorf("direct-fragment 被替换时应注明分片被丢弃: %s", w)
		}
		if strings.HasPrefix(w, `warp-chain-rewritten: "carrier-2"`) || strings.HasPrefix(w, `warp-chain-rewritten: "node-c"`) {
			t.Errorf("无既有 detour 的节点不该有 warning: %s", w)
		}
	}
}

// RedirectToWarp 本身：表驱动（八类末端），幂等。
func TestRedirectToWarpTable(t *testing.T) {
	type tc struct {
		name     string
		in       []map[string]any
		want     map[string]string // tag → 期望 detour
		warnings int
		wantErr  error
	}
	cases := []tc{
		{"无 detour", []map[string]any{node("a", "")}, map[string]string{"a": "warp"}, 0, nil},
		{"单跳代理链", []map[string]any{node("a", "p"), node("p", "")}, map[string]string{"a": "p", "p": "warp"}, 1, nil},
		{"多跳代理链（共享末端）", []map[string]any{node("a", "p1"), node("b", "p1"), node("p1", "p2"), node("p2", "")},
			map[string]string{"a": "p1", "b": "p1", "p1": "p2", "p2": "warp"}, 3, nil},
		{"以 direct 终止", []map[string]any{node("a", "direct")}, map[string]string{"a": "warp"}, 1, nil},
		{"以 direct-fragment 终止", []map[string]any{node("a", "direct-fragment")}, map[string]string{"a": "warp"}, 1, nil},
		{"以 bypass 终止", []map[string]any{node("a", "p"), node("p", "bypass")}, map[string]string{"a": "p", "p": "warp"}, 2, nil},
		{"末端已是 warp", []map[string]any{node("a", "warp")}, map[string]string{"a": "warp"}, 0, nil},
		{"成环", []map[string]any{node("a", "b"), node("b", "a")}, nil, 0, build.ErrDetourCycle},
		{"悬空", []map[string]any{node("a", "ghost")}, nil, 0, build.ErrDetourDangling},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			ws, err := build.RedirectToWarp(c.in)
			if c.wantErr != nil {
				if !errors.Is(err, c.wantErr) || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
					t.Fatalf("err = %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			for _, e := range c.in {
				tag := e["tag"].(string)
				got, _ := e["detour"].(string)
				if got != c.want[tag] {
					t.Errorf("%s.detour = %q，期望 %q", tag, got, c.want[tag])
				}
			}
			if len(ws) != c.warnings {
				t.Errorf("warning %d 条，期望 %d: %v", len(ws), c.warnings, ws)
			}
			// 幂等：再来一遍，不改动、不再有 warning
			again, err := build.RedirectToWarp(c.in)
			if err != nil || len(again) != 0 {
				t.Errorf("第二次应无 warning、无错误: %v %v", again, err)
			}
			for _, e := range c.in {
				if got, _ := e["detour"].(string); got != c.want[e["tag"].(string)] {
					t.Errorf("第二次改动了 %s: %q", e["tag"], got)
				}
			}
		})
	}
}

// 订阅里叫 warp 的节点是保留 tag 冲突：被重命名，别的节点对它的 detour 同步改写；内部 warp 端点仍是唯一的 warp。
func TestSubscriptionNodeNamedWarpIsRenamed(t *testing.T) {
	for _, mode := range []string{proxyOverWarp, warpOverProxy} {
		o, p := warpOptions(mode)
		t.Run(p.Mode, func(t *testing.T) {
			raw, warnings, err := buildJSON(t, profileJSON(t, []map[string]any{node("warp", ""), node("node-a", "warp")}, nil), o)
			if err != nil {
				t.Fatal(err)
			}
			mustCheck(t, raw, p)
			c := decode(t, raw)
			if c.entity("warp (2)") == nil {
				t.Fatalf("订阅里的 warp 应被重命名为 warp (2)")
			}
			if c.entity("warp")["type"] != "wireguard" {
				t.Errorf("tag warp 必须是内部 WARP 端点: %v", c.entity("warp"))
			}
			renamed := false
			for _, w := range warnings {
				if strings.HasPrefix(w, "tag-renamed:") {
					renamed = true
				}
			}
			if !renamed {
				t.Errorf("缺少 tag-renamed warning: %v", warnings)
			}
			// 原来指向订阅节点 warp 的 detour 跟着改名：不能悄悄指到内部 WARP 端点上
			if p.Mode == options.WarpWarpOverProxy {
				if got := c.detour("node-a"); got != "warp (2)" {
					t.Errorf("node-a.detour = %q，应跟着改名为 warp (2)", got)
				}
			}
		})
	}
}

// 选项缺陷：启用 WARP 但没有 / 坏的 wireguard-config → build-failed:，不产出配置；噪声、warp2 只给警告。
func TestWarpOptionsErrorsAndWarnings(t *testing.T) {
	prof := profileJSON(t, []map[string]any{node("node-a", "")}, nil)
	for name, cfgJSON := range map[string]string{"空": "", "坏 JSON": "oops", "短密钥": `{"private-key":"AAAA","local-address-ipv4":"172.16.0.2","peer-public-key":"AAAA"}`} {
		t.Run(name, func(t *testing.T) {
			o, _ := warpOptions(proxyOverWarp)
			o.Warp.WireguardConfig = cfgJSON
			_, _, err := buildJSON(t, prof, o)
			if err == nil || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) || !strings.Contains(err.Error(), "warp-config-invalid:") {
				t.Fatalf("err = %v", err)
			}
		})
	}

	o, _ := warpOptions(warpOverProxy)
	o.Warp.Noise, o.Warp.NoiseMode = "5-9", "m1"
	o.Warp2.Enable = true
	_, ws, err := buildJSON(t, prof, o)
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(ws, "\n")
	for _, want := range []string{"warp-noise-unsupported: warp.noise=", "warp-noise-unsupported: warp.noise-mode=", "warp2-unsupported:"} {
		if !strings.Contains(joined, want) {
			t.Errorf("缺少 warning %q:\n%s", want, joined)
		}
	}
	// 默认噪声值不吵
	o2, _ := warpOptions(warpOverProxy)
	_, ws, err = buildJSON(t, prof, o2)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(strings.Join(ws, "\n"), "warp-noise-unsupported") {
		t.Errorf("默认噪声值不该产生警告: %v", ws)
	}
}

// WARP 未启用：配置里没有 warp 端点，业务出口 select，既有链不被改写。
func TestWarpDisabledLeavesGraphUntouched(t *testing.T) {
	raw, _, err := buildJSON(t, profileJSON(t, []map[string]any{node("node-a", "direct-fragment"), node("node-b", "")}, nil), gate.Option("O1"))
	if err != nil {
		t.Fatal(err)
	}
	c := decode(t, raw)
	if c.entity("warp") != nil {
		t.Error("未启用 WARP 不该有 warp 端点")
	}
	if c.Route.Final != "select" || c.dnsRemoteDetour() != "select" {
		t.Errorf("final = %q，dns-remote.detour = %q", c.Route.Final, c.dnsRemoteDetour())
	}
	if c.detour("node-a") != "direct-fragment" || c.detour("node-b") != "" {
		t.Errorf("既有链不该被改写: node-a=%q node-b=%q", c.detour("node-a"), c.detour("node-b"))
	}
}

// 用户规则里的 proxy 目标指向业务出口：warp_over_proxy 下是 warp，其余是 select；bypass 规则不受影响。
func TestProxyRuleTargetFollowsEgress(t *testing.T) {
	for mode, wantTarget := range map[string]string{warpOverProxy: "warp", proxyOverWarp: "select"} {
		o, _ := warpOptions(mode)
		o.Rules = []options.Rule{
			{Domains: "full:proxied.example.net", Outbound: options.TargetProxy},
			{Domains: "full:direct.example.net", Outbound: options.TargetBypass},
		}
		raw, _, err := buildJSON(t, profileJSON(t, []map[string]any{node("node-a", "")}, nil), o)
		if err != nil {
			t.Fatal(err)
		}
		c := decode(t, raw)
		got := map[string]any{}
		for _, r := range c.Route.Rules {
			if d, ok := r["domain"].([]any); ok && len(d) == 1 {
				got[d[0].(string)] = r["outbound"]
			}
		}
		if got["proxied.example.net"] != wantTarget || got["direct.example.net"] != "bypass" {
			t.Errorf("%s：规则目标 = %v，期望 proxy→%s、bypass→bypass", mode, got, wantTarget)
		}
	}
}

// WARP 对端写成域名时，它和节点的服务器域名一样要直连解析。
func TestWarpPeerDomainResolvedDirectly(t *testing.T) {
	o, _ := warpOptions(proxyOverWarp)
	o.Warp.CleanIP = "warp-entry.example.net"
	raw, _, err := buildJSON(t, profileJSON(t, []map[string]any{node("node-a", "")}, nil), o)
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		DNS struct {
			Rules []map[string]any `json:"rules"`
		} `json:"dns"`
	}
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, r := range c.DNS.Rules {
		if r["server"] == "dns-direct" {
			for _, d := range r["domain"].([]any) {
				if d == "warp-entry.example.net" {
					found = true
				}
			}
		}
	}
	if !found {
		t.Errorf("WARP 对端域名应在直连 DNS 规则里: %v", c.DNS.Rules)
	}
}

// 订阅自带直连类出站（custom-direct）经读时清洗：
//   - 无 WARP / warp_over_proxy：node-a 的 detour 被归一化为 direct，再因「空 direct 不能作 detour」去掉——链等价，合法；
//     读时清洗的重映射记 1 条 warning（detour-remapped）；
//   - proxy_over_warp：node-a.detour = warp，且恰好 1 条被改写链的 warning（仍是读时清洗的重映射，
//     链已终止于 warp，所以不会再记第二条 warp-chain-rewritten）。
//
// 注意计划 / 规格里写的是「node-a.detour == direct」：真实 Start 拒绝指向空 direct 的 detour，所以实际输出里没有这个字段。
func TestCustomDirectNormalization(t *testing.T) {
	prof := profileJSON(t, []map[string]any{
		node("node-a", "custom-direct"),
		{"type": "direct", "tag": "custom-direct"},
	}, nil)
	for _, tc := range []struct {
		name     string
		o        *options.Options
		wantA    string
		wantWarn int
	}{
		{"无 WARP", gate.Option("O1"), "", 1},
		{"warp_over_proxy", func() *options.Options { o, _ := warpOptions(warpOverProxy); return o }(), "", 1},
		{"proxy_over_warp", func() *options.Options { o, _ := warpOptions(proxyOverWarp); return o }(), "warp", 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw, warnings, err := buildJSON(t, prof, tc.o)
			if err != nil {
				t.Fatal(err)
			}
			c := decode(t, raw)
			if got := c.detour("node-a"); got != tc.wantA {
				t.Errorf("node-a.detour = %q，期望 %q", got, tc.wantA)
			}
			if c.entity("custom-direct") != nil {
				t.Error("订阅自带的直连类出站应被丢弃")
			}
			if n := len(rewriteWarnings(warnings)); n != tc.wantWarn {
				t.Errorf("改写 warning %d 条，期望 %d: %v", n, tc.wantWarn, warnings)
			}
			if p, on := build.PolicyFor(tc.o); on {
				mustCheck(t, raw, p)
			}
		})
	}
}

// 先 Parse 落成 detour: direct、再 BuildConfig，与直接 BuildConfig 旧文件结果一致（两条路径殊途同归，spec §6.3）。
func TestTwoStepAndDirectBuildAgree(t *testing.T) {
	legacy := profileJSON(t, []map[string]any{node("node-a", "custom-direct"), {"type": "direct", "tag": "custom-direct"}}, nil)
	parsed := profileJSON(t, []map[string]any{node("node-a", "direct")}, nil) // 新 Parse 的产物
	for _, mode := range []string{proxyOverWarp, warpOverProxy} {
		o, _ := warpOptions(mode)
		a, _, err := buildJSON(t, legacy, o)
		if err != nil {
			t.Fatal(err)
		}
		b, _, err := buildJSON(t, parsed, o)
		if err != nil {
			t.Fatal(err)
		}
		if string(a) != string(b) {
			t.Errorf("%s：两步与直接构建的配置不一致", mode)
		}
	}
}

// ---- 反例：故意把图弄坏，断言必须抓住（每条都指明路径） ----

func mutateConfig(t testing.TB, raw []byte, f func(c map[string]any)) []byte {
	t.Helper()
	var c map[string]any
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	f(c)
	out, err := json.Marshal(c)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func findIn(c map[string]any, key, tag string) map[string]any {
	for _, x := range c[key].([]any) {
		if m := x.(map[string]any); m["tag"] == tag {
			return m
		}
	}
	return nil
}

func TestWarpGraphCounterexamples(t *testing.T) {
	prof := profileJSON(t, []map[string]any{node("node-a", "direct-fragment"), node("node-b", "")}, nil)
	oUnder, pUnder := warpOptions(proxyOverWarp)
	oOver, pOver := warpOptions(warpOverProxy)
	under, _, err := buildJSON(t, prof, oUnder)
	if err != nil {
		t.Fatal(err)
	}
	over, _, err := buildJSON(t, prof, oOver)
	if err != nil {
		t.Fatal(err)
	}
	mustCheck(t, under, pUnder)
	mustCheck(t, over, pOver)

	t.Run("warp 混进 select 成员（两种模式都抓）", func(t *testing.T) {
		for _, tc := range []struct {
			raw []byte
			p   build.WarpPolicy
		}{{under, pUnder}, {over, pOver}} {
			bad := mutateConfig(t, tc.raw, func(c map[string]any) {
				sel := findIn(c, "outbounds", "select")
				sel["outbounds"] = append(sel["outbounds"].([]any), "warp")
			})
			mustViolate(t, bad, tc.p, "warp 不得是 select 的成员（路径：select -> warp")
		}
	})
	t.Run("proxy_over_warp 跳过 RedirectToWarp：node-a 仍以 direct-fragment 终止", func(t *testing.T) {
		bad := mutateConfig(t, under, func(c map[string]any) {
			findIn(c, "outbounds", "node-a")["detour"] = "direct-fragment"
		})
		mustViolate(t, bad, pUnder, "node-a -> direct-fragment")
	})
	t.Run("proxy_over_warp 的节点没有 detour（链根本没到 warp）", func(t *testing.T) {
		bad := mutateConfig(t, under, func(c map[string]any) { delete(findIn(c, "outbounds", "node-b"), "detour") })
		mustViolate(t, bad, pUnder, "成员 node-b 的拨号链未终止于 warp")
	})
	t.Run("proxy_over_warp 的 warp 带了 detour", func(t *testing.T) {
		bad := mutateConfig(t, under, func(c map[string]any) { findIn(c, "endpoints", "warp")["detour"] = "select" })
		mustViolate(t, bad, pUnder, "warp.detour")
	})
	t.Run("warp_over_proxy 的 route.final 回到 select（业务流量不经 warp）", func(t *testing.T) {
		bad := mutateConfig(t, over, func(c map[string]any) { c["route"].(map[string]any)["final"] = "select" })
		mustViolate(t, bad, pOver, "route.final=select 的第一跳应是 warp")
	})
	t.Run("warp_over_proxy 的 dns-remote 没走 warp", func(t *testing.T) {
		bad := mutateConfig(t, over, func(c map[string]any) {
			for _, s := range c["dns"].(map[string]any)["servers"].([]any) {
				if m := s.(map[string]any); m["tag"] == "dns-remote" {
					m["detour"] = "select"
				}
			}
		})
		mustViolate(t, bad, pOver, "dns-remote.detour=select")
	})
	t.Run("warp_over_proxy 的 warp 没有 detour select", func(t *testing.T) {
		bad := mutateConfig(t, over, func(c map[string]any) { delete(findIn(c, "endpoints", "warp"), "detour") })
		mustViolate(t, bad, pOver, "warp.detour")
	})
	t.Run("warp_over_proxy 错误地改写了载体链（应保持不变）", func(t *testing.T) {
		// 保持不变的断言：warp_over_proxy 下 node-a 的 detour 必须仍是订阅原样的 direct-fragment。
		if got := decode(t, over).detour("node-a"); got != "direct-fragment" {
			t.Fatalf("基线就不对: %q", got)
		}
		bad := decode(t, mutateConfig(t, over, func(c map[string]any) { findIn(c, "outbounds", "node-a")["detour"] = "warp" }))
		if bad.detour("node-a") == "direct-fragment" {
			t.Fatal("反例没有生效")
		}
		// 断言本身：错误改写后与订阅原样不符
		if bad.detour("node-a") == decode(t, over).detour("node-a") {
			t.Fatal("「保持不变」断言抓不住被改写的载体链")
		}
	})
	t.Run("detour 成环", func(t *testing.T) {
		bad := mutateConfig(t, under, func(c map[string]any) {
			findIn(c, "outbounds", "node-a")["detour"] = "node-b"
			findIn(c, "outbounds", "node-b")["detour"] = "node-a"
		})
		mustViolate(t, bad, pUnder, "detour 成环")
	})
}
