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
	asm, err := assembleOutbounds(profile, o, &warnings)
	if err != nil {
		return nil, nil, err
	}
	// 业务出口：常态 select；warp_over_proxy 时是 warp（见 warp_policy.go）。
	// dns-remote 的 detour、route.final、proxy 规则的目标都取这一个变量。
	egress, warpEp, err := ApplyWarp(asm, o, &warnings)
	if err != nil {
		return nil, nil, err
	}
	c.Outbounds, c.Endpoints = asm.Outbounds, asm.Endpoints

	// WARP 对端的域名（若 clean-ip 写成域名）与各节点的服务器域名一样，必须直连解析。
	dialers := asm.Entities
	if warpEp != nil {
		dialers = append(append([]map[string]any{}, dialers...), warpEp)
	}
	c.DNS, err = BuildDNS(dnsInput{
		Options:       o,
		Egress:        egress,
		HasTun:        o.EnableTun,
		DirectDomains: nodeHostnames(dialers...),
	}, &warnings)
	if err != nil {
		return nil, nil, err
	}
	dropSubscriptionResolvers(c, &warnings)
	if c.Route, err = BuildRoute(o, env, egress, &warnings); err != nil {
		return nil, nil, err
	}
	if err := CheckDNSDeps(c); err != nil {
		return nil, nil, err
	}
	if err := ValidateGraph(c); err != nil {
		return nil, nil, err
	}

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

// dropSubscriptionResolvers 去掉订阅节点自带的 domain_resolver：订阅的 dns 块整块丢弃、DNS 服务器由构建器重建，
// 它写的服务器 tag 在运行配置里要么不存在（悬空引用，启动即失败），要么碰巧与我们的 tag 重名而改变解析路径、
// 甚至绕成环。域名节点统一用 route.default_domain_resolver 解析。
func dropSubscriptionResolvers(c *cfg.Config, warnings *[]string) {
	drop := func(tag string, m map[string]any) {
		if _, ok := m["domain_resolver"]; !ok {
			return
		}
		delete(m, "domain_resolver")
		*warnings = append(*warnings, fmt.Sprintf("domain-resolver-dropped: %q uses a subscription-defined domain_resolver, replaced by the default resolver", tag))
	}
	for _, o := range c.Outbounds {
		drop(o.Tag(), o)
	}
	for _, e := range c.Endpoints {
		drop(e.Tag(), e)
	}
}
