package subscription

import (
	"bytes"
	"encoding/base64"
	"strings"
)

// 输入形态。
type format int

const (
	formatUnknown format = iota
	formatJSON
	formatClash
	formatList
)

var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

// normalizeInput 去 BOM 与首尾空白。
func normalizeInput(in []byte) []byte {
	in = bytes.TrimSpace(in)
	for bytes.HasPrefix(in, utf8BOM) {
		in = bytes.TrimSpace(in[len(utf8BOM):])
	}
	return in
}

// stripJSONComments 去掉 // 与 /* */ 注释（字符串里的不动），保留换行以便错误行号不乱。
func stripJSONComments(in []byte) []byte {
	out := make([]byte, 0, len(in))
	inStr, esc := false, false
	for i := 0; i < len(in); i++ {
		c := in[i]
		if inStr {
			out = append(out, c)
			switch {
			case esc:
				esc = false
			case c == '\\':
				esc = true
			case c == '"':
				inStr = false
			}
			continue
		}
		switch {
		case c == '"':
			inStr = true
			out = append(out, c)
		case c == '/' && i+1 < len(in) && in[i+1] == '/':
			for i < len(in) && in[i] != '\n' {
				i++
			}
			if i < len(in) {
				out = append(out, '\n')
			}
		case c == '/' && i+1 < len(in) && in[i+1] == '*':
			i += 2
			for i+1 < len(in) && !(in[i] == '*' && in[i+1] == '/') {
				if in[i] == '\n' {
					out = append(out, '\n')
				}
				i++
			}
			i++ // 跳过 '/'
		default:
			out = append(out, c)
		}
	}
	return out
}

// looksLikeJSON：以 { 或 [ 开头（去注释前后都行）。
func looksLikeJSON(in []byte) bool {
	return len(in) > 0 && (in[0] == '{' || in[0] == '[')
}

// hasShareLinks：至少有一行以 scheme:// 开头。
func hasShareLinks(text string) bool {
	for _, line := range strings.Split(text, "\n") {
		if isLinkLine(strings.TrimSpace(line)) {
			return true
		}
	}
	return false
}

// isLinkLine：形如 scheme://… 且 scheme 只含字母数字与 +-.（排除 http 页面里的零散文字）。
func isLinkLine(line string) bool {
	i := strings.Index(line, "://")
	if i <= 0 {
		return false
	}
	for _, r := range line[:i] {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '+' || r == '-' || r == '.') {
			return false
		}
	}
	return true
}

// decodeBase64Whole 对整段文本解一次 base64：标准 / urlsafe、有无 padding、夹带空白与换行都认。
func decodeBase64Whole(text string) ([]byte, bool) {
	var b strings.Builder
	for _, r := range text {
		if r == '\n' || r == '\r' || r == ' ' || r == '\t' {
			continue
		}
		b.WriteRune(r)
	}
	s := b.String()
	if s == "" {
		return nil, false
	}
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.RawURLEncoding} {
		if dec, err := enc.DecodeString(s); err == nil && len(dec) > 0 {
			return dec, true
		}
	}
	return nil, false
}

// hasClashProxies：文本像 Clash 配置（顶层有 proxies 键）。粗筛，真正的校验在解析时。
func hasClashProxies(text string) bool {
	for _, line := range strings.Split(text, "\n") {
		l := strings.TrimRight(line, " \t\r")
		if strings.HasPrefix(l, "proxies:") || strings.HasPrefix(l, `"proxies":`) || strings.HasPrefix(l, "'proxies':") {
			return true
		}
	}
	return false
}
