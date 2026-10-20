package gate

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

var update = flag.Bool("update", false, "重写黄金文件（改动要在评审里看 diff）")

// testdataDir 由本文件的源码位置推出（不依赖调用方测试的工作目录，build 包与 gate 包的测试共用同一份数据）。
var testdataDir = func() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		panic("gate: cannot locate source dir")
	}
	return filepath.Join(filepath.Dir(file), "..", "testdata")
}()

// TestdataDir 是 internal/build/testdata 的绝对路径。
func TestdataDir() string { return testdataDir }

// GoldenDir 是黄金文件目录。
var GoldenDir = filepath.Join(testdataDir, "golden")

// Golden 把 got 与 GoldenDir/<name>.json 逐字节比较；带 -update 则重写。
// 缺文件不会自动创建：新增矩阵项必须显式 -update 并把文件放进评审。
func Golden(t testing.TB, name string, got []byte) {
	t.Helper()
	path := filepath.Join(GoldenDir, name+".json")
	if *update {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, got, 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("黄金文件 %s 不存在（新矩阵项需 `go test ./internal/build/gate -update` 生成并评审）: %v", path, err)
	}
	if !bytes.Equal(want, got) {
		t.Errorf("%s 与黄金文件不一致（有意的改动请 -update 并在评审里看 diff）\n--- 黄金 ---\n%s\n--- 实际 ---\n%s", name, want, got)
	}
}

// GoldenNames 列出黄金文件目录里的全部名字（不含扩展名）。
func GoldenNames(t testing.TB) []string {
	t.Helper()
	entries, err := os.ReadDir(GoldenDir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		if n := e.Name(); filepath.Ext(n) == ".json" {
			names = append(names, n[:len(n)-len(".json")])
		}
	}
	return names
}
