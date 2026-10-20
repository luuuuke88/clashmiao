package core_test

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/core"
	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 真实的两步流程：订阅原文 → core.Parse 落盘 → core.BuildConfig（选项 JSON 与 Dart 发来的一致）。
// 关注 WARP 与「订阅自带直连类出站」「悬空 detour」的交互（spec §5.2.2 / §6.3）。

type flowMode struct {
	name string
	opts string // configOptions JSON
}

func warpOptionsJSON(t *testing.T, mode string) string {
	t.Helper()
	o := map[string]any{}
	if mode != "" {
		o["warp"] = map[string]any{"enable": true, "mode": mode, "wireguard-config": gate.SyntheticWarpConfig}
	}
	b, err := json.Marshal(o)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func flowModes(t *testing.T) []flowMode {
	return []flowMode{
		{"无 WARP", warpOptionsJSON(t, "")},
		{"warp_over_proxy", warpOptionsJSON(t, options.WarpWarpOverProxy)},
		{"proxy_over_warp", warpOptionsJSON(t, options.WarpProxyOverWarp)},
	}
}

func writeFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

const customDirectSub = `{"outbounds":[
  {"type":"shadowsocks","tag":"node-a","server":"192.0.2.10","server_port":8388,"method":"aes-128-gcm","password":"x","detour":"custom-direct"},
  {"type":"direct","tag":"custom-direct"}
]}`

const ghostSub = `{"outbounds":[
  {"type":"shadowsocks","tag":"node-b","server":"192.0.2.11","server_port":8388,"method":"aes-128-gcm","password":"x","detour":"ghost"}
]}`

func detourOf(t *testing.T, content, tag string) (string, bool) {
	t.Helper()
	var c struct {
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal([]byte(content), &c); err != nil {
		t.Fatal(err)
	}
	for _, o := range c.Outbounds {
		if o["tag"] == tag {
			d, ok := o["detour"].(string)
			return d, ok
		}
	}
	t.Fatalf("没有出站 %s", tag)
	return "", false
}

// node-a → custom-direct：custom-direct 被读时清洗丢弃，链的去向按模式决定。
// 注意：规格 / 计划写的是「node-a.detour == direct」，但真实 Start 拒绝指向空 direct 的 detour，
// 所以 warp_over_proxy 与无 WARP 下输出里没有 detour 字段（链等价）；proxy_over_warp 下是 warp。
func TestWarpFlowCustomDirect(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.json")
	if err := core.Parse(profile, writeFile(t, dir, "sub.json", customDirectSub), false); err != nil {
		t.Fatal(err)
	}
	for _, m := range flowModes(t) {
		t.Run(m.name, func(t *testing.T) {
			content, err := core.BuildConfig(profile, m.opts)
			if err != nil {
				t.Fatal(err)
			}
			d, has := detourOf(t, content, "node-a")
			want, wantHas := "", false
			if m.name == "proxy_over_warp" {
				want, wantHas = "warp", true
			}
			if d != want || has != wantHas {
				t.Errorf("node-a.detour = %q（存在=%v），期望 %q（存在=%v）", d, has, want, wantHas)
			}
			checkBuilt(t, content, m.opts)

			// 被改写的既有链恰好 1 条 warning：proxy_over_warp 下来自读时清洗的重映射（链已终止于 warp，不再记第二条）。
			o, _, err := options.Decode([]byte(m.opts))
			if err != nil {
				t.Fatal(err)
			}
			raw, err := os.ReadFile(profile)
			if err != nil {
				t.Fatal(err)
			}
			_, warnings, err := build.BuildJSON(raw, o, build.AndroidEnv())
			if err != nil {
				t.Fatal(err)
			}
			n := 0
			for _, w := range warnings {
				if strings.HasPrefix(w, "warp-chain-rewritten:") || strings.HasPrefix(w, "detour-remapped:") {
					n++
				}
			}
			wantN := 0
			if m.name == "proxy_over_warp" {
				wantN = 1 // Parse 已把 custom-direct 落成 direct，RedirectToWarp 把它换成 warp
			}
			if n != wantN {
				t.Errorf("改写 warning 应恰好 %d 条，实际 %d: %v", wantN, n, warnings)
			}
		})
	}
}

// Parse 之后再 BuildConfig（落盘文件为中介，模拟真实两步）与直接 BuildConfig 旧文件（订阅自带 custom-direct 还在）结果一致。
func TestWarpFlowTwoStepEqualsLegacyFile(t *testing.T) {
	dir := t.TempDir()
	legacyProfile := writeFile(t, dir, "legacy.json", customDirectSub) // 旧内核落盘的形态：custom-direct 仍在
	parsed := filepath.Join(dir, "parsed.json")
	if err := core.Parse(parsed, legacyProfile, false); err != nil {
		t.Fatal(err)
	}
	for _, m := range flowModes(t) {
		t.Run(m.name, func(t *testing.T) {
			a, err := core.BuildConfig(legacyProfile, m.opts)
			if err != nil {
				t.Fatal(err)
			}
			b, err := core.BuildConfig(parsed, m.opts)
			if err != nil {
				t.Fatal(err)
			}
			if a != b {
				t.Fatal("两步（Parse → BuildConfig）与直接读旧文件的 BuildConfig 结果不一致")
			}
		})
	}
}

// node-b → ghost（从未存在）：所有模式（含无 WARP）都是 ErrDetourDangling，带 build-failed: 前缀，不产出配置。
func TestWarpFlowDanglingDetourInEveryMode(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.json")
	if err := core.Parse(profile, writeFile(t, dir, "sub.json", ghostSub), false); err != nil {
		t.Fatalf("Parse 不负责悬空引用，应通过: %v", err)
	}
	for _, m := range flowModes(t) {
		t.Run(m.name, func(t *testing.T) {
			content, err := core.BuildConfig(profile, m.opts)
			if !errors.Is(err, build.ErrDetourDangling) || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
				t.Fatalf("err = %v，期望 ErrDetourDangling 且以 %s 开头", err, build.PrefixBuildFailed)
			}
			if content != "" {
				t.Error("失败时不该产出配置")
			}
		})
	}
}

// 启用 WARP 却没有可用的 wireguard-config：build-failed:，错误里点明 warp-config-invalid:。
func TestWarpFlowMissingConfig(t *testing.T) {
	dir := t.TempDir()
	profile := filepath.Join(dir, "profile.json")
	if err := core.Parse(profile, writeFile(t, dir, "sub.json", customDirectSub), false); err != nil {
		t.Fatal(err)
	}
	_, err := core.BuildConfig(profile, `{"warp":{"enable":true,"mode":"proxy_over_warp","wireguard-config":""}}`)
	if err == nil || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) || !strings.Contains(err.Error(), "warp-config-invalid:") {
		t.Fatalf("err = %v", err)
	}
}
