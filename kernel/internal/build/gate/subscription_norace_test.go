//go:build !race

package gate

import (
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

// 端点四形态真 Start：端点出现在 select / auto 成员里，默认值正确，仅端点的订阅也起得来。
func TestSharedProfilesRealStart(t *testing.T) {
	want := map[string]struct {
		selectMembers string
		def           string
	}{
		"endpoint-only":        {"auto,wg-hk", "auto"},
		"mixed":                {"auto,香港01,美国01,wg-jp", "auto"},
		"endpoint-default":     {"auto,香港01,wg-sg§default§", "wg-sg§default§"},
		"groups-with-endpoint": {"auto,香港01,剩余流量：100 GB,wg-hk", "auto"},
	}
	for _, name := range sharedProfileNames {
		t.Run(name, func(t *testing.T) {
			p, _, err := subscription.Parse(sharedProfile(t, name))
			if err != nil {
				t.Fatal(err)
			}
			raw, _, err := build.Build(toBuildProfile(p), Option("O1"), build.AndroidEnv())
			if err != nil {
				t.Fatal(err)
			}
			adapted, _, err := HostAdapt(raw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			eng, _ := NewEngine(t)
			if err := eng.Start(string(adapted)); err != nil {
				t.Fatalf("Start: %v", err)
			}
			defer eng.Stop()
			sel := FirstGroups(t, eng).Find("select")
			if sel == nil {
				t.Fatal("没有 select 组")
			}
			w := want[name]
			if got := strings.Join(sel.ItemTags(), ","); got != w.selectMembers {
				t.Errorf("select 成员 = %s，期望 %s", got, w.selectMembers)
			}
			if sel.Selected != w.def {
				t.Errorf("selected = %q，期望 %q", sel.Selected, w.def)
			}
		})
	}
}
