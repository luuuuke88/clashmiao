package gate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

func sharedProfile(t testing.TB, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(TestdataDir(), "..", "..", "..", "testdata", "shared", "profiles", name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// sharedProfileNames 是与 Dart 共享的四个端点形态夹具。
var sharedProfileNames = []string{"endpoint-only", "mixed", "endpoint-default", "groups-with-endpoint"}

func toBuildProfile(p subscription.Profile) build.Profile {
	return build.Profile{Outbounds: p.Outbounds, Endpoints: p.Endpoints}
}

// hideInfoNode 模拟 Dart 侧的隐藏：把订阅信息节点改名加上 §hide§（同时改写引用它的地方）。
func hideInfoNode(p subscription.Profile, old string) subscription.Profile {
	nt := old + " §hide§"
	for _, o := range p.Outbounds {
		if o["tag"] == old {
			o["tag"] = nt
		}
		if o["detour"] == old {
			o["detour"] = nt
		}
	}
	return p
}

// 端点四形态：Parse → BuildConfig → 不变量 → 适配副本 CheckConfig 全通过（真 Start 见 subscription_norace_test.go）。
func TestSharedProfilesParseBuildCheck(t *testing.T) {
	for _, name := range sharedProfileNames {
		t.Run(name, func(t *testing.T) {
			p, _, err := subscription.Parse(sharedProfile(t, name))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			o := Option("O1")
			raw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			if vs := CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
				t.Errorf("不变量违规: %v", vs)
			}
			adapted, ap, err := HostAdapt(raw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
				t.Fatalf("%v %v", err, bad)
			}
			if err := CheckConfig(adapted); err != nil {
				t.Fatalf("CheckConfig: %v", err)
			}
		})
	}
}

// groups-with-endpoint：订阅自带的 selector 含 auto、端点成员与（被隐藏的）信息节点引用，构建器丢弃它并重建，
// 不因悬空引用失败；隐藏的信息节点不进 select / auto，端点在里面。
func TestGroupsWithEndpointRebuilt(t *testing.T) {
	p, _, err := subscription.Parse(sharedProfile(t, "groups-with-endpoint"))
	if err != nil {
		t.Fatal(err)
	}
	if p.NodeCount() != 3 {
		t.Fatalf("节点数 = %d（2 出站 + 1 端点，分组不计）", p.NodeCount())
	}
	for _, o := range p.Outbounds {
		if o["type"] == "selector" || o["type"] == "urltest" {
			t.Fatalf("Parse 应丢弃订阅自带的分组: %v", o["tag"])
		}
	}
	p = hideInfoNode(p, "剩余流量：100 GB")
	raw, _, err := build.Build(toBuildProfile(p), Option("O1"), build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	g := newGraphFromRaw(t, raw)
	sel := strings.Join(toStrings(g.nodes["select"]["outbounds"]), ",")
	if sel != "auto,香港01,wg-hk" {
		t.Errorf("select 成员 = %s（端点在，隐藏的信息节点不在）", sel)
	}
	if auto := strings.Join(toStrings(g.nodes["auto"]["outbounds"]), ","); auto != "香港01,wg-hk" {
		t.Errorf("auto 成员 = %s", auto)
	}
	if _, ok := g.nodes["剩余流量：100 GB §hide§"]; !ok {
		t.Error("隐藏的节点仍应作为出站存在")
	}
}

func toStrings(x any) []string { return strList(x) }

// 订阅文件走 Parse → Build 后选择组默认值正确：标在端点上的 §default§ 取端点的真实 tag。
func TestEndpointDefaultMarkerInBuiltConfig(t *testing.T) {
	p, _, err := subscription.Parse(sharedProfile(t, "endpoint-default"))
	if err != nil {
		t.Fatal(err)
	}
	raw, _, err := build.Build(toBuildProfile(p), Option("O1"), build.AndroidEnv())
	if err != nil {
		t.Fatal(err)
	}
	g := newGraphFromRaw(t, raw)
	if def := g.nodes["select"]["default"]; def != "wg-sg§default§" {
		t.Errorf("select.default = %v", def)
	}
}

func newGraphFromRaw(t testing.TB, raw []byte) *graph {
	t.Helper()
	var c obj
	if err := jsonUnmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	return newGraph(c)
}

// 订阅解析的各种合成夹具经 Parse → BuildConfig 后都能过不变量与 libbox.CheckConfig：
// 证明 Clash 转换库的输出、旧形态清洗的输出与构建器的装配在 1.14 schema 下是自洽的，
// 且 node-a → custom-direct 经 Parse 后不悬空。
func TestParsedSubscriptionFixturesBuildAndCheck(t *testing.T) {
	dir := filepath.Join(TestdataDir(), "..", "..", "subscription", "testdata", "subscriptions")
	for _, name := range []string{"clash-protocols.yaml", "clash-anchors.yaml", "singbox-full.json", "singbox-array.json",
		"singbox-single.json", "singbox-legacy18.json", "singbox-custom-direct.json", "singbox-comments.json", "singbox-endpoint-only.json"} {
		t.Run(name, func(t *testing.T) {
			in, err := os.ReadFile(filepath.Join(dir, name))
			if err != nil {
				t.Fatal(err)
			}
			p, _, err := subscription.Parse(in)
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			o := Option("O1")
			raw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			if vs := CheckInvariants(raw, o, build.AndroidEnv()); len(vs) != 0 {
				t.Errorf("不变量违规: %v", vs)
			}
			adapted, ap, err := HostAdapt(raw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			if bad, err := CheckWhitelist(raw, adapted, ap); err != nil || len(bad) != 0 {
				t.Fatalf("%v %v", err, bad)
			}
			if err := CheckConfig(adapted); err != nil {
				t.Fatalf("CheckConfig: %v", err)
			}
		})
	}
}
