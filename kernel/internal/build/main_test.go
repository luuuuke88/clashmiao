package build_test

import (
	"fmt"
	"os"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/gate"
)

// 真启动的测试（!race 文件）需要 libbox 的 Setup；它在进程内只能做一次。
func TestMain(m *testing.M) {
	cleanup, err := gate.Setup()
	if err != nil {
		fmt.Fprintln(os.Stderr, "gate setup:", err)
		os.Exit(1)
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}
