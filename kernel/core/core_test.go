package core_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/core"
	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func subscriptionFixture(name string) string {
	return filepath.Join("..", "internal", "subscription", "testdata", "subscriptions", name)
}

func legacyFixture(name string) string {
	return filepath.Join("..", "internal", "legacy", "testdata", "legacy", name)
}

// 两组选项：默认值，以及一组打开更多开关的组合（都是 Dart 侧会真实发来的键）。
var optionSets = map[string]string{
	"defaults": `{}`,
	"busy":     `{"mixed-port":2081,"enable-fake-dns":true,"enable-dns-routing":true,"bypass-lan":true,"ipv6-mode":"prefer_ipv6","remote-dns-address":"tcp://1.1.1.1","direct-dns-address":"223.5.5.5"}`,
}

// checkBuilt 对构建产出做与闸门一致的检查：不变量 + 主机适配副本过 CheckConfig；返回适配副本。
func checkBuilt(t *testing.T, content, optsJSON string) []byte {
	t.Helper()
	o, _, err := options.Decode([]byte(optsJSON))
	if err != nil {
		t.Fatal(err)
	}
	if vs := gate.CheckInvariants([]byte(content), o, build.AndroidEnv()); len(vs) != 0 {
		t.Fatalf("不变量违规: %v", vs)
	}
	adapted, _, err := gate.HostAdapt([]byte(content), gate.AdaptOptions{})
	if err != nil {
		t.Fatalf("HostAdapt: %v", err)
	}
	if err := gate.CheckConfig(adapted); err != nil {
		t.Fatalf("适配副本 CheckConfig: %v", err)
	}
	if err := core.CheckConfig(string(adapted)); err != nil {
		t.Fatalf("core.CheckConfig: %v", err)
	}
	return adapted
}

func TestVersions(t *testing.T) {
	if v := core.Version(); !strings.HasPrefix(v, "1.14") && v != "unknown" {
		t.Errorf("Version = %q", v)
	}
	if v := core.GoVersion(); !strings.HasPrefix(v, "go") {
		t.Errorf("GoVersion = %q", v)
	}
}

// Parse → BuildConfig → CheckConfig：各形态订阅（含旧 1.8 形态、仅端点、Clash）与两组选项。
func TestParseBuildCheck(t *testing.T) {
	for _, f := range []string{
		"singbox-full.json", "singbox-array.json", "singbox-single.json", "singbox-legacy18.json",
		"singbox-endpoint-only.json", "singbox-custom-direct.json", "clash-protocols.yaml",
	} {
		for oname, ojson := range optionSets {
			t.Run(f+"/"+oname, func(t *testing.T) {
				out := filepath.Join(t.TempDir(), "profile.json")
				if err := core.Parse(out, subscriptionFixture(f), false); err != nil {
					t.Fatalf("Parse: %v", err)
				}
				content, err := core.BuildConfig(out, ojson)
				if err != nil {
					t.Fatalf("BuildConfig: %v", err)
				}
				checkBuilt(t, content, ojson)
			})
		}
	}
}

// 升级前旧内核落盘的订阅（1.8 形态，没有经过新 Parse）直接喂 BuildConfig：读时清洗后照样构建成功。
// 唯一的例外是引用「被丢弃的 selector / block / dns 或从未存在的 tag」的那份：它必须被拒绝，而不是悄悄改道。
func TestBuildConfigReadsLegacyProfiles(t *testing.T) {
	files, err := filepath.Glob(legacyFixture("*.in.json"))
	if err != nil || len(files) == 0 {
		t.Fatalf("没有 legacy 夹具: %v", err)
	}
	for _, f := range files {
		name := strings.TrimSuffix(filepath.Base(f), ".in.json")
		t.Run(name, func(t *testing.T) {
			content, err := core.BuildConfig(f, `{}`)
			if name == "detour-not-remapped" {
				if err == nil || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
					t.Fatalf("悬空 detour 必须以 %s 拒绝，得到 %v", build.PrefixBuildFailed, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("BuildConfig: %v", err)
			}
			if name == "unknown-fields-preserved" {
				// 未知字段被清洗原样保留（不替订阅做主）；内核自己拒绝它，所以只断言「拒绝的原因就是那个字段」。
				adapted, _, err := gate.HostAdapt([]byte(content), gate.AdaptOptions{})
				if err != nil {
					t.Fatal(err)
				}
				if err := core.CheckConfig(string(adapted)); err == nil || !strings.Contains(err.Error(), "x_future_field") {
					t.Fatalf("CheckConfig 应因 x_future_field 拒绝，得到 %v", err)
				}
				return
			}
			checkBuilt(t, content, `{}`)
		})
	}
}

// Parse(Parse(x)) 与 BuildConfig 对已解析文件的重复读取结果一致（读时清洗幂等）。
func TestBuildConfigIsStableOnParsedProfile(t *testing.T) {
	dir := t.TempDir()
	p1, p2 := filepath.Join(dir, "p1.json"), filepath.Join(dir, "p2.json")
	if err := core.Parse(p1, subscriptionFixture("singbox-legacy18.json"), false); err != nil {
		t.Fatal(err)
	}
	if err := core.Parse(p2, p1, false); err != nil {
		t.Fatal(err)
	}
	a, err := core.BuildConfig(p1, `{}`)
	if err != nil {
		t.Fatal(err)
	}
	b, err := core.BuildConfig(p2, `{}`)
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatal("Parse(Parse(x)) 之后构建结果不同")
	}
}

