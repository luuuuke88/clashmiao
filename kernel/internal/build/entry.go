package build

import (
	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// BuildJSON 是门面 BuildConfig 的实现体：读订阅落盘文件（新 Parse 的产物，或升级前旧内核写下的
// 1.8 形态），先做读时清洗（spec §6.3，幂等），再构建运行配置。
// 读时清洗的警告并入返回的 warnings；清洗不改变「悬空 / 成环 detour 一律报错」的规则。
func BuildJSON(rawProfile []byte, o *options.Options, env Env) ([]byte, []string, error) {
	p, err := ParseProfile(rawProfile)
	if err != nil {
		return nil, nil, err
	}
	res := legacy.Clean(p.Outbounds, p.Endpoints, legacy.CleanOptions{RemapTarget: remapTarget(o)})
	p.Outbounds, p.Endpoints = res.Outbounds, res.Endpoints
	raw, warnings, err := Build(p, o, env)
	if err != nil {
		return nil, nil, err
	}
	return raw, append(append([]string{}, res.Warnings...), warnings...), nil
}

// remapTarget 是「指向被丢弃的直连类出站」的 detour 的新目标。
// 目前恒为 direct；U13 落地 WARP 后，proxy_over_warp 下改为 warp。
func remapTarget(*options.Options) string { return TagDirect }
