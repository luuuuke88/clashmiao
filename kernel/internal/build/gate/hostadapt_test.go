package gate

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
)

// 「原始配置与适配副本的差异 == 白名单」：有 tun-in 的配置，差异只有删 tun-in、删 override_android_vpn、改写本地入站。
func TestHostAdaptDiffIsExactlyTheWhitelist(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O1", "P1", "O1"})
	adapted, ap, err := HostAdapt(raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	changes, err := Diff(raw, adapted)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, c := range changes {
		switch {
		case c.Path == "inbounds[]":
			got = append(got, c.Op+" inbounds["+asString(asMap(firstNonNil(c.Old, c.New))["tag"])+"]")
		default:
			got = append(got, c.Op+" "+c.Path)
		}
	}
	want := []string{
		"removed inbounds[tun-in]",
		"removed inbounds[mixed-in]", "added inbounds[mixed-in]",
		"removed inbounds[dns-in]", "added inbounds[dns-in]",
		"removed route.override_android_vpn",
	}
	if !sameSet(got, want) {
		t.Fatalf("适配差异与白名单不一致\n 实际: %v\n 期望: %v", got, want)
	}
	if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("CheckWhitelist: %v %v", err, bad)
	}
}

func firstNonNil(a, b any) any {
	if a != nil {
		return a
	}
	return b
}

func sameSet(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	m := map[string]int{}
	for _, s := range a {
		m[s]++
	}
	for _, s := range b {
		m[s]--
	}
	for _, n := range m {
		if n != 0 {
			return false
		}
	}
	return true
}

// 白名单之外的差异一律使测试失败：适配悄悄把真 bug 抹掉（或多做了别的）会被抓住。
func TestHostAdaptBeyondWhitelistIsRejected(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O1", "P1", "O1"})
	adapted, ap, err := HostAdapt(raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	tamper := []struct {
		name   string
		want   string
		mutate func(c map[string]any)
	}{
		{"改了 route.final", "route.final", func(c map[string]any) { asMap(c["route"])["final"] = "auto" }},
		{"删了一条路由规则", "route.rules[]", func(c map[string]any) {
			rt := asMap(c["route"])
			rt["rules"] = asSlice(rt["rules"])[1:]
		}},
		{"改了 DNS 服务器的 detour", "dns.servers[]", func(c map[string]any) {
			findOne(t, asMap(c["dns"])["servers"], "tag", "dns-remote")["detour"] = "direct"
		}},
		{"改了 mixed-in 的监听之外的字段", "超出白名单", func(c map[string]any) {
			findOne(t, c["inbounds"], "tag", "mixed-in")["sniff"] = true
		}},
		{"把 mixed-in 改成监听 0.0.0.0", "超出白名单", func(c map[string]any) {
			findOne(t, c["inbounds"], "tag", "mixed-in")["listen"] = "0.0.0.0"
		}},
		{"删了一个出站", "outbounds[]", func(c map[string]any) {
			c["outbounds"] = asSlice(c["outbounds"])[1:]
		}},
		{"注入了未授权的证书", "certificate", func(c map[string]any) {
			c["certificate"] = map[string]any{"store": "none"}
		}},
	}
	for _, tc := range tamper {
		t.Run(tc.name, func(t *testing.T) {
			var c map[string]any
			if err := json.Unmarshal(adapted, &c); err != nil {
				t.Fatal(err)
			}
			tc.mutate(c)
			bad, _ := json.Marshal(c)
			got, err := CheckWhitelist(raw, bad, ap)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(strings.Join(got, "\n"), tc.want) {
				t.Errorf("白名单没有拒绝这个改动，期望含 %q，实际 %v", tc.want, got)
			}
		})
	}
}

// 没有 tun-in 的配置（仅线路）：适配只改本地入站端口并删 override_android_vpn。
func TestHostAdaptLineOnly(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O2", "P1", "O2"})
	adapted, ap, err := HostAdapt(raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("%v %v", err, bad)
	}
}

// 适配遗漏（没删 tun-in）会被「适配副本里仍有 tun-in」抓住。
func TestHostAdaptMustRemoveTun(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O1", "P1", "O1"})
	bad, err := CheckWhitelist(raw, raw, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(bad, "\n"), "仍有 tun-in") {
		t.Errorf("没删 tun-in 的副本应被拒绝: %v", bad)
	}
}

// 带 fake DNS 的配置：dns-fake 服务器与引用它的规则一并被删，且仍在白名单内。
func TestHostAdaptRemovesFakeDNSAndItsRules(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O1", "P1", "O1"})
	withFake := mutate(t, raw, func(c map[string]any) {
		d := asMap(c["dns"])
		d["servers"] = append(asSlice(d["servers"]), map[string]any{"type": "fakeip", "tag": "dns-fake", "inet4_range": "198.18.0.0/15"})
		d["rules"] = append(asSlice(d["rules"]), map[string]any{"inbound": []any{"tun-in"}, "server": "dns-fake"})
	})
	adapted, ap, err := HostAdapt(withFake, AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := CheckWhitelist(withFake, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("%v %v", err, bad)
	}
	if strings.Contains(string(adapted), "dns-fake") {
		t.Fatal("适配副本里仍引用 dns-fake")
	}
}

// DoH 用例：注入测试 CA 在白名单内；注入内容与预期不符则被拒绝。
func TestHostAdaptInjectsCA(t *testing.T) {
	raw, _ := buildCase(t, Case{"P1-O1", "P1", "O1"})
	pem := "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n"
	adapted, ap, err := HostAdapt(raw, AdaptOptions{CAPEM: pem})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("%v %v", err, bad)
	}
	// 同一份副本，不声明要注入 CA：必须被拒绝。
	bad, _ := CheckWhitelist(raw, adapted, AdaptOptions{MixedPort: ap.MixedPort, DNSPort: ap.DNSPort})
	if !strings.Contains(strings.Join(bad, "\n"), "certificate") {
		t.Errorf("未声明的证书注入应被拒绝: %v", bad)
	}
	_ = build.AndroidEnv
}
