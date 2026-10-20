package build_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func routeOf(t testing.TB, o *options.Options) (*cfg.Route, []string) {
	t.Helper()
	c, w := buildCfg(t, gate.LoadProfile(t, "P1"), o)
	return c.Route, w
}

// 规则顺序固定。
func TestRouteRuleOrder(t *testing.T) {
	o := gate.Option("O3") // bypass-lan 开、有四条用户规则
	o.ResolveDestination = true
	r, _ := routeOf(t, o)
	kind := func(x cfg.RouteRule) string {
		switch {
		case x.Action == "sniff":
			return "sniff"
		case x.Action == "resolve":
			return "resolve"
		case x.Action == "hijack-dns" && len(x.Protocol) > 0:
			return "hijack:protocol"
		case x.Action == "hijack-dns" && len(x.Inbound) > 0:
			return "hijack:dns-in"
		case x.Action == "hijack-dns" && len(x.Port) > 0:
			return "hijack:port53"
		case x.IPIsPrivate:
			return "bypass-lan"
		default:
			return "user"
		}
	}
	var got []string
	for _, x := range r.Rules {
		got = append(got, kind(x))
	}
	want := "sniff,resolve,hijack:protocol,hijack:dns-in,hijack:port53,bypass-lan,user,user,user,user"
	if strings.Join(got, ",") != want {
		t.Fatalf("规则顺序\n got  %s\n want %s", strings.Join(got, ","), want)
	}
}

// 没有 dns-in（local-dns-port=0）就不生成引用它的规则；resolve / bypass-lan 关闭时不出现。
func TestRouteConditionalRules(t *testing.T) {
	o := gate.Option("O1")
	o.LocalDNSPort = 0
	r, _ := routeOf(t, o)
	for _, x := range r.Rules {
		if len(x.Inbound) > 0 {
			t.Errorf("没有 dns-in 就不该有引用 inbound 的规则: %+v", x)
		}
		if x.Action == "resolve" || x.IPIsPrivate {
			t.Errorf("默认选项不该有 resolve / bypass-lan: %+v", x)
		}
	}
	if len(r.Rules) != 3 { // sniff + protocol dns + port 53
		t.Errorf("规则数 = %d，期望 3", len(r.Rules))
	}
}

func TestRouteBypassLANTwoStates(t *testing.T) {
	has := func(o *options.Options) bool {
		r, _ := routeOf(t, o)
		for _, x := range r.Rules {
			if x.IPIsPrivate {
				if x.Action != "route" || x.Outbound != "bypass" {
					t.Errorf("bypass-lan 应路由到 bypass: %+v", x)
				}
				return true
			}
		}
		return false
	}
	o := gate.Option("O1")
	if has(o) {
		t.Error("关闭 bypass-lan 时不该有 ip_is_private 规则")
	}
	o.BypassLAN = true
	if !has(o) {
		t.Error("开启 bypass-lan 时应有 ip_is_private 规则")
	}
}

func TestRouteResolveDestinationTwoStates(t *testing.T) {
	count := func(o *options.Options) (n int, strategy string, sniffIdx, resolveIdx int) {
		r, _ := routeOf(t, o)
		sniffIdx, resolveIdx = -1, -1
		for i, x := range r.Rules {
			if x.Action == "sniff" {
				sniffIdx = i
			}
			if x.Action == "resolve" {
				n++
				strategy, resolveIdx = x.Strategy, i
			}
		}
		return
	}
	o := gate.Option("O1")
	if n, _, _, _ := count(o); n != 0 {
		t.Error("默认不该有 resolve")
	}
	o.ResolveDestination, o.IPv6Mode = true, "prefer_ipv6"
	n, strategy, sniffIdx, resolveIdx := count(o)
	if n != 1 || strategy != "prefer_ipv6" || resolveIdx != sniffIdx+1 {
		t.Errorf("resolve 应紧跟 sniff 且 strategy 取 ipv6-mode: n=%d strategy=%q sniff=%d resolve=%d", n, strategy, sniffIdx, resolveIdx)
	}
}

