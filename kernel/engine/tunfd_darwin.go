//go:build darwin

package engine

import "github.com/sagernet/sing-box/experimental/libbox"

// TunnelFileDescriptor 扫描本进程里的 utun 控制 socket，返回 Packet Tunnel 的 fd；找不到返回 -1。
// 只在 Apple 平台有意义（GOOS=ios 同样满足 darwin 标签）。
func TunnelFileDescriptor() int32 { return libbox.GetTunnelFileDescriptor() }
