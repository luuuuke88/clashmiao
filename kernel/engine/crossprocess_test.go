package engine

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"
)

// crossProcessEnv 非空时，测试二进制以「跨进程用例的子进程」身份运行（值是父进程的 BasePath）。
const crossProcessEnv = "CLASHMIAO_XPROC_BASE"

type lineSink chan string

func (c lineSink) OnGroups(j string)       { c <- "groups " + j }
func (c lineSink) OnStats(j string)        { c <- "stats " + j }
func (c lineSink) OnLog(l string)          { c <- "log " + l }
func (c lineSink) OnDisconnected(m string) { c <- "disconnected " + m }

// runCrossProcessChild 是 iOS Runner 的替身：独立进程、独立 Setup（同一个 BasePath，自己的工作目录），
// 只用 Client 订阅父进程 Engine 的命令服务器。每一步的结果按行写到 stdout，由父进程断言；
// 父进程在 stdin 写一行即表示它已经停掉服务，子进程随后要收到断线通知。
func runCrossProcessChild(base string) int {
	say := func(format string, args ...any) { fmt.Printf(format+"\n", args...) }
	own, err := os.MkdirTemp("", "cc")
	if err != nil {
		say("fail mkdir %v", err)
		return 1
	}
	defer os.RemoveAll(own)
	if err := Setup(SetupOptions{BasePath: base, WorkingPath: own + "/work", TempPath: own + "/tmp", LogMaxLines: 50}); err != nil {
		say("fail setup %v", err)
		return 1
	}
	c := NewClient()
	defer c.Close()
	events := make(lineSink, 256)
	wait := func(what string, pred func(string) bool) (string, bool) {
		deadline := time.After(30 * time.Second)
		for {
			select {
			case ev := <-events:
				if pred(ev) {
					return ev, true
				}
			case <-deadline:
				say("fail timeout %s", what)
				return "", false
			}
		}
	}
	if _, err := c.SubscribeGroups(events); err != nil {
		say("fail groups %v", err)
		return 1
	}
	ev, ok := wait("first groups", func(e string) bool { return strings.HasPrefix(e, "groups ") })
	if !ok {
		return 1
	}
	say("%s", normalizeGroups(ev))
	if err := c.SelectOutbound("select", "b"); err != nil {
		say("fail select %v", err)
		return 1
	}
	if err := c.URLTest("auto"); err != nil {
		say("fail urltest %v", err)
		return 1
	}
	if _, ok := wait("selected b", func(e string) bool {
		return strings.Contains(e, `"tag":"select","type":"selector","selected":"b"`)
	}); !ok {
		return 1
	}
	say("selected")
	if _, err := c.SubscribeStats(events, 100); err != nil {
		say("fail stats %v", err)
		return 1
	}
	if _, ok := wait("stats", func(e string) bool { return strings.HasPrefix(e, `stats {"connections-in":`) }); !ok {
		return 1
	}
	say("stats")
	if _, err := c.SubscribeLogs(events); err != nil {
		say("fail logs %v", err)
		return 1
	}
	if _, ok := wait("log marker", func(e string) bool { return strings.Contains(e, "xproc-marker") }); !ok {
		return 1
	}
	say("logs")
	// 等父进程停服务，然后必须收到断线通知（Runner 据此重连）。
	if _, err := bufio.NewReader(os.Stdin).ReadString('\n'); err != nil {
		say("fail stdin %v", err)
		return 1
	}
	if _, ok := wait("disconnect", func(e string) bool { return strings.HasPrefix(e, "disconnected") }); !ok {
		return 1
	}
	say("disconnected")
	return 0
}
