package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// buildExperimental 只生成 cache_file：选择组的选择在重启后保留，开 fake DNS 时还存 fakeip 映射。
// **永远不生成 clash_api**（App 从未使用它，开着只增加本机攻击面；见 spec §5.4）。
func buildExperimental(o *options.Options) *cfg.Experimental {
	return &cfg.Experimental{CacheFile: &cfg.CacheFile{
		Enabled:     true,
		Path:        "cache.db",
		StoreFakeIP: o.EnableFakeDNS,
	}}
}