// 用户规则表驱动：每种前缀 / 目标一行。
func TestRouteUserRules(t *testing.T) {
	cases := []struct {
		name string
		rule options.Rule
		want cfg.RouteRule
	}{
		{"后缀（无前缀）", options.Rule{Domains: "Example.COM", Outbound: "bypass"},
			cfg.RouteRule{DomainSuffix: []string{"example.com"}, Action: "route", Outbound: "bypass"}},
		{"domain: 后缀", options.Rule{Domains: "domain:example.com", Outbound: "bypass"},
			cfg.RouteRule{DomainSuffix: []string{"example.com"}, Action: "route", Outbound: "bypass"}},
		{"full: 精确", options.Rule{Domains: "full:a.example.com", Outbound: "bypass"},
			cfg.RouteRule{Domain: []string{"a.example.com"}, Action: "route", Outbound: "bypass"}},
		{"regexp: 正则（大小写保留）", options.Rule{Domains: `regexp:^Ad\d+\.example\.com$`, Outbound: "block"},
			cfg.RouteRule{DomainRegex: []string{`^Ad\d+\.example\.com$`}, Action: "reject"}},
		{"keyword:", options.Rule{Domains: "keyword:tracker", Outbound: "block"},
			cfg.RouteRule{DomainKeyword: []string{"tracker"}, Action: "reject"}},
		{"多个域名混合", options.Rule{Domains: "full:a.com,domain:b.com,keyword:c", Outbound: "bypass"},
			cfg.RouteRule{Domain: []string{"a.com"}, DomainSuffix: []string{"b.com"}, DomainKeyword: []string{"c"}, Action: "route", Outbound: "bypass"}},
		{"IP 段与单 IP", options.Rule{IP: "10.0.0.0/8, 192.0.2.7", Outbound: "bypass"},
			cfg.RouteRule{IPCIDR: []string{"10.0.0.0/8", "192.0.2.7/32"}, Action: "route", Outbound: "bypass"}},
		{"IPv6 段", options.Rule{IP: "2001:db8::/32", Outbound: "bypass"},
			cfg.RouteRule{IPCIDR: []string{"2001:db8::/32"}, Action: "route", Outbound: "bypass"}},
		{"端口与端口段", options.Rule{Port: "443,8000:8100", Outbound: "bypass"},
			cfg.RouteRule{Port: []uint16{443}, PortRange: []string{"8000:8100"}, Action: "route", Outbound: "bypass"}},
		{"网络", options.Rule{Network: "udp", Domains: "domain:quic.example.com", Outbound: "bypass"},
			cfg.RouteRule{DomainSuffix: []string{"quic.example.com"}, Network: []string{"udp"}, Action: "route", Outbound: "bypass"}},
		{"协议", options.Rule{Protocol: "bittorrent", Outbound: "bypass"},
			cfg.RouteRule{Protocol: []string{"bittorrent"}, Action: "route", Outbound: "bypass"}},
		{"proxy 目标走业务出口", options.Rule{Domains: "domain:proxied.example.com", Outbound: "proxy"},
			cfg.RouteRule{DomainSuffix: []string{"proxied.example.com"}, Action: "route", Outbound: "select"}},
		{"空目标按 proxy", options.Rule{Domains: "domain:proxied.example.com"},
			cfg.RouteRule{DomainSuffix: []string{"proxied.example.com"}, Action: "route", Outbound: "select"}},
		{"去重保序", options.Rule{Domains: "domain:b.com,domain:a.com,domain:b.com", Outbound: "bypass"},
			cfg.RouteRule{DomainSuffix: []string{"b.com", "a.com"}, Action: "route", Outbound: "bypass"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			o := gate.Option("O1")
			o.Rules = []options.Rule{tc.rule}
			r, w := routeOf(t, o)
			if len(w) != 0 {
				t.Errorf("不该有警告: %v", w)
			}
			got := r.Rules[len(r.Rules)-1] // 用户规则在最后
			gj, _ := json.Marshal(got)
			wj, _ := json.Marshal(tc.want)
			if string(gj) != string(wj) {
				t.Errorf("规则\n got  %s\n want %s", gj, wj)
			}
		})
	}
}

// final 与 proxy 规则的目标取同一个 egress（这里只有 select；warp_over_proxy 由 U13 注入同一个变量）。
func TestRouteFinalAndProxyTargetShareEgress(t *testing.T) {
	o := gate.Option("O1")
	o.Rules = []options.Rule{{Domains: "domain:p.example.com", Outbound: "proxy"}}
	r, _ := routeOf(t, o)
	last := r.Rules[len(r.Rules)-1]
	if last.Outbound != r.Final {
		t.Errorf("proxy 规则目标 %q 与 final %q 应相同", last.Outbound, r.Final)
	}
}

