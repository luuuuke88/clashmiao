package engine

import (
	"errors"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// 启动失败的前缀：Kotlin 据此映射 FailureCode.CreateService / StartService。
const (
	PrefixCreateService = "create-service:"
	PrefixStartService  = "start-service:"
)

// classifyStartError 区分「配置建不出服务」与「服务启动失败」。
// libbox 的 StartOrReloadService 把两者混在同一个错误里；失败路径上再对配置做一次只构造不启动的检查：
// 它也失败 → 建服务阶段的错误，否则是启动阶段的错误（比如端口被占、DNS 服务器 detour 指向空 direct）。
func classifyStartError(err error, configJSON string) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, ErrCanceled) {
		return err
	}
	if checkErr := libbox.CheckConfig(configJSON); checkErr != nil {
		return &StartError{Prefix: PrefixCreateService, Err: err}
	}
	return &StartError{Prefix: PrefixStartService, Err: err}
}

// StartError 是带分类前缀的启动错误，Error() 以前缀开头。
type StartError struct {
	Prefix string
	Err    error
}

func (e *StartError) Error() string { return e.Prefix + " " + e.Err.Error() }
func (e *StartError) Unwrap() error { return e.Err }
