package build_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 跨语言契约（构建器一侧）：Dart 的 RuntimeConfigBuilder 对 profile 夹具 P1–P8 构建出的
// runtime-config.json（kernel/testdata/dart/runtime-config-*.json，由 Dart 测试生成），搭配 Dart 的
// getDefaultConfigOptions 产出的选项夹具（kernel/testdata/options/*.json），整份喂给 BuildJSON：
// 构建通过、不变量与禁用键扫描为零、宿主适配副本只改白名单字段并通过 CheckConfig；
// 真 Start 见 dart_profiles_norace_test.go。
var dartPairs = []struct{ profile, option string }{
	{"P1", "default"},
	{"P2", "default"},
	{"P2-mux", "default"},
	{"P3", "default"},
	{"P4a", "default"}, // 端点独占
	{"P4b", "default"}, // 端点与出站混合
	{"P4c", "default"}, // 端点带 §default§
	{"P5", "default"},
	{"P6", "default"},
	{"P7", "default"}, // 旧 1.8 形态：读时清洗
	{"P8", "default"},
	{"P2-mux", "mux-fragment"},
	{"P2", "fakedns-dnsrouting-bypasslan"},
	{"P4a", "line-only-global"},
	{"P1", "vpn-smart"}, // 智能分流的全量清单
	{"P1", "warp-proxy-over-warp"},
	{"P4b", "warp-warp-over-proxy"},
	{"P8", "warp-proxy-over-warp"},
	{"P2", "persisted-hidden-options"}, // 界面已隐藏、存档里仍带着的值
	{"P2", "dns-remote-override"},
}

func dartTestdata(parts ...string) string {
	return filepath.Join(append([]string{gate.TestdataDir(), "..", "..", "..", "testdata"}, parts...)...)
}

func loadDartOptions(t testing.TB, name string) *options.Options {
	t.Helper()
	raw, err := os.ReadFile(dartTestdata("options", name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	o, warns, err := options.Decode(raw)
	if err != nil {
		t.Fatalf("%s: Decode: %v", name, err)
	}
	for _, w := range warns {
		t.Errorf("%s: Dart 选项夹具带警告 %s: %s", name, w.Code, w.Message)
	}
	if err := o.Validate(); err != nil {
		t.Fatalf("%s: Validate: %v", name, err)
	}
	return o
}

func loadDartRuntimeConfig(t testing.TB, name string) []byte {
	t.Helper()
	raw, err := os.ReadFile(dartTestdata("dart", "runtime-config-"+name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// buildDartPair 构建一格并做不依赖真启动的全部检查，返回适配副本。
func buildDartPair(t *testing.T, profile, option string) (adapted []byte) {
	t.Helper()
	rc := loadDartRuntimeConfig(t, profile)
	o := loadDartOptions(t, option)
	raw, warnings, err := build.BuildJSON(rc, o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("BuildJSON(%s × %s): %v", profile, option, err)
	}
	for _, w := range warnings {
		t.Logf("警告: %s", w)
	}
	if vs := gate.CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
		t.Errorf("不变量违规（含禁用键扫描）: %v", vs)
	}
	adapted, ap, err := gate.HostAdapt(raw, gate.AdaptOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if bad, err := gate.CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
		t.Fatalf("适配副本改了白名单之外的字段: %v %v", err, bad)
	}
	if err := gate.CheckConfig(adapted); err != nil {
		t.Fatalf("CheckConfig(%s × %s): %v", profile, option, err)
	}
	return adapted
}

func TestDartRuntimeConfigsBuildAndCheck(t *testing.T) {
	for _, p := range dartPairs {
		t.Run(p.profile+"×"+p.option, func(t *testing.T) { buildDartPair(t, p.profile, p.option) })
	}
}

// 夹具目录与矩阵一致：Dart 新导出一个 runtime-config，这里必须有对应的格子（否则它没被任何测试用到）。
func TestDartRuntimeConfigFixturesAllCovered(t *testing.T) {
	files, err := filepath.Glob(dartTestdata("dart", "runtime-config-*.json"))
	if err != nil || len(files) < 9 {
		t.Fatalf("Dart runtime-config 夹具太少（%d，err=%v）", len(files), err)
	}
	covered := map[string]bool{}
	for _, p := range dartPairs {
		covered[p.profile] = true
	}
	for _, f := range files {
		name := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(f), "runtime-config-"), ".json")
		if !covered[name] {
			t.Errorf("夹具 %s 没有任何矩阵格子使用", filepath.Base(f))
		}
	}
	for name := range covered {
		if _, err := os.Stat(dartTestdata("dart", "runtime-config-"+name+".json")); err != nil {
			t.Errorf("矩阵用到的夹具 %s 不存在: %v", name, err)
		}
	}
}

// Dart 产出的订阅里，WireGuard 端点三形态都保持端点身份（不被 Dart 侧的任何改写弄丢）。
func TestDartRuntimeConfigKeepsEndpoints(t *testing.T) {
	for _, name := range []string{"P4a", "P4b", "P4c"} {
		rc := string(loadDartRuntimeConfig(t, name))
		if !strings.Contains(rc, `"endpoints"`) {
			t.Errorf("%s: Dart 产出的 runtime-config 丢了 endpoints", name)
		}
	}
}