// geoip: / geosite: 在选项层已被拒，构建器遇到同样报错（不静默忽略）。
func TestRouteRejectsGeoRules(t *testing.T) {
	for _, rule := range []options.Rule{{Domains: "geosite:cn"}, {IP: "geoip:cn"}, {Domains: "geoip:cn"}} {
		o := gate.Option("O1")
		o.Rules = []options.Rule{rule}
		if err := o.Validate(); err == nil {
			t.Errorf("选项层应拒绝 %+v", rule)
		}
		_, _, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv())
		if err == nil || !options.IsOptionError(err) || !strings.Contains(err.Error(), "rules[0]") {
			t.Errorf("构建器应以 option-invalid 拒绝 %+v，实际 %v", rule, err)
		}
	}
}

// 没有匹配项的规则会匹配一切：丢弃并给警告，而不是悄悄把全部流量改道。
func TestRouteEmptyRuleIsDroppedWithWarning(t *testing.T) {
	o := gate.Option("O1")
	o.Rules = []options.Rule{{Outbound: "bypass"}, {Domains: "domain:ok.example.com", Outbound: "bypass"}}
	r, w := routeOf(t, o)
	if len(w) != 1 || !strings.HasPrefix(w[0], "rule-empty:") || !strings.Contains(w[0], "rules[0]") {
		t.Errorf("warnings = %v", w)
	}
	for _, x := range r.Rules {
		if x.Action == "route" && x.Outbound == "bypass" && len(x.Domain)+len(x.DomainSuffix)+len(x.IPCIDR) == 0 {
			t.Errorf("无匹配项的规则不该进配置: %+v", x)
		}
	}
}

// block-ads：不生成任何规则集（不引用远程资源），只给警告。
func TestRouteBlockAdsOnlyWarns(t *testing.T) {
	o := gate.Option("O9")
	raw, w, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv())
	if err != nil {
		t.Fatal(err)
	}
	if len(w) != 1 || !strings.HasPrefix(w[0], "block-ads-unsupported:") {
		t.Errorf("warnings = %v", w)
	}
	if strings.Contains(string(raw), "rule_set") || strings.Contains(string(raw), "download_detour") || strings.Contains(string(raw), ".srs") {
		t.Errorf("block-ads 不该生成规则集或远程引用:\n%s", raw)
	}
}

// 反例：把 sniff 挪到 hijack-dns 之后，不变量抓住。
func TestRouteCounterexampleSniffAfterHijack(t *testing.T) {
	raw, o := gate.BuildCase(t, gate.Case{Name: "x", Profile: "P1", Option: "O1"})
	var c map[string]any
	_ = json.Unmarshal(raw, &c)
	rules := c["route"].(map[string]any)["rules"].([]any)
	rules[0], rules[1] = rules[1], rules[0]
	bad, _ := json.Marshal(c)
	found := false
	for _, v := range gate.CheckInvariants(bad, o, build.AndroidEnv()) {
		if strings.Contains(v, "必须在 hijack-dns") {
			found = true
		}
	}
	if !found {
		t.Error("不变量应抓住 sniff 在 hijack-dns 之后")
	}
}

// 智能分流的全量清单（Dart 侧注入的 rules）：生成的配置通过 CheckConfig；耗时与大小记录在日志里。
func TestRouteCNDirectFullRulesPassCheckConfig(t *testing.T) {
	o := cnDirectOptions(t)
	start := time.Now()
	raw, w, err := build.Build(gate.LoadProfile(t, "P1"), o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	buildTime := time.Since(start)
	if len(w) != 0 {
		t.Errorf("全量清单不该有警告: %v", w)
	}
	adapted, ap, err := gate.HostAdapt(raw, gate.AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := gate.CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("%v %v", err, bad)
	}
	start = time.Now()
	if err := gate.CheckConfig(adapted); err != nil {
		t.Fatalf("CheckConfig: %v", err)
	}
	t.Logf("全量清单：配置 %d KiB，构建 %v，CheckConfig %v", len(raw)/1024, buildTime.Round(time.Millisecond), time.Since(start).Round(time.Millisecond))
	if vs := gate.CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
		t.Errorf("不变量违规: %v", vs)
	}
}

func cnDirectOptions(t testing.TB) *options.Options {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(gate.TestdataDir(), "rules", "cn-direct.json"))
	if err != nil {
		t.Fatal(err)
	}
	var f struct {
		Rules []options.Rule `json:"rules"`
	}
	if err := json.Unmarshal(b, &f); err != nil || len(f.Rules) != 2 {
		t.Fatalf("cn-direct.json 不是预期形态: %v", err)
	}
	o := gate.Option("O1")
	o.Rules = f.Rules
	o.EnableDNSRouting = true
	if err := o.Validate(); err != nil {
		t.Fatal(err)
	}
	return o
}
