package legacy

import (
	"bytes"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "重写 testdata/legacy/*.out.json（有意的改动要在评审里看 diff）")

type doc struct {
	Comment   string           `json:"_comment,omitempty"`
	Outbounds []map[string]any `json:"outbounds"`
	Endpoints []map[string]any `json:"endpoints,omitempty"`
}

func readDoc(t *testing.T, path string) doc {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var d doc
	if err := json.Unmarshal(raw, &d); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	return d
}

func marshal(t *testing.T, d doc) []byte {
	t.Helper()
	b, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	return append(b, '\n')
}

func clean(d doc, target string) Result {
	return Clean(d.Outbounds, d.Endpoints, CleanOptions{RemapTarget: target})
}

func inFiles(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob("testdata/legacy/*.in.json")
	if err != nil || len(files) == 0 {
		t.Fatalf("没有夹具: %v", err)
	}
	sort.Strings(files)
	return files
}

// 每条清洗规则一对 in / out 黄金文件。
func TestCleanGolden(t *testing.T) {
	for _, in := range inFiles(t) {
		name := strings.TrimSuffix(filepath.Base(in), ".in.json")
		t.Run(name, func(t *testing.T) {
			res := clean(readDoc(t, in), "direct")
			got := marshal(t, doc{Outbounds: res.Outbounds, Endpoints: res.Endpoints})
			outPath := strings.TrimSuffix(in, ".in.json") + ".out.json"
			if *update {
				if err := os.WriteFile(outPath, got, 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(outPath)
			if err != nil {
				t.Fatalf("缺黄金文件（-update 生成并评审）: %v", err)
			}
			if !bytes.Equal(want, got) {
				t.Errorf("与黄金文件不一致\n--- 黄金 ---\n%s\n--- 实际 ---\n%s", want, got)
			}
		})
	}
}

// 幂等：输出再喂 Clean，结果不变，且不再有记账 / 重映射 / 警告。
func TestCleanIsIdempotent(t *testing.T) {
	for _, in := range inFiles(t) {
		name := strings.TrimSuffix(filepath.Base(in), ".in.json")
		t.Run(name, func(t *testing.T) {
			for _, target := range []string{"direct", "warp"} {
				first := clean(readDoc(t, in), target)
				second := Clean(first.Outbounds, first.Endpoints, CleanOptions{RemapTarget: target})
				if !reflect.DeepEqual(first.Outbounds, second.Outbounds) || !reflect.DeepEqual(first.Endpoints, second.Endpoints) {
					t.Errorf("target=%s 不幂等:\n%s\n%s", target, mustJSON(first), mustJSON(second))
				}
				if len(second.Removed) != 0 || len(second.Remapped) != 0 || len(second.Warnings) != 0 {
					t.Errorf("target=%s 第二遍不该再有记账 / 重映射: %+v", target, second)
				}
			}
		})
	}
}

func mustJSON(v any) string { b, _ := json.Marshal(v); return string(b) }

// 输入不被修改。
func TestCleanDoesNotMutateInput(t *testing.T) {
	for _, in := range inFiles(t) {
		d := readDoc(t, in)
		before := mustJSON(d)
		_ = clean(d, "warp")
		if after := mustJSON(d); after != before {
			t.Errorf("%s: 输入被修改", in)
		}
	}
}

func find(list []map[string]any, tag string) map[string]any {
	for _, m := range list {
		if m["tag"] == tag {
			return m
		}
	}
	return nil
}

// wireguard 出站 → 端点：字段逐项断言。
func TestWireguardOutboundBecomesEndpoint(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/wireguard-full.in.json"), "direct")
	if find(res.Outbounds, "wg-2") != nil {
		t.Fatal("wireguard 不该留在 outbounds 里")
	}
	ep := find(res.Endpoints, "wg-2")
	if ep == nil {
		t.Fatal("没有生成端点 wg-2")
	}
	checks := map[string]any{
		"type":    "wireguard",
		"tag":     "wg-2",
		"address": []any{"10.9.0.2/32", "fd00::2/128"},
		"mtu":     float64(1280),
		"system":  false,
		"name":    "wg0",
		"workers": float64(2),
		"detour":  "carrier",
	}
	for k, want := range checks {
		if !reflect.DeepEqual(ep[k], want) {
			t.Errorf("端点 %s = %v，期望 %v", k, ep[k], want)
		}
	}
	if ep["private_key"] != "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=" {
		t.Errorf("private_key 应原样保留: %v", ep["private_key"])
	}
	if ep["tcp_fast_open"] != true {
		t.Errorf("拨号字段应原样保留: %v", ep)
	}
	for _, gone := range []string{"server", "server_port", "local_address", "peer_public_key", "pre_shared_key", "reserved", "allowed_ips", "system_interface", "interface_name"} {
		if _, ok := ep[gone]; ok {
			t.Errorf("端点顶层不该留着旧字段 %s", gone)
		}
	}
	peers, _ := ep["peers"].([]any)
	if len(peers) != 1 {
		t.Fatalf("peers = %v", ep["peers"])
	}
	p := peers[0].(map[string]any)
	wantPeer := map[string]any{
		"address":        "198.51.100.7",
		"port":           float64(2408),
		"public_key":     "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=",
		"pre_shared_key": "QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8=",
		"reserved":       []any{float64(1), float64(2), float64(3)},
		"allowed_ips":    []any{"10.0.0.0/8"},
	}
	if !reflect.DeepEqual(p, wantPeer) {
		t.Errorf("peers[0]\n got  %v\n want %v", mustJSON(p), mustJSON(wantPeer))
	}
}

// allowed_ips 缺省时补 ["0.0.0.0/0","::/0"]；出站已带 peers（1.11 写法）时保留它们。
func TestWireguardAllowedIPsDefaultAndPeersStyle(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/wireguard-basic.in.json"), "direct")
	peer := find(res.Endpoints, "wg-1")["peers"].([]any)[0].(map[string]any)
	if !reflect.DeepEqual(peer["allowed_ips"], []any{"0.0.0.0/0", "::/0"}) {
		t.Errorf("allowed_ips 缺省值 = %v", peer["allowed_ips"])
	}
	if _, has := peer["reserved"]; has {
		t.Error("没有 reserved 时不该凭空生成")
	}

	res = clean(readDoc(t, "testdata/legacy/wireguard-peers-style.in.json"), "direct")
	ep := find(res.Endpoints, "wg-3")
	if got := mustJSON(ep["peers"]); !strings.Contains(got, `"wg3.example.net"`) || strings.Contains(got, "::/0") {
		t.Errorf("已有 peers 应原样保留: %s", got)
	}
	if ep["address"] == nil {
		t.Errorf("local_address 应变成 address: %v", ep)
	}
	if _, ok := ep["local_address"]; ok {
		t.Error("local_address 应已改名")
	}
}

// 原有端点保持在前，转换出来的端点追加在后。
func TestEndpointOrder(t *testing.T) {
	res := Clean(
		[]map[string]any{{"type": "wireguard", "tag": "from-outbound", "server": "192.0.2.1", "server_port": 1, "local_address": []any{"10.0.0.2/32"}, "private_key": "k", "peer_public_key": "p"}},
		[]map[string]any{{"type": "wireguard", "tag": "already-endpoint", "address": []any{"10.0.0.3/32"}, "private_key": "k", "peers": []any{}}},
		CleanOptions{})
	if len(res.Endpoints) != 2 || res.Endpoints[0]["tag"] != "already-endpoint" || res.Endpoints[1]["tag"] != "from-outbound" {
		t.Errorf("端点顺序 = %v", mustJSON(res.Endpoints))
	}
}

// 订阅自带的 block / dns / selector / urltest / direct 全部丢弃，并先记账。
func TestDropAndBookkeeping(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/drop-types.in.json"), "direct")
	if len(res.Outbounds) != 1 || res.Outbounds[0]["tag"] != "a" {
		t.Fatalf("只应留下节点 a: %v", mustJSON(res.Outbounds))
	}
	want := []string{"block:block", "dns-out:dns", "direct:direct", "sel2:select", "sel:selector", "ut2:url-test", "ut:urltest"}
	sort.Strings(want)
	if got := res.SortedRemoved(); !reflect.DeepEqual(got, want) {
		t.Errorf("记账 = %v，期望 %v", got, want)
	}
	if len(res.Remapped) != 0 {
		t.Errorf("没有引用就不该有重映射: %v", res.Remapped)
	}
}

// 旧字段：tls_fragment / tls_tricks / domain_strategy / sniff* 删除；有效字段与未知字段保留。
func TestStripLegacyFieldsKeepsTheRest(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/tls-fragment-tricks.in.json"), "direct")
	tr := find(res.Outbounds, "t")
	if _, ok := tr["tls_fragment"]; ok {
		t.Error("顶层 tls_fragment 应删除")
	}
	tls := tr["tls"].(map[string]any)
	for _, k := range []string{"tls_tricks", "tls_fragment"} {
		if _, ok := tls[k]; ok {
			t.Errorf("tls.%s 应删除", k)
		}
	}
	if tls["enabled"] != true || tls["server_name"] != "t.example.net" {
		t.Errorf("tls 里的有效字段应保留: %v", tls)
	}

	res = clean(readDoc(t, "testdata/legacy/domain-strategy-and-sniff.in.json"), "direct")
	a := find(res.Outbounds, "a")
	for _, k := range []string{"domain_strategy", "sniff", "sniff_override_destination", "sniff_timeout"} {
		if _, ok := a[k]; ok {
			t.Errorf("出站上的 %s 应删除", k)
		}
	}
	if _, ok := find(res.Endpoints, "wg-e")["domain_strategy"]; ok {
		t.Error("端点上的 domain_strategy 也应删除")
	}

	res = clean(readDoc(t, "testdata/legacy/keep-valid-fields.in.json"), "direct")
	k := find(res.Outbounds, "a")
	if k["tcp_fast_open"] != true || k["udp_fragment"] != true || k["connect_timeout"] != "5s" {
		t.Errorf("仍有效的字段应保留: %v", k)
	}
	if k["multiplex"] == nil {
		t.Error("multiplex 应保留")
	}
}

// 未知字段原样保留（不替上游猜）；同一个出站上的旧字段照常删除。
func TestUnknownFieldsArePreserved(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/unknown-fields-preserved.in.json"), "direct")
	a := find(res.Outbounds, "a")
	if !reflect.DeepEqual(a["x_future_field"], map[string]any{"nested": []any{float64(1), float64(2), float64(3)}}) {
		t.Errorf("未知字段应原样保留: %v", a["x_future_field"])
	}
	if _, ok := a["domain_strategy"]; ok {
		t.Error("旧字段仍应删除")
	}
}

// 记账与重映射：node-a → custom-direct（订阅自带的 type: direct）在 direct / warp 目标下分别重映射。
func TestRemapDetourToRemovedDirect(t *testing.T) {
	for _, target := range []string{"direct", "warp"} {
		t.Run(target, func(t *testing.T) {
			res := clean(readDoc(t, "testdata/legacy/detour-remap.in.json"), target)
			if find(res.Outbounds, "custom-direct") != nil {
				t.Error("custom-direct 应被删除")
			}
			if got := res.Removed["custom-direct"]; got != "direct" {
				t.Errorf("Removed[custom-direct] = %q", got)
			}
			if got := find(res.Outbounds, "node-a")["detour"]; got != target {
				t.Errorf("node-a.detour = %v，期望 %s", got, target)
			}
			if got := find(res.Endpoints, "wg-d")["detour"]; got != target {
				t.Errorf("端点 wg-d.detour = %v，期望 %s", got, target)
			}
			if got := find(res.Outbounds, "node-b")["detour"]; got != "node-a" {
				t.Errorf("指向保留节点的 detour 不该动: %v", got)
			}
			want := []Remap{{Node: "node-a", Old: "custom-direct", New: target}, {Node: "wg-d", Old: "custom-direct", New: target}}
			if !reflect.DeepEqual(res.Remapped, want) {
				t.Errorf("Remapped = %+v，期望 %+v", res.Remapped, want)
			}
			if len(res.Warnings) != 2 || !strings.HasPrefix(res.Warnings[0], "detour-remapped:") {
				t.Errorf("warnings = %v", res.Warnings)
			}
		})
	}
}

// 空目标按 direct。
func TestRemapTargetDefaultsToDirect(t *testing.T) {
	res := Clean([]map[string]any{{"type": "direct", "tag": "d"}, {"type": "shadowsocks", "tag": "n", "detour": "d"}}, nil, CleanOptions{})
	if res.Outbounds[0]["detour"] != "direct" {
		t.Errorf("detour = %v", res.Outbounds[0]["detour"])
	}
}

// 指向被丢弃的 selector / urltest / block / dns 或从未存在 tag 的引用不被重映射（交给构建器报悬空）。
func TestDanglingReferencesAreNotRemapped(t *testing.T) {
	res := clean(readDoc(t, "testdata/legacy/detour-not-remapped.in.json"), "direct")
	for tag, want := range map[string]string{"x": "grp", "y": "blk", "z": "never-existed", "w": "dns-out"} {
		if got := find(res.Outbounds, tag)["detour"]; got != want {
			t.Errorf("%s.detour = %v，应保持 %s（不替用户猜）", tag, got, want)
		}
	}
	if len(res.Remapped) != 0 || len(res.Warnings) != 0 {
		t.Errorf("不该有重映射: %+v %v", res.Remapped, res.Warnings)
	}
	for _, tag := range []string{"grp", "blk", "dns-out"} {
		if _, ok := res.Removed[tag]; !ok {
			t.Errorf("%s 仍应记账", tag)
		}
	}
}

// 已经干净的形态原样通过。
func TestAlreadyCleanIsUntouched(t *testing.T) {
	d := readDoc(t, "testdata/legacy/already-clean.in.json")
	res := clean(d, "direct")
	if !reflect.DeepEqual(res.Outbounds, d.Outbounds) || !reflect.DeepEqual(res.Endpoints, d.Endpoints) {
		t.Errorf("干净输入被改动:\n%s\n%s", mustJSON(d), mustJSON(res))
	}
}

// 空输入不 panic。
func TestCleanEmpty(t *testing.T) {
	res := Clean(nil, nil, CleanOptions{})
	if len(res.Outbounds)+len(res.Endpoints) != 0 || len(res.Removed) != 0 {
		t.Errorf("%+v", res)
	}
}

// 与 Dart 共享的旧形态清单：Clean 是否改动每一行，与 needsCleaning 一致。
func TestSharedLegacyShapes(t *testing.T) {
	raw, err := os.ReadFile("../../testdata/shared/legacy-shapes.json")
	if err != nil {
		t.Fatal(err)
	}
	var f struct {
		Shapes []struct {
			Name          string         `json:"name"`
			JSON          map[string]any `json:"json"`
			NeedsCleaning bool           `json:"needsCleaning"`
		} `json:"shapes"`
	}
	if err := json.Unmarshal(raw, &f); err != nil || len(f.Shapes) < 8 {
		t.Fatalf("夹具不可用: %v (%d 行)", err, len(f.Shapes))
	}
	sawTrue, sawFalse := false, false
	for _, row := range f.Shapes {
		t.Run(row.Name, func(t *testing.T) {
			res := Clean([]map[string]any{row.JSON}, nil, CleanOptions{})
			var after []map[string]any
			after = append(after, res.Outbounds...)
			after = append(after, res.Endpoints...)
			changed := len(res.Removed) > 0 || !reflect.DeepEqual(after, []map[string]any{row.JSON})
			if changed != row.NeedsCleaning {
				t.Errorf("Clean 改动 = %v，夹具 needsCleaning = %v", changed, row.NeedsCleaning)
			}
			if NeedsCleaning(row.JSON) != row.NeedsCleaning {
				t.Errorf("NeedsCleaning() = %v，夹具 = %v", NeedsCleaning(row.JSON), row.NeedsCleaning)
			}
		})
		sawTrue = sawTrue || row.NeedsCleaning
		sawFalse = sawFalse || !row.NeedsCleaning
	}
	if !sawTrue || !sawFalse {
		t.Error("夹具应两种取值都有")
	}
}

// 保留 tag 的避让先于重映射：重映射生成的 detour（指向预置 direct）不会被误当成指向同名代理节点；
// 引用代理节点 direct 的 detour 才跟着改名。
func TestCleanRenamesReservedTagBeforeRemap(t *testing.T) {
	outbounds := []map[string]any{
		{"type": "shadowsocks", "tag": "a", "detour": "custom-direct"},
		{"type": "direct", "tag": "custom-direct"},
		{"type": "shadowsocks", "tag": "direct", "detour": "custom-direct"},
		{"type": "shadowsocks", "tag": "b", "detour": "direct"},
	}
	res := Clean(outbounds, nil, CleanOptions{RemapTarget: "direct"})
	byTag := map[string]map[string]any{}
	for _, o := range res.Outbounds {
		byTag[o["tag"].(string)] = o
	}
	if byTag["direct (2)"] == nil || byTag["direct"] != nil {
		t.Fatalf("代理节点 direct 应改名为 direct (2): %v", res.Outbounds)
	}
	if byTag["a"]["detour"] != "direct" || byTag["direct (2)"]["detour"] != "direct" {
		t.Errorf("重映射结果应指向预置 direct: a=%v direct(2)=%v", byTag["a"]["detour"], byTag["direct (2)"]["detour"])
	}
	if byTag["b"]["detour"] != "direct (2)" {
		t.Errorf("b 引用的是代理节点，应跟着改名: %v", byTag["b"]["detour"])
	}
	again := Clean(res.Outbounds, nil, CleanOptions{RemapTarget: "direct"})
	if len(again.Warnings) != 0 || len(again.Remapped) != 0 {
		t.Errorf("清洗应当幂等: %v", again.Warnings)
	}
}
