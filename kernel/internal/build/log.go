package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// buildLog：默认不写文件（日志走命令服务器的环形缓冲 → Platform.WriteLog）。
func buildLog(o *options.Options) *cfg.Log {
	return &cfg.Log{Level: o.LogLevel, Timestamp: true}
}
