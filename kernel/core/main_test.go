package core_test

import (
	"os"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/core"
)

// libbox.Setup 进程内只做一次；命令服务器的 unix socket 路径有长度上限，所以目录放在系统临时目录下的短名字目录里。
var workDir string

func TestMain(m *testing.M) {
	base, err := os.MkdirTemp("", "cc")
	if err != nil {
		panic(err)
	}
	workDir = base + "/work"
	if err := core.Setup(&core.SetupOptions{BasePath: base, WorkingPath: workDir, TempPath: base + "/tmp", LogMaxLines: 300}); err != nil {
		panic(err)
	}
	code := m.Run()
	_ = os.RemoveAll(base)
	os.Exit(code)
}
