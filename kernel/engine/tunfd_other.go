//go:build !darwin

package engine

// TunnelFileDescriptor 只在 Apple 平台有意义，其它平台恒为 -1。
func TunnelFileDescriptor() int32 { return -1 }
