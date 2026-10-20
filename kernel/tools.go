//go:build tools

// 构建期工具依赖：空导入只是为了让 go.mod 锁住版本，不参与任何编译产物。
//
//   - gomobile / gobind：gomobile bind 的命令本体，版本由 go.mod 决定；
//   - sing-box/constant：发布构建用 -X 覆盖其中的 Version，这里同时锁住 sing-box 的 tag，
//     U2 起 engine 包会真正引用 sing-box。
package kernel

import (
	_ "github.com/sagernet/gomobile/cmd/gobind"
	_ "github.com/sagernet/gomobile/cmd/gomobile"
	_ "github.com/sagernet/sing-box/constant"
)
