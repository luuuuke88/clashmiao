// Package uri 把单行分享链接（vmess:// vless:// ss:// …）转换成 sing-box 出站 / 端点。
// 净室实现：行为由现有订阅形态与官方文档定义，不拷贝上游 core 的源码。本包不 import sing-box。
package uri

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/url"
	"strconv"
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

var (
	// ErrUnsupportedScheme 表示这个 scheme 没有转换器。
	ErrUnsupportedScheme = errors.New("unsupported scheme")
	// ErrInvalid 表示链接本身不合法或用了我们不能兑现的组合（不静默降级）。消息以 `uri-invalid:` 开头。
	ErrInvalid = errors.New("uri-invalid")
)

// invalidf 生成 `uri-invalid: <scheme>: …` 错误（errors.Is(err, ErrInvalid) 为真）。
func invalidf(scheme, format string, args ...any) error {
	return fmt.Errorf("%w: %s: %s", ErrInvalid, scheme, fmt.Sprintf(format, args...))
}

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
		return Entity{}, fmt.Errorf("%w: not a share link", ErrInvalid)
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

// ---- 公共工具 ----

// decodeB64 接受标准 / urlsafe、带 / 不带 padding 的 base64，并容忍夹带的空白。
func decodeB64(s string) ([]byte, error) {
	s = strings.Map(func(r rune) rune {
		if r == ' ' || r == '\n' || r == '\r' || r == '\t' {
			return -1
		}
		return r
	}, s)
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return b, nil
		}
	}
	return nil, errors.New("not base64")
}

// params 是链接查询参数：键不区分大小写，值已 percent 解码。
// 与 url.ParseQuery 的区别：「+」保持字面量（base64 密钥里有 +，不能被当成空格）。
type params map[string]string

func parseParams(rawQuery string) params {
	p := params{}
	for _, kv := range strings.Split(rawQuery, "&") {
		if kv == "" {
			continue
		}
		k, v, _ := strings.Cut(kv, "=")
		k, v = unescape(k), unescape(v)
		key := strings.ToLower(k)
		if _, exists := p[key]; !exists { // 重复键取第一个
			p[key] = v
		}
	}
	return p
}

// get 返回第一个非空的值（按给出的键名顺序，键名不区分大小写）。
func (p params) get(keys ...string) string {
	for _, k := range keys {
		if v := p[strings.ToLower(k)]; v != "" {
			return v
		}
	}
	return ""
}

// truthy：1 / true / yes / on。
func (p params) truthy(keys ...string) bool {
	switch strings.ToLower(p.get(keys...)) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

func unescape(s string) string {
	if !strings.Contains(s, "%") {
		return s
	}
	if u, err := url.PathUnescape(s); err == nil {
		return u
	}
	return s
}

// splitList 按逗号切分并去掉空项与空白。
func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// link 是拆开的 scheme://[userinfo@]host:port[/path][?query][#fragment]。
type link struct {
	scheme   string
	user     string
	password string
	hasPass  bool
	hasUser  bool
	host     string
	port     int
	path     string
	query    params
	rawQuery string
	name     string
}

// parseLink 用标准库解析 URL 形式的链接；port 缺省时返回 0（由调用方决定是否必须）。
func parseLink(line string) (*link, error) {
	u, err := url.Parse(line)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalid, err)
	}
	l := &link{scheme: strings.ToLower(u.Scheme), host: u.Hostname(), path: u.Path, rawQuery: u.RawQuery,
		query: parseParams(u.RawQuery), name: unescape(u.Fragment)}
	if u.User != nil {
		l.hasUser = true
		l.user = u.User.Username()
		l.password, l.hasPass = u.User.Password()
	}
	if p := u.Port(); p != "" {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 65535 {
			return nil, invalidf(l.scheme, "bad port %q", p)
		}
		l.port = n
	}
	return l, nil
}

// need 校验 host 与 port 都在。
func (l *link) need() error {
	if l.host == "" {
		return invalidf(l.scheme, "missing host")
	}
	if l.port == 0 {
		return invalidf(l.scheme, "missing port")
	}
	return nil
}

// tag 取名称，没有就用 host:port。
func (l *link) tag() string {
	if l.name != "" {
		return l.name
	}
	return defaultTag(l.host, l.port)
}

func defaultTag(host string, port int) string {
	if strings.Contains(host, ":") {
		return fmt.Sprintf("[%s]:%d", host, port)
	}
	return fmt.Sprintf("%s:%d", host, port)
}

// credentials 返回 user[:password]（用户名里没有冒号时就是整段 userinfo）。
func (l *link) credentials() string {
	if l.hasPass {
		return l.user + ":" + l.password
	}
	return l.user
}

func base(typ string, tag, host string, port int) map[string]any {
	return map[string]any{"type": typ, "tag": tag, "server": host, "server_port": port}
}
