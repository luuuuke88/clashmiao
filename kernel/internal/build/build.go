// Package build 把订阅里的节点（profile）与 configOptions 构建成运行配置（sing-box 1.14 schema）。
// 本包不 import sing-box：schema 类型自带（见 cfg），升级 sing-box 时靠黄金文件 diff 与 gate 里的
// CheckConfig / 真启动发现 schema 变化，而不是靠编译器。
package build

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 稳定错误码前缀（spec §6.4）。
const (
	PrefixBuildFailed = "build-failed:"
	PrefixNoOutbounds = "no-outbounds:"
)

// Profile 是订阅解析后的产物：只读 outbounds 与 endpoints，其余一律忽略。
type Profile struct {
	Outbounds []map[string]any `json:"outbounds"`
	Endpoints []map[string]any `json:"endpoints,omitempty"`
}

// ParseProfile 读取 {"outbounds":[...],"endpoints":[...]}。
func ParseProfile(raw []byte) (Profile, error) {
	var p Profile
	if err := json.Unmarshal(raw, &p); err != nil {
		return Profile{}, fmt.Errorf("%s profile is not valid JSON: %w", PrefixBuildFailed, err)
	}
	return p, nil
}

// Env 让构建可测试地区分 Android 与桌面。
type Env struct {
	GOOS          string // "android" 时才生成 override_android_vpn
	IPv6Supported bool   // 平台是否能承载 IPv6（决定 TUN 是否带 v6 地址）
}

// AndroidEnv 是 Android 上的环境。
func AndroidEnv() Env { return Env{GOOS: "android", IPv6Supported: true} }

// Build 产出运行配置 JSON 与警告。失败的错误以稳定前缀开头。
func Build(profile Profile, o *options.Options, env Env) ([]byte, []string, error) {
	if o == nil {
		return nil, nil, errors.New(PrefixBuildFailed + " nil options")
	}
	var warnings []string

	c := &cfg.Config{
		Log:          buildLog(o),
		Inbounds:     buildInbounds(o, env),
		Experimental: buildExperimental(o),
	}
	scaffold(c, profile, o, env, &warnings)

	// 配置里永远没有 clash_api；用户动过相关选项时给一条警告，让「选项被忽略」可见。
	if o.ClashAPINonDefault() {
		warnings = append(warnings, options.WarnClashAPI+": clash api is not built in; enable-clash-api / clash-api-port / web-secret have no effect")
	}

	raw, err := c.Marshal()
	if err != nil {
		return nil, nil, fmt.Errorf("%s %w", PrefixBuildFailed, err)
	}
	return append(raw, '\n'), warnings, nil
}

// ipv6Enabled：用户选了 v6 档且平台能承载。
func ipv6Enabled(o *options.Options, env Env) bool {
	return o.IPv6Mode != "ipv4_only" && env.IPv6Supported
}
