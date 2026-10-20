//go:build !race

package build_test

import (
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
)

// 真 Start：Dart 产出的每一格适配副本都能真的起来、首帧有 select 组，Stop 干净。
// （带 urltest 组的真启动在 -race 下会撞上游的数据竞争，所以放在 !race 文件里，见 tools/kernel/gotest.sh。）
func TestDartRuntimeConfigsRealStart(t *testing.T) {
	for _, p := range dartPairs {
		t.Run(p.profile+"×"+p.option, func(t *testing.T) {
			adapted := buildDartPair(t, p.profile, p.option)
			eng, _ := gate.NewEngine(t)
			if err := eng.Start(string(adapted)); err != nil {
				t.Fatalf("Start: %v", err)
			}
			defer eng.Stop()
			if sel := gate.FirstGroups(t, eng).Find("select"); sel == nil {
				t.Fatal("首帧没有 select 组")
			}
		})
	}
}
