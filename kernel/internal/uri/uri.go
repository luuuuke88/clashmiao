// Package uri 把单行分享链接（vmess:// vless:// ss:// …）转换成 sing-box 出站 / 端点。
// 净室实现：行为由现有订阅形态与官方文档定义，不拷贝上游 core 的源码。本包不 import sing-box。
package uri

import (
	"errors"
	"fmt"
	"strings"
	"sync"
)

// Entity 是一行链接转换出的节点：普通出站，或（wg:// 这类）端点。
type Entity struct {
	Map      map[string]any
	Endpoint bool
}

// Converter 转换一个 scheme 的整行链接（包含 scheme）。
type Converter func(line string) (Entity, error)

// ErrUnsupportedScheme 表示这个 scheme 没有转换器。
var ErrUnsupportedScheme = errors.New("unsupported scheme")

var (
	mu       sync.RWMutex
	registry = map[string]Converter{}
)

// Register 登记 scheme（小写，不含 ://）的转换器。重复登记 panic（编程错误）。
func Register(scheme string, fn Converter) {
	mu.Lock()
	defer mu.Unlock()
	scheme = strings.ToLower(scheme)
	if _, dup := registry[scheme]; dup {
		panic("uri: duplicate scheme " + scheme)
	}
	registry[scheme] = fn
}

// Schemes 列出已登记的 scheme（测试用）。
func Schemes() []string {
	mu.RLock()
	defer mu.RUnlock()
	out := make([]string, 0, len(registry))
	for s := range registry {
		out = append(out, s)
	}
	return out
}

// SchemeOf 取一行链接的 scheme（小写）；不是 scheme://… 返回空串。
func SchemeOf(line string) string {
	i := strings.Index(line, "://")
	if i <= 0 {
		return ""
	}
	return strings.ToLower(line[:i])
}

// Convert 转换一行链接。订阅型 scheme（ssconf://）明确报不支持。
func Convert(line string) (Entity, error) {
	line = strings.TrimSpace(line)
	scheme := SchemeOf(line)
	if scheme == "" {
		return Entity{}, fmt.Errorf("not a share link")
	}
	if scheme == "ssconf" {
		return Entity{}, fmt.Errorf("%w: ssconf:// subscription links are not supported", ErrUnsupportedScheme)
	}
	mu.RLock()
	fn := registry[scheme]
	mu.RUnlock()
	if fn == nil {
		return Entity{}, fmt.Errorf("%w: %s://", ErrUnsupportedScheme, scheme)
	}
	return fn(line)
}
