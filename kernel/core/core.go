// Package core 是 gomobile 门面：Android 的 Kotlin 层只通过它访问内核。
// gomobile 只能传基本类型、string、[]byte、自有 struct / interface，所以复杂载荷一律是 JSON 字符串，
// 字段只增不改（spec §4.2）。生成的 Java 类位于 com.clashmiao.libcore.core。
//
// 本包只是薄壳：业务在 internal/* 与 engine，这里只做类型适配与错误前缀。
package core

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/luuuuke88/clashmiao/kernel/engine"
	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
	"github.com/luuuuke88/clashmiao/kernel/internal/warp"
)

// SetupOptions 是 Setup 的参数。
type SetupOptions struct {
	BasePath      string // 命令服务器的 unix socket 所在目录（应用私有目录）
	WorkingPath   string // 工作目录：cache.db、崩溃报告
	TempPath      string
	Debug         bool
	LogMaxLines   int32
	MemoryLimited bool
}

// Setup 必须在 NewEngine 之前调用（重复调用只是重新应用）。
func Setup(o *SetupOptions) error {
	if o == nil {
		return errors.New("setup: nil options")
	}
	return engine.Setup(engine.SetupOptions{
		BasePath:      o.BasePath,
		WorkingPath:   o.WorkingPath,
		TempPath:      o.TempPath,
		Debug:         o.Debug,
		LogMaxLines:   int(o.LogMaxLines),
		MemoryLimited: o.MemoryLimited,
	})
}

// Version 返回 sing-box 版本串。
func Version() string { return engine.Version() }

// GoVersion 返回 Go 版本与目标平台。
func GoVersion() string { return engine.GoVersion() }

// Parse 把订阅原文（inPath）解析成 {"outbounds":[…],"endpoints":[…]} 写到 outPath。
// 失败的错误以稳定前缀开头：format-unknown: / no-outbounds: / uri-invalid: / build-failed:。
// 参数顺序与旧门面 Mobile.parse 相同。
func Parse(outPath, inPath string, debug bool) error {
	return subscription.ParseFile(outPath, inPath, debug)
}

// BuildConfig 读订阅落盘文件（profilePath）与 configOptions JSON，产出运行配置 JSON 文本。
// 流程：读文件 → 读时清洗（旧 1.8 形态）→ 解码并校验选项 → 构建。
// 失败的错误以稳定前缀开头：option-invalid: / build-failed:。
func BuildConfig(profilePath, optionsJSON string) (string, error) {
	rawProfile, err := os.ReadFile(profilePath)
	if err != nil {
		return "", fmt.Errorf("%s read profile: %w", build.PrefixBuildFailed, err)
	}
	o, _, err := options.Decode([]byte(optionsJSON))
	if err != nil {
		return "", err
	}
	if err := o.Validate(); err != nil {
		return "", err
	}
	out, _, err := build.BuildJSON(rawProfile, o, build.AndroidEnv())
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// CheckConfig 只构造、不启动地检查配置。
func CheckConfig(content string) error { return engine.CheckConfig(content) }

// warpClient 是 WARP 注册用的 HTTP 客户端（测试里换成改道到本地假服务器的客户端）。
var warpClient = &http.Client{Timeout: 45 * time.Second}

// GenerateWarpConfig 向 Cloudflare 注册一台 WARP 设备（licenseKey 非空时绑定 license），
// 成功后（若给了旧的 accountID / accessToken）再删除旧设备，返回与旧 Dart 解析兼容的 JSON：
// {"account-id","access-token","log","config":{"private-key","local-address-ipv4","local-address-ipv6","peer-public-key","client-id"}}。
// 失败的错误以 warp-network: / warp-license-invalid: / warp-register-failed: 开头。
func GenerateWarpConfig(licenseKey, accountID, accessToken string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	return warp.Generate(ctx, warpClient, licenseKey, accountID, accessToken)
}
