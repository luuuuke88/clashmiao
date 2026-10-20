package build_test

import (
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 架构约束：internal/{build,subscription,uri,legacy,options} 不 import sing-box，也不 import engine。
// 只有 engine、core，以及只被 _test.go 使用的测试支持包 internal/build/gate、internal/build/e2e 可以。
// （这样升级 sing-box 时，纯数据层不会被编译器悄悄绑进去；变化靠黄金文件与闸门发现。）

var forbiddenImports = []string{"github.com/sagernet/", "/kernel/engine", "/kernel/core"}

// exempt 是允许 import 的测试支持包目录（相对 internal/）。
var exempt = []string{"build/gate", "build/e2e"}

// scanImports 返回 root 下（排除 exempt 子目录）所有违规 import，格式「文件: import 路径」。
func scanImports(t *testing.T, root string, exempt []string) []string {
	t.Helper()
	var bad []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, path)
		rel = filepath.ToSlash(rel)
		if d.IsDir() {
			for _, e := range exempt {
				if rel == e {
					return filepath.SkipDir
				}
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") {
			return nil
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		for _, imp := range f.Imports {
			p := strings.Trim(imp.Path.Value, `"`)
			for _, bannedPart := range forbiddenImports {
				if strings.Contains(p, bannedPart) {
					bad = append(bad, rel+": "+p)
				}
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return bad
}

func TestPureLayersDoNotImportSingBoxOrEngine(t *testing.T) {
	if bad := scanImports(t, "..", exempt); len(bad) != 0 {
		t.Fatalf("这些包不该 import sing-box / engine / core:\n  %s", strings.Join(bad, "\n  "))
	}
}

// 证明这条检查不是摆设：往临时目录放一个 import 了 sing-box 的文件，必须被抓住；放在豁免目录里则放行。
func TestImportScanCatchesViolation(t *testing.T) {
	root := t.TempDir()
	write := func(rel, src string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("uri/x.go", "package uri\nimport _ \"github.com/sagernet/sing-box/option\"\n")
	write("legacy/y_test.go", "package legacy\nimport _ \"github.com/luuuuke88/clashmiao/kernel/engine\"\n")
	write("build/gate/ok.go", "package gate\nimport _ \"github.com/sagernet/sing-box/option\"\n")
	bad := scanImports(t, root, exempt)
	if len(bad) != 2 {
		t.Fatalf("应抓住 2 处（uri 与 legacy 的测试文件），实际 %v", bad)
	}
	for _, b := range bad {
		if strings.HasPrefix(b, "build/gate") {
			t.Errorf("豁免目录不该被报: %s", b)
		}
	}
}
