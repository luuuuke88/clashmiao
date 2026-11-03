//go:build ios

package engine

// iOS 上内核总是跑在 Packet Tunnel 扩展里：影响 TUN 的建立方式与内核的 OOM 策略。
const underNetworkExtension = true
