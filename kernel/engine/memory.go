package engine

import "runtime/debug"

const (
	memoryLimitedGCPercent = 10
	memoryLimitedSoftLimit = 30 << 20
)

// applyMemoryLimit 复刻旧内核「受限内存」档位里能复刻的部分：GC 百分比 10 + 软上限 30 MiB。
// 旧内核还有一个 45 MiB 的连接上限，新 libbox 没有对应物，也不启用它的 OOM killer（见 spec §5.5）。
// 必须在 libbox.Setup 之后调用：Setup 会把软上限重置成「不限」。
func applyMemoryLimit(limited bool) {
	if !limited {
		return
	}
	debug.SetGCPercent(memoryLimitedGCPercent)
	debug.SetMemoryLimit(memoryLimitedSoftLimit)
}
