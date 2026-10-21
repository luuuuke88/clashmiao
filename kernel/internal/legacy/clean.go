// Package legacy 清洗旧内核（1.8 schema）产出的订阅文件：用户已落盘的订阅是旧 Parse 的产物，
// 升级后不做数据迁移，而是「读时清洗」（spec §6.3）。Clean 是幂等的纯函数，
// 新 Parse 与 BuildConfig 对 outbounds / endpoints 都先过它。本包不 import sing-box。
package legacy

import (
	"fmt"
	"sort"
	"strings"
)

// CleanOptions 控制重映射目标。
type CleanOptions struct {
	// RemapTarget 是「指向被丢弃的直连类出站」的 detour 的新目标：
	// Parse 传 direct；BuildConfig 在 proxy_over_warp 下传 warp，其余传 direct。空串按 direct。
	RemapTarget string
}

// ReservedTags 是构建器的预置 / 保留 tag（与 build.reservedTags 同一份清单，build 的测试钉住两者一致）：
// 订阅里的节点不得占用，Clean 在重映射之前先给占用者改名，见 Clean 的第 ③ 步。
var ReservedTags = []string{"select", "auto", "direct", "direct-fragment", "bypass", "block", "warp"}

// Remap 记录一次 detour 重映射。
type Remap struct {
	Node string // 持有 detour 的出站 / 端点的 tag
	Old  string // 被丢弃的直连类出站的 tag
	New  string // 重映射目标
}

// Result 是清洗结果。
type Result struct {
	Outbounds []map[string]any
	Endpoints []map[string]any
	Warnings  []string
	// Removed 记录被丢弃的出站：tag → type（在丢弃之前记账，重映射与上层校验都靠它）。
	Removed map[string]string
	// Remapped 是已重映射的 detour 引用。
	Remapped []Remap
}

// droppedType 与构建器丢弃订阅自带分组 / 直连类的口径一致（含 select / url-test 等写法与 custom）。
func droppedType(t string) bool {
	return dropKind(t) != ""
}

// dropKind 返回规范化后的被丢弃类型，不丢弃返回空串。
func dropKind(t string) string {
	switch n := strings.ToLower(strings.NewReplacer("-", "", "_", "").Replace(strings.TrimSpace(t))); n {
	case "direct", "block", "dns", "selector", "urltest", "custom":
		return n
	case "select":
		return "selector"
	}
	return ""
}

// Clean 在同一个函数里按固定顺序一次做完（不留悬空引用）：
//
//	①记账：删除任何实体之前，先记下将被丢弃的 tag → type；
//	②清洗与丢弃：wireguard 出站转端点；丢弃 block / dns / selector / urltest / direct；删除已不存在的字段；
//	③避让保留 tag：节点 / 端点的 tag 与预置 tag（direct、warp……）冲突的先改名为「tag (2)」，别的节点对它的 detour
//	  一并改写。必须先于重映射：重映射生成的 detour 才是真正指向预置 direct / warp 的引用，若改名排在它后面，
//	  这些新引用会被当成「指向那个同名代理节点」而被错误地改走；
//	④重映射：所有出站与端点的 detour，凡指向被丢弃的直连类（type: direct）的，改指 RemapTarget；
//	⑤返回清洗后的实体、warning 与已重映射清单。
//
// 不重映射的引用：指向被丢弃的 selector / urltest / block / dns，或从未存在的 tag——交给构建器的
// ValidateDetours 报 ErrDetourDangling，这里不替用户猜。输入不会被修改；未知字段原样保留。
func Clean(outbounds, endpoints []map[string]any, opt CleanOptions) Result {
	target := opt.RemapTarget
	if target == "" {
		target = "direct"
	}
	res := Result{Removed: map[string]string{}}

	// ① 记账。
	removedDirect := map[string]bool{}
	for _, o := range outbounds {
		if k := dropKind(str(o["type"])); k != "" {
			tag := str(o["tag"])
			res.Removed[tag] = str(o["type"])
			if k == "direct" {
				removedDirect[tag] = true
			}
		}
	}

	// ② 清洗与丢弃。
	for _, o := range outbounds {
		if droppedType(str(o["type"])) {
			continue
		}
		c := cloneMap(o)
		if str(c["type"]) == "wireguard" {
			res.Endpoints = append(res.Endpoints, wireguardEndpoint(c))
			continue
		}
		stripLegacyFields(c)
		res.Outbounds = append(res.Outbounds, c)
	}
	var kept []map[string]any
	for _, e := range endpoints {
		c := cloneMap(e)
		stripLegacyFields(c)
		kept = append(kept, c)
	}
	res.Endpoints = append(kept, res.Endpoints...)

	// ③ 避让保留 tag（先于重映射，见函数注释）。
	renamed := avoidReservedTags(&res, removedDirect)

	// ④ 重映射。
	remap := func(list []map[string]any) {
		for _, n := range list {
			d, _ := n["detour"].(string)
			if d == "" {
				continue
			}
			if !removedDirect[d] {
				if nt, ok := renamed[d]; ok {
					n["detour"] = nt
				}
				continue
			}
			n["detour"] = target
			res.Remapped = append(res.Remapped, Remap{Node: str(n["tag"]), Old: d, New: target})
			res.Warnings = append(res.Warnings, fmt.Sprintf("detour-remapped: %q detoured to the removed direct outbound %q, now %q", str(n["tag"]), d, target))
		}
	}
	remap(res.Outbounds)
	remap(res.Endpoints)
	return res
}

