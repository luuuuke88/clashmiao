package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 基于 UDP 的协议没有 TCP 握手可分片，加 tls.fragment 会被内核拒绝或毫无意义。
var udpBasedTypes = map[string]bool{"hysteria": true, "hysteria2": true, "tuic": true, "wireguard": true}

// applyTLSTricks 兑现 tls-tricks 里新内核能兑现的唯一一项：enable-fragment（spec §5.6）。
//
//	对 tls.enabled 的出站设 tls.fragment 与 tls.record_fragment；
//	reality 出站跳过（reality 自己握手，分片会破坏它）；UDP 类协议跳过。
//
// 其余键（fragment-size / fragment-sleep / mixed-sni-case / enable-padding）新内核没有对应能力，
// 值保留但不生效；用户打开了就给 warning，让「不生效」可见。
func applyTLSTricks(o *options.Options, nodes []cfg.Outbound, warnings *[]string) {
	t := o.TLSTricks
	if t.MixedSNICase {
		*warnings = append(*warnings, "tls-trick-unsupported: mixed-sni-case has no effect (not supported by the kernel)")
	}
	if t.EnablePadding {
		*warnings = append(*warnings, "tls-trick-unsupported: enable-padding has no effect (not supported by the kernel)")
	}
	if !t.EnableFragment {
		return
	}
	if t.FragmentSize != options.Default().TLSTricks.FragmentSize || t.FragmentSleep != options.Default().TLSTricks.FragmentSleep {
		*warnings = append(*warnings, "tls-trick-unsupported: fragment-size / fragment-sleep have no effect (the kernel only has on/off fragmenting)")
	}
	for _, n := range nodes {
		if udpBasedTypes[n.Type()] {
			continue
		}
		tls, ok := n["tls"].(map[string]any)
		if !ok {
			continue
		}
		if enabled, _ := tls["enabled"].(bool); !enabled {
			continue
		}
		if reality, ok := tls["reality"].(map[string]any); ok {
			if re, _ := reality["enabled"].(bool); re {
				continue
			}
		}
		tls["fragment"] = true
		tls["record_fragment"] = true
	}
}