func TestErrorPrefixes(t *testing.T) {
	dir := t.TempDir()
	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	ok := write("ok.json", `{"outbounds":[{"type":"shadowsocks","tag":"n1","server":"198.51.100.1","server_port":8388,"method":"aes-128-gcm","password":"x"}]}`)

	cases := []struct {
		name   string
		err    error
		prefix string
	}{
		{"Parse HTML", core.Parse(filepath.Join(dir, "o1"), write("page.html", "<html><body>forbidden</body></html>"), false), "format-unknown:"},
		{"Parse empty", core.Parse(filepath.Join(dir, "o2"), write("empty.txt", ""), false), "format-unknown:"},
		{"Parse missing input", core.Parse(filepath.Join(dir, "o3"), filepath.Join(dir, "nope"), false), "build-failed:"},
		{"Parse direct only", core.Parse(filepath.Join(dir, "o4"), write("direct.json", `{"outbounds":[{"type":"direct","tag":"d"}]}`), false), "no-outbounds:"},
		{"Parse bad link", core.Parse(filepath.Join(dir, "o5"), write("bad.txt", "vmess://not-base64-json\n"), false), "uri-invalid:"},
		{"Build missing profile", buildErr(filepath.Join(dir, "nope"), `{}`), "build-failed:"},
		{"Build bad profile", buildErr(write("junk.json", "not json"), `{}`), "build-failed:"},
		{"Build options not JSON", buildErr(ok, `not json`), "option-invalid:"},
		{"Build options empty", buildErr(ok, ``), "option-invalid:"},
		{"Build option out of range", buildErr(ok, `{"mixed-port":0}`), "option-invalid:"},
		{"Build wrong option type", buildErr(ok, `{"mixed-port":"abc"}`), "option-invalid:"},
		{"Build dangling detour", buildErr(write("ghost.json", `{"outbounds":[{"type":"shadowsocks","tag":"n1","server":"198.51.100.1","server_port":8388,"method":"aes-128-gcm","password":"x","detour":"ghost"}]}`), `{}`), "build-failed:"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.err == nil {
				t.Fatalf("期望以 %s 开头的错误，得到 nil", c.prefix)
			}
			if !strings.HasPrefix(c.err.Error(), c.prefix) {
				t.Fatalf("错误 %q 不以 %s 开头", c.err, c.prefix)
			}
		})
	}
}

func buildErr(profile, opts string) error {
	_, err := core.BuildConfig(profile, opts)
	return err
}

func TestSetupRejectsNil(t *testing.T) {
	if err := core.Setup(nil); err == nil {
		t.Fatal("nil SetupOptions 必须报错")
	}
}

func TestNewEngineRejectsNil(t *testing.T) {
	if _, err := core.NewEngine(nil, testHandler{}); err == nil || !strings.HasPrefix(err.Error(), "command-server:") {
		t.Fatalf("nil host: %v", err)
	}
	if _, err := core.NewEngine(newTestHost(), nil); err == nil || !strings.HasPrefix(err.Error(), "command-server:") {
		t.Fatalf("nil handler: %v", err)
	}
}
