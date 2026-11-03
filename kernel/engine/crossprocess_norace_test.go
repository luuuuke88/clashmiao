//go:build !race

package engine

import (
	"bufio"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// 真正的两个进程：本进程起 Engine，子进程（同一个测试二进制）自己 Setup 同一个 BasePath、只用 Client。
// 这是 iOS 上 Runner 与 Packet Tunnel 的形态；同进程里的两个对象证明不了 libbox 的进程级全局状态能互通。
func TestCrossProcessClient(t *testing.T) {
	e, _, _ := startWithURLTest(t)
	base := strings.TrimSuffix(testWorkDir, "/work")

	cmd := exec.Command(os.Args[0], "-test.run=^$")
	cmd.Env = append(os.Environ(), crossProcessEnv+"="+base)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })

	lines := make(chan string, 64)
	go func() {
		sc := bufio.NewScanner(stdout)
		sc.Buffer(make([]byte, 1<<20), 1<<20)
		for sc.Scan() {
			lines <- sc.Text()
		}
		close(lines)
	}()
	expect := func(prefix string) string {
		t.Helper()
		select {
		case l, ok := <-lines:
			if !ok {
				t.Fatalf("child exited before %q", prefix)
			}
			if strings.HasPrefix(l, "fail") || !strings.HasPrefix(l, prefix) {
				t.Fatalf("child: %q, want prefix %q", l, prefix)
			}
			return l
		case <-time.After(60 * time.Second):
			t.Fatalf("timeout waiting for child %q", prefix)
			return ""
		}
	}

	first := strings.TrimPrefix(expect("groups "), "groups ")
	want, err := os.ReadFile(wirePath("groups-first.json"))
	if err != nil {
		t.Fatal(err)
	}
	if first != string(want) {
		t.Fatalf("cross-process groups frame differs from fixture\n got: %s\nwant: %s", first, want)
	}
	expect("selected")
	expect("stats")
	// 日志流先回放环形缓冲再推新行：标记行写在子进程订阅日志之前或之后都能收到。
	e.WriteLog("xproc-marker")
	expect("logs")
	if err := e.Stop(); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	if err := e.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if _, err := io.WriteString(stdin, "stopped\n"); err != nil {
		t.Fatal(err)
	}
	expect("disconnected")
	if err := cmd.Wait(); err != nil {
		t.Fatalf("child exit: %v", err)
	}
}
