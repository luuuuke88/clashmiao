package subscription

import (
	"errors"
	"fmt"
	"strings"
)

// 稳定错误码前缀（spec §6.4）：Dart 侧按它映射文案，不再靠消息子串猜。
const (
	CodeFormatUnknown = "format-unknown:"
	CodeNoOutbounds   = "no-outbounds:"
	CodeURIInvalid    = "uri-invalid:"
	CodeBuildFailed   = "build-failed:"
	// CodeLimitExceeded：输入、节点数、输出或嵌套深度超出解析预算（见 limits.go）。
	CodeLimitExceeded = "limit-exceeded:"
)

// Error 是带稳定码的订阅解析错误；Error() 以 Code 开头。
type Error struct {
	Code string
	Msg  string
}

func (e *Error) Error() string { return e.Code + " " + e.Msg }

func fail(code, format string, args ...any) error {
	return &Error{Code: code, Msg: fmt.Sprintf(format, args...)}
}

// CodeOf 取错误链里的稳定码；不是订阅错误返回空串。
func CodeOf(err error) string {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

// Is 判断 err 是否带指定的码。
func Is(err error, code string) bool { return CodeOf(err) == code }

// CodeFromMessage 从原生异常消息里取码（Kotlin 把消息原样带回时用）；没有稳定前缀返回空串。
func CodeFromMessage(msg string) string {
	msg = strings.TrimSpace(msg)
	for _, c := range []string{CodeFormatUnknown, CodeNoOutbounds, CodeURIInvalid, CodeBuildFailed, CodeLimitExceeded} {
		if strings.HasPrefix(msg, c) {
			return c
		}
	}
	return ""
}
