// Package core 是 gomobile 门面。U1 阶段只有占位，用来验证构建流水线
// （链接参数、tags、版本覆盖、对齐、proguard）；真正的门面见 U12。
package core

import "github.com/sagernet/sing-box/constant"

// Version 返回内置的 sing-box 版本串（发布构建用 -X 覆盖）。
func Version() string { return constant.Version }
