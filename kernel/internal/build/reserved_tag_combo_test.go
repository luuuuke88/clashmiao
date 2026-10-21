package build_test

import (
	"encoding/json"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

// 保留 tag 改名 × 旧直连重映射的组合（三种模式 × Build / Parse→Build）：
// 「指向被丢弃的直连类出站」的引用重映射到预置 direct / warp 之后，不能再被「订阅里名叫 direct 的代理节点」
// 的改名逻辑捕获成指向 direct (2)；名叫 direct 的节点自己的 detour 也不能因此变成自环。
func comboSubscription() []byte {
	b, _ := json.Marshal(map[string]any{"outbounds": []map[string]any{
		node("a", "custom-direct"),
		{"type": "direct", "tag": "custom-direct"},
		node("direct", "custom-direct"), // 订阅里名叫 direct 的代理节点，自己也指向被丢弃的直连类
		node("b", "direct"),             // 引用的是这个代理节点（不是预置 direct）：应跟着改名
	}})
	return b
}

func TestReservedRenameDoesNotRecaptureRemappedDirect(t *testing.T) {
	modes := []struct {
		name, option string
		wantRemapTo  string // a 的 detour：preset direct 会被去掉，proxy_over_warp 下指向 warp
	}{
		{"normal", "O1", ""},
		{"proxy_over_warp", "O5a", "warp"},
		{"warp_over_proxy", "O5b", ""},
	}
	for _, m := range modes {
		for _, path := range []string{"build", "parse-then-build"} {
			t.Run(m.name+"/"+path, func(t *testing.T) {
				o := gate.Option(m.option)
				profile := comboSubscription()
				if path == "parse-then-build" {
					p, _, err := subscription.Parse(profile)
					if err != nil {
						t.Fatal(err)
					}
					profile, _ = json.Marshal(map[string]any{"outbounds": p.Outbounds, "endpoints": p.Endpoints})
				}
				raw, warnings, err := buildJSON(t, profile, o)
				if err != nil {
					t.Fatalf("构建失败: %v", err)
				}
				c := decode(t, raw)
				if c.entity("direct (2)") == nil || c.entity("direct (2)")["type"] != "shadowsocks" {
					t.Fatalf("订阅里的代理节点 direct 应改名为 direct (2): %v", warnings)
				}
				if got := c.detour("a"); got != m.wantRemapTo {
					t.Errorf("a.detour = %q，期望 %q（重映射结果不能被改名逻辑捕获成 direct (2)）", got, m.wantRemapTo)
				}
				if got := c.detour("direct (2)"); got != m.wantRemapTo {
					t.Errorf("direct (2).detour = %q，期望 %q（不能自环）", got, m.wantRemapTo)
				}
				if got := c.detour("b"); got != "direct (2)" {
					t.Errorf("b 引用的是代理节点 direct，应改写为 direct (2)，实际 %q", got)
				}
			})
		}
	}
}

// legacy.ReservedTags 与构建器的保留 tag 清单一致（两处各持一份，防止改一处漏一处）。
func TestLegacyReservedTagsMatchBuilder(t *testing.T) {
	got := map[string]bool{}
	for _, tag := range legacy.ReservedTags {
		got[tag] = true
	}
	for _, tag := range build.ReservedTags() {
		if !got[tag] {
			t.Errorf("legacy.ReservedTags 缺少 %q", tag)
		}
		delete(got, tag)
	}
	for tag := range got {
		t.Errorf("legacy.ReservedTags 多出 %q", tag)
	}
}
