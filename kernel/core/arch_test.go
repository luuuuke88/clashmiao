package core_test

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 门面只经 engine 触碰 sing-box（libbox 全仓只有 engine 一处 import），
// 且不 import 测试支持包（gate / e2e 只被 _test.go 使用，不进 gomobile 产物）。
func TestFacadeImportsOnlyEngineAndInternalData(t *testing.T) {
	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		if strings.HasSuffix(f, "_test.go") {
			continue
		}
		af, err := parser.ParseFile(token.NewFileSet(), f, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatal(err)
		}
		for _, imp := range af.Imports {
			p := strings.Trim(imp.Path.Value, `"`)
			if strings.Contains(p, "github.com/sagernet/") {
				t.Errorf("%s 直接 import %s：只能经 engine", f, p)
			}
			if strings.Contains(p, "/internal/build/gate") || strings.Contains(p, "/internal/build/e2e") {
				t.Errorf("%s import 了测试支持包 %s", f, p)
			}
		}
	}
	if _, err := os.Stat("core.go"); err != nil {
		t.Fatal("扫描目录不对：", err)
	}
}
