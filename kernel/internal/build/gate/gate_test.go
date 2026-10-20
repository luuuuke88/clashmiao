package gate

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func buildCase(t testing.TB, c Case) ([]byte, *options.Options) { return BuildCase(t, c) }

// 原始（Android）配置上的断言：黄金文件 + 不变量。
func TestMatrixGoldenAndInvariants(t *testing.T) {
	for _, c := range Matrix {
		t.Run(c.Name, func(t *testing.T) {
			raw, o := buildCase(t, c)
			Golden(t, c.Name, raw)
			if vs := CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
				t.Errorf("不变量违规:\n  %s", strings.Join(vs, "\n  "))
			}
		})
	}
}

// 构建器输出对同一输入是确定的（黄金文件稳定的前提）。
func TestBuildIsDeterministic(t *testing.T) {
	for _, c := range Matrix {
		a, _ := buildCase(t, c)
		b, _ := buildCase(t, c)
		if !bytes.Equal(a, b) {
			t.Errorf("%s: 两次构建输出不同", c.Name)
		}
	}
}

// 适配副本上的断言（不启动）：差异在白名单内，且 libbox.CheckConfig 放行。
func TestMatrixHostAdaptedConfigChecks(t *testing.T) {
	for _, c := range Matrix {
		t.Run(c.Name, func(t *testing.T) {
			raw, _ := buildCase(t, c)
			adapted, ap, err := HostAdapt(raw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
				t.Fatalf("适配差异超出白名单: %v %v", err, bad)
			}
			if err := CheckConfig(adapted); err != nil {
				t.Fatalf("CheckConfig(适配副本): %v", err)
			}
		})
	}
}

// 矩阵、黄金文件、README 三者保持一致：少一个都不行。
func TestMatrixMatchesGoldenFilesAndReadme(t *testing.T) {
	readme, err := os.ReadFile(filepath.Join(TestdataDir(), "README"))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{}
	for _, c := range Matrix {
		want[c.Name] = true
		if !strings.Contains(string(readme), "| "+c.Name+" |") {
			t.Errorf("testdata/README 的矩阵表里没有登记 %s", c.Name)
		}
	}
	for _, n := range GoldenNames(t) {
		if !want[n] {
			t.Errorf("黄金文件 %s.json 没有对应的矩阵格子（多余文件会让「逐字节比较」形同虚设）", n)
		}
	}
	for _, name := range ProfileNames(t) {
		_ = LoadProfile(t, name) // 每个 profile 夹具都必须能解析
	}
	for _, name := range OptionNames() {
		if err := Option(name).Validate(); err != nil {
			t.Errorf("选项夹具 %s 不合法: %v", name, err)
		}
	}
}

// 「仅线路」(O2) 的产出里没有 tun-in，也没有任何引用它的东西，并通过全部检查。
func TestLineOnlyHasNoTun(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O2", "P1", "O2"})
	if bytes.Contains(raw, []byte("tun-in")) {
		t.Fatalf("仅线路配置里不该出现 tun-in:\n%s", raw)
	}
	if bytes.Contains(raw, []byte(`"type": "tun"`)) {
		t.Fatalf("仅线路配置里不该有 tun 入站")
	}
	if vs := CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
		t.Fatalf("不变量违规: %v", vs)
	}
	var c map[string]any
	_ = json.Unmarshal(raw, &c)
	if _, has := newGraph(c).inbounds["mixed-in"]; !has {
		t.Fatal("仅线路仍需要 mixed-in")
	}
}

// ---- 反例：故意改坏，证明闸门不是摆设 ----

