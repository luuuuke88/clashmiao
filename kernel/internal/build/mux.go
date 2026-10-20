package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

var muxTypes = map[string]bool{"vmess": true, "vless": true, "trojan": true, "shadowsocks": true}

// applyMux 在 mux.enable 时给 vmess / vless / trojan / shadowsocks 注入 multiplex：
// 节点自带 multiplex 的不动；reality 节点跳过（旧逻辑）；带 flow（xtls-rprx-vision 等）的 vless 同样不能多路复用。
func applyMux(o *options.Options, nodes []cfg.Outbound) {
	if !o.Mux.Enable {
		return
	}
	for _, n := range nodes {
		if !muxTypes[n.Type()] {
			continue
		}
		if _, has := n["multiplex"]; has {
			continue
		}
		if tls, ok := n["tls"].(map[string]any); ok {
			if reality, ok := tls["reality"].(map[string]any); ok {
				if re, _ := reality["enabled"].(bool); re {
					continue
				}
			}
		}
		if flow, _ := n["flow"].(string); flow != "" {
			continue
		}
		n["multiplex"] = map[string]any{
			"enabled":     true,
			"protocol":    o.Mux.Protocol,
			"max_streams": o.Mux.MaxStreams,
			"padding":     o.Mux.Padding,
		}
	}
}
