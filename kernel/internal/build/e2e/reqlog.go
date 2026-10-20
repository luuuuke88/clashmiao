// Package e2e 是测试用的本地可控目标：本地 DNS / DoH、HTTP 目标、记录 TLS 记录数的 TLS 目标、假节点（SOCKS 上游）。
// 每个目标都带请求记录，并提供基于 channel 的 WaitFor，既不提供也不使用 sleep。
// 仅被 _test.go 使用，不进 core。
package e2e

import (
	"sync"
	"testing"
	"time"
)

// Entry 是一条请求记录。
type Entry struct {
	Kind   string // dns / http / tls / socks
	Source string // 对端地址（谁来的）
	Target string // 域名、host:port 或路径
	Detail string // 附加信息：查询类型、传输方式、TLS 记录数……
}

// Log 是并发安全的请求记录。
type Log struct {
	Name string

	mu      sync.Mutex
	entries []Entry
	waiters []*waiter
}

type waiter struct {
	pred func([]Entry) bool
	ch   chan struct{}
}

// NewLog 建一个空记录；name 只用于失败信息。
func NewLog(name string) *Log { return &Log{Name: name} }

// Add 追加一条记录并唤醒满足条件的等待者。
func (l *Log) Add(e Entry) {
	l.mu.Lock()
	l.entries = append(l.entries, e)
	var still []*waiter
	for _, w := range l.waiters {
		if w.pred(l.entries) {
			close(w.ch)
		} else {
			still = append(still, w)
		}
	}
	l.waiters = still
	l.mu.Unlock()
}

// Entries 返回当前记录的快照。
func (l *Log) Entries() []Entry {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]Entry(nil), l.entries...)
}

// Len 是当前记录条数。
func (l *Log) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.entries)
}

// Count 统计满足条件的记录数。
func (l *Log) Count(pred func(Entry) bool) int {
	n := 0
	for _, e := range l.Entries() {
		if pred(e) {
			n++
		}
	}
	return n
}

// WaitFor 返回的 channel 在记录条数 >= n 时关闭。
func (l *Log) WaitFor(n int) <-chan struct{} {
	return l.WaitUntil(func(es []Entry) bool { return len(es) >= n })
}

// WaitUntil 返回的 channel 在 pred(记录快照) 为真时关闭（事件驱动，不轮询）。
func (l *Log) WaitUntil(pred func([]Entry) bool) <-chan struct{} {
	l.mu.Lock()
	defer l.mu.Unlock()
	ch := make(chan struct{})
	if pred(l.entries) {
		close(ch)
		return ch
	}
	l.waiters = append(l.waiters, &waiter{pred: pred, ch: ch})
	return ch
}

// MustWait 等到至少 n 条记录；超时（30 s，仅作失败兜底）则让测试失败。
func (l *Log) MustWait(t testing.TB, n int) {
	t.Helper()
	select {
	case <-l.WaitFor(n):
	case <-time.After(30 * time.Second):
		t.Fatalf("%s: timeout waiting for %d log entries, have %d: %v", l.Name, n, l.Len(), l.Entries())
	}
}

// MustWaitMatch 等到出现一条满足条件的记录。
func (l *Log) MustWaitMatch(t testing.TB, what string, match func(Entry) bool) {
	t.Helper()
	select {
	case <-l.WaitUntil(func(es []Entry) bool {
		for _, e := range es {
			if match(e) {
				return true
			}
		}
		return false
	}):
	case <-time.After(30 * time.Second):
		t.Fatalf("%s: timeout waiting for %s, log: %v", l.Name, what, l.Entries())
	}
}

// Has 判断是否已有满足条件的记录。
func (l *Log) Has(pred func(Entry) bool) bool { return l.Count(pred) > 0 }