func mutate(t *testing.T, raw []byte, f func(c map[string]any)) []byte {
	t.Helper()
	var c map[string]any
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	f(c)
	out, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func findOne(t *testing.T, list any, key, val string) map[string]any {
	t.Helper()
	for _, e := range asSlice(list) {
		if m := asMap(e); asString(m[key]) == val {
			return m
		}
	}
	t.Fatalf("没找到 %s=%s", key, val)
	return nil
}

func wantViolation(t *testing.T, vs []string, substr string) {
	t.Helper()
	for _, v := range vs {
		if strings.Contains(v, substr) {
			return
		}
	}
	t.Errorf("不变量没有抓住这个坏配置：期望含 %q，实际 %v", substr, vs)
}

// 反例 1：DNS 服务器的 detour 指向空 direct。CheckConfig 放行，不变量必须抓住（真 Start 拒绝见 gate_norace_test.go）。
func TestCounterexampleDNSDetourToEmptyDirect(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O1", "P1", "O1"})
	bad := mutate(t, raw, func(c map[string]any) {
		findOne(t, asMap(c["dns"])["servers"], "tag", "dns-direct")["detour"] = "direct"
	})
	wantViolation(t, CheckInvariants(bad, o, build.AndroidEnv()), "指向空 direct")
	adapted, _, _ := HostAdapt(bad, AdaptOptions{})
	if err := CheckConfig(adapted); err != nil {
		t.Logf("注意：CheckConfig 也拒绝了这个坏配置: %v", err)
	}
}

// 反例 2：selector 的 default 不在成员里。
func TestCounterexampleSelectorDefaultNotMember(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O1", "P1", "O1"})
	bad := mutate(t, raw, func(c map[string]any) {
		findOne(t, c["outbounds"], "tag", "select")["default"] = "§default§"
	})
	wantViolation(t, CheckInvariants(bad, o, build.AndroidEnv()), "不在成员里")
}

// 反例 3：入站里残留 sniff 字段，被禁用键扫描抓住。
func TestCounterexampleSniffInboundField(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O1", "P1", "O1"})
	bad := mutate(t, raw, func(c map[string]any) {
		findOne(t, c["inbounds"], "tag", "mixed-in")["sniff"] = true
	})
	wantViolation(t, CheckInvariants(bad, o, build.AndroidEnv()), "禁用键 inbounds[].sniff")
}

// 反例 4：仅线路配置里残留 tun-in，被条件 tag 不变量抓住。
func TestCounterexampleTunInLineOnly(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O2", "P1", "O2"})
	bad := mutate(t, raw, func(c map[string]any) {
		c["inbounds"] = append(asSlice(c["inbounds"]), map[string]any{"type": "tun", "tag": "tun-in", "address": []any{"172.19.0.1/28"}})
	})
	wantViolation(t, CheckInvariants(bad, o, build.AndroidEnv()), "条件 tag tun-in 不该存在")
}

// 反例 5：非 Android 的 Env 却含 override_android_vpn，被条件不变量抓住。
func TestCounterexampleOverrideAndroidVPNOffAndroid(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O1", "P1", "O1"})
	wantViolation(t, CheckInvariants(raw, o, build.Env{GOOS: "linux", IPv6Supported: true}), "override_android_vpn")
}

// 额外的反例：每条不变量至少被一个坏配置触发，防止某条检查悄悄失效。
func TestMoreCounterexamples(t *testing.T) {
	raw, o := buildCase(t, Case{"P1-O1", "P1", "O1"})
	cases := []struct {
		name   string
		want   string
		mutate func(c map[string]any)
	}{
		{"缺必有出站", "缺少必有出站 bypass", func(c map[string]any) {
			var keep []any
			for _, e := range asSlice(c["outbounds"]) {
				if asString(asMap(e)["tag"]) != "bypass" {
					keep = append(keep, e)
				}
			}
			c["outbounds"] = keep
		}},
		{"成员不存在", "成员 \"ghost\" 不存在", func(c map[string]any) {
			g := findOne(t, c["outbounds"], "tag", "auto")
			g["outbounds"] = append(asSlice(g["outbounds"]), "ghost")
		}},
		{"detour 成环", "detour 成环", func(c map[string]any) {
			a := findOne(t, c["outbounds"], "tag", "香港01")
			a["detour"] = "direct-fragment"
			findOne(t, c["outbounds"], "tag", "direct-fragment")["detour"] = "香港01"
		}},
		{"dns.final 不对", "dns.final", func(c map[string]any) { asMap(c["dns"])["final"] = "dns-direct" }},
		{"route.final 不对", "route.final", func(c map[string]any) { asMap(c["route"])["final"] = "auto" }},
		{"sniff 在 hijack-dns 之后", "必须在 hijack-dns", func(c map[string]any) {
			r := asSlice(asMap(c["route"])["rules"])
			r[0], r[1] = r[1], r[0]
		}},
		{"warp 混进 select", "warp 不得是 select 的成员", func(c map[string]any) {
			g := findOne(t, c["outbounds"], "tag", "select")
			g["outbounds"] = append(asSlice(g["outbounds"]), "warp")
		}},
		{"DNS 旧 address 格式", "禁用键 dns.servers[].address", func(c map[string]any) {
			findOne(t, asMap(c["dns"])["servers"], "tag", "dns-direct")["address"] = "223.5.5.5"
		}},
		{"路由规则指向 dns-out", "dns-out", func(c map[string]any) {
			asMap(c["route"])["rules"] = append(asSlice(asMap(c["route"])["rules"]), map[string]any{"protocol": []any{"dns"}, "outbound": "dns-out"})
		}},
		{"含 clash_api", "禁用键 experimental.clash_api", func(c map[string]any) {
			asMap(c["experimental"])["clash_api"] = map[string]any{"external_controller": "127.0.0.1:9090"}
		}},
		{"缺 dns-in", "条件 tag dns-in 应当存在", func(c map[string]any) {
			var keep []any
			for _, e := range asSlice(c["inbounds"]) {
				if asString(asMap(e)["tag"]) != "dns-in" {
					keep = append(keep, e)
				}
			}
			c["inbounds"] = keep
		}},
		{"fake DNS 服务器无引用方却留着", "条件 tag dns-fake 不该存在", func(c map[string]any) {
			d := asMap(c["dns"])
			d["servers"] = append(asSlice(d["servers"]), map[string]any{"type": "fakeip", "tag": "dns-fake", "inet4_range": "198.18.0.0/15"})
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			bad := mutate(t, raw, tc.mutate)
			wantViolation(t, CheckInvariants(bad, o, build.AndroidEnv()), tc.want)
		})
	}
}
