//go:build ios

package core

import "github.com/luuuuke88/clashmiao/kernel/internal/build"

// platformEnv 是 BuildConfig 用的构建环境：iOS 构建取 iOS 环境。
func platformEnv() build.Env { return build.IOSEnv() }
