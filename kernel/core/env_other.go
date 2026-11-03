//go:build !ios

package core

import "github.com/luuuuke88/clashmiao/kernel/internal/build"

// platformEnv 是 BuildConfig 用的构建环境：Android 构建与主机测试都取 Android 环境（现状）。
func platformEnv() build.Env { return build.AndroidEnv() }