// avoidReservedTags 把占用预置 tag 的节点 / 端点改名，返回「旧 tag → 新 tag」。
// 被改名的 tag 若同时是被丢弃直连类出站的 tag，引用仍按「指向被丢弃的直连类」处理（removedDirect 优先）。
func avoidReservedTags(res *Result, removedDirect map[string]bool) map[string]string {
	reserved := map[string]bool{}
	for _, t := range ReservedTags {
		reserved[t] = true
	}
	used := map[string]bool{}
	for t := range reserved {
		used[t] = true
	}
	for t := range res.Removed {
		used[t] = true
	}
	var all []map[string]any
	all = append(all, res.Outbounds...)
	all = append(all, res.Endpoints...)
	for _, n := range all {
		used[str(n["tag"])] = true
	}
	renamed := map[string]string{}
	for _, n := range all {
		tag := str(n["tag"])
		if !reserved[tag] {
			continue
		}
		var nt string
		for i := 2; ; i++ {
			if c := fmt.Sprintf("%s (%d)", tag, i); !used[c] {
				nt = c
				break
			}
		}
		used[nt] = true
		renamed[tag] = nt
		n["tag"] = nt
		res.Warnings = append(res.Warnings, fmt.Sprintf("tag-renamed: %q conflicts with a built-in tag, renamed to %q", tag, nt))
	}
	return renamed
}

// legacyFields 是旧内核私有、新内核不认的字段（出现在出站 / 端点顶层或 tls 里都删）。
var legacyFields = []string{"tls_fragment", "tls_tricks", "domain_strategy", "sniff", "sniff_override_destination", "sniff_timeout", "sniff_override"}

// stripLegacyFields 删除旧字段；保留 tcp_fast_open、udp_fragment 等仍有效的字段。
func stripLegacyFields(m map[string]any) {
	for _, f := range legacyFields {
		delete(m, f)
	}
	if tls, ok := m["tls"].(map[string]any); ok {
		for _, f := range legacyFields {
			delete(tls, f)
		}
	}
}

// wireguardEndpoint 把 1.8 的 wireguard 出站转成 1.14 的 wireguard 端点。
//
//	server / server_port        → peers[0].address / port
//	peer_public_key             → peers[0].public_key
//	pre_shared_key              → peers[0].pre_shared_key
//	reserved                    → peers[0].reserved
//	allowed_ips（缺省）          → ["0.0.0.0/0", "::/0"]
//	local_address               → address
//	system_interface            → system
//	interface_name              → name
//	private_key / mtu / workers / detour 及其它拨号字段原样保留
//
// 出站已带 peers（1.11 写法）时保留它，只补顶层映射。
func wireguardEndpoint(o map[string]any) map[string]any {
	ep := map[string]any{"type": "wireguard"}
	peer := map[string]any{}
	hasPeers := false
	for k, v := range o {
		switch k {
		case "type":
		case "server":
			peer["address"] = v
		case "server_port":
			peer["port"] = v
		case "peer_public_key":
			peer["public_key"] = v
		case "pre_shared_key":
			peer["pre_shared_key"] = v
		case "reserved":
			peer["reserved"] = v
		case "allowed_ips":
			peer["allowed_ips"] = v
		case "local_address":
			ep["address"] = v
		case "system_interface":
			ep["system"] = v
		case "interface_name":
			ep["name"] = v
		case "peers":
			ep["peers"] = v
			hasPeers = true
		default:
			if legacyField(k) {
				continue
			}
			ep[k] = v
		}
	}
	if !hasPeers {
		if _, ok := peer["allowed_ips"]; !ok {
			peer["allowed_ips"] = []any{"0.0.0.0/0", "::/0"}
		}
		ep["peers"] = []any{peer}
	}
	return ep
}

func legacyField(k string) bool {
	for _, f := range legacyFields {
		if f == k {
			return true
		}
	}
	return false
}

func str(x any) string { s, _ := x.(string); return s }

func cloneMap(m map[string]any) map[string]any {
	out := make(map[string]any, len(m))
	for k, v := range m {
		out[k] = cloneValue(v)
	}
	return out
}

func cloneValue(v any) any {
	switch t := v.(type) {
	case map[string]any:
		return cloneMap(t)
	case []any:
		out := make([]any, len(t))
		for i, e := range t {
			out[i] = cloneValue(e)
		}
		return out
	}
	return v
}

// NeedsCleaning 判断一个出站是否带「需要清洗的旧形态」，口径是 spec §6.5 的固定清单，与 Dart 的 JSON 直通判据共用：
//
//	type 为 wireguard / dns / block 的出站；
//	出站顶层出现 tls_fragment / domain_strategy / sniff / sniff_override_destination，或 tls 里出现 tls_tricks。
//
// 订阅自带的 selector / urltest / direct 不在清单里（它们由构建器按规则丢弃，不阻止直通）。
// Clean 实际删除的旧字段比这份清单多（如 sniff_timeout），清单只管「是否必须走 Parse」。
// 共享夹具 testdata/shared/legacy-shapes.json 钉住两边的一致。
func NeedsCleaning(o map[string]any) bool {
	switch str(o["type"]) {
	case "wireguard", "dns", "block":
		return true
	}
	for _, f := range []string{"tls_fragment", "domain_strategy", "sniff", "sniff_override_destination"} {
		if _, ok := o[f]; ok {
			return true
		}
	}
	if tls, ok := o["tls"].(map[string]any); ok {
		if _, ok := tls["tls_tricks"]; ok {
			return true
		}
	}
	return false
}

// SortedRemoved 便于测试与日志稳定输出。
func (r Result) SortedRemoved() []string {
	out := make([]string, 0, len(r.Removed))
	for tag, typ := range r.Removed {
		out = append(out, tag+":"+typ)
	}
	sort.Strings(out)
	return out
}
