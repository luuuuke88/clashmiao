package gate

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
)

// legacy 清洗后的黄金输出（internal/legacy/testdata/legacy/*.out.json）塞进最小配置：
// 必须通过构建器、闸门的不变量与 libbox.CheckConfig。
// 唯一的例外是「引用被丢弃的 selector / block / dns 或从未存在的 tag」那份——它不被重映射，
// 构建器必须以 ErrDetourDangling 拒绝（而不是悄悄改道）。
func TestLegacyCleanOutputsPassCheckConfig(t *testing.T) {
	dir := filepath.Join(TestdataDir(), "..", "..", "legacy", "testdata", "legacy")
	files, err := filepath.Glob(filepath.Join(dir, "*.out.json"))
	if err != nil || len(files) == 0 {
		t.Fatalf("没有 legacy 黄金输出: %v", err)
	}
	for _, f := range files {
		name := strings.TrimSuffix(filepath.Base(f), ".out.json")
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			p, err := build.ParseProfile(raw)
			if err != nil {
				t.Fatal(err)
			}
			var d struct {
				Endpoints []map[string]any `json:"endpoints"`
			}
			if err := json.Unmarshal(raw, &d); err != nil {
				t.Fatal(err)
			}
			p.Endpoints = d.Endpoints

			if name == "detour-not-remapped" {
				_, _, err := build.Build(p, Option("O1"), build.AndroidEnv())
				if !errors.Is(err, build.ErrDetourDangling) {
					t.Fatalf("悬空的 detour 应被构建器以 ErrDetourDangling 拒绝，实际 %v", err)
				}
				return
			}
			if name == "unknown-fields-preserved" {
				// 内核对未知字段是严格的：清洗器原样保留（不替上游猜），所以由内核在 CheckConfig 报出，而不是被我们悄悄吞掉。
				cfgRaw, _, err := build.Build(p, Option("O1"), build.AndroidEnv())
				if err != nil {
					t.Fatal(err)
				}
				adapted, _, _ := HostAdapt(cfgRaw, AdaptOptions{})
				if err := CheckConfig(adapted); err == nil || !strings.Contains(err.Error(), "x_future_field") {
					t.Fatalf("内核应指出未知字段 x_future_field，实际 %v", err)
				}
				return
			}
			o := Option("O1")
			cfgRaw, _, err := build.Build(p, o, build.AndroidEnv())
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			if vs := CheckInvariants(cfgRaw, o, build.AndroidEnv()); len(vs) != 0 {
				t.Errorf("不变量违规: %v", vs)
			}
			adapted, ap, err := HostAdapt(cfgRaw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			if bad, err := CheckWhitelist(cfgRaw, adapted, ap); err != nil || len(bad) != 0 {
				t.Fatalf("%v %v", err, bad)
			}
			if err := CheckConfig(adapted); err != nil {
				t.Fatalf("CheckConfig: %v", err)
			}
		})
	}
}

// 旧 Parse 产物里自带的 direct 出站被删除、引用同样被重映射后，整条路径（Clean → Build）不悬空。
func TestLegacyRemapThenBuildDoesNotDangle(t *testing.T) {
	in, err := os.ReadFile(filepath.Join(TestdataDir(), "..", "..", "legacy", "testdata", "legacy", "detour-remap.in.json"))
	if err != nil {
		t.Fatal(err)
	}
	var d struct {
		Outbounds []map[string]any `json:"outbounds"`
		Endpoints []map[string]any `json:"endpoints"`
	}
	if err := json.Unmarshal(in, &d); err != nil {
		t.Fatal(err)
	}
	// 没经过 Clean：custom-direct 是订阅自带的 direct 出站，构建器会丢弃它，引用悬空。
	_, _, err = build.Build(build.Profile{Outbounds: d.Outbounds, Endpoints: d.Endpoints}, Option("O1"), build.AndroidEnv())
	if !errors.Is(err, build.ErrDetourDangling) {
		t.Fatalf("没清洗的旧文件应以悬空被拒绝（证明清洗这一步不是摆设），实际 %v", err)
	}
	res := legacy.Clean(d.Outbounds, d.Endpoints, legacy.CleanOptions{RemapTarget: "direct"})
	if _, _, err := build.Build(build.Profile{Outbounds: res.Outbounds, Endpoints: res.Endpoints}, Option("O1"), build.AndroidEnv()); err != nil {
		t.Fatalf("清洗后应能构建: %v", err)
	}
}
