// Package gate 是配置构建器的测试闸门：黄金文件、不变量、主机适配副本与真启动的公用部分。
// 它只被 _test.go 使用，不进 core；允许 import sing-box 与 engine（规则见计划的 Go 侧约定）。
//
// 闸门分两个作用域，断言互不替代（spec §7.1）：
//   - 原始（Android）配置上的断言，不启动：黄金文件逐字节比较与本文件的 CheckInvariants；
//   - 主机适配副本上的断言：HostAdapt 只允许白名单改动，再做 CheckConfig 与真 Start。
package gate

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"sort"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

type obj = map[string]any

// forbiddenKeys 是 1.14 起已移除或我们明确不生成的键，出现在配置任何位置都算违规。
var forbiddenKeys = map[string]string{
	"inet4_address":              "旧 TUN 地址字段（1.10 起改为 address）",
	"inet6_address":              "旧 TUN 地址字段（1.10 起改为 address）",
	"geoip":                      "geoip 规则已移除（1.12 起改规则集）",
	"geosite":                    "geosite 规则已移除（1.12 起改规则集）",
	"tls_tricks":                 "旧内核私有字段",
	"tls_fragment":               "旧内核私有字段（分片用 tls.fragment）",
	"disable_color":              "旧内核私有字段",
	"clash_api":                  "内核不内置 clash_api，配置里永不生成",
	"sniff":                      "入站嗅探字段已移除（1.13 起是路由动作）",
	"sniff_override_destination": "入站嗅探字段已移除",
	"sniff_timeout":              "入站嗅探字段已移除",
	"sniff_override":             "入站嗅探字段已移除",
}

// CheckInvariants 对一份原始（Android）配置做全部结构断言，返回违规列表（空即通过）。
func CheckInvariants(raw []byte, o *options.Options, env build.Env) []string {
	var c obj
	if err := json.Unmarshal(raw, &c); err != nil {
		return []string{"配置不是合法 JSON: " + err.Error()}
	}
	v := &violations{}
	scanForbidden(v, "", c)

	g := newGraph(c)
	g.checkRefs(v)
	g.checkDetourCycles(v)
	g.checkMemberCycles(v)
	checkTags(v, g, c, o, env)
	checkOrderAndFinals(v, g, c, o)
	checkWarpMembership(v, g)
	checkWarpGraph(v, raw, o)
	checkDNSDeps(v, raw)
	return v.list
}

type violations struct{ list []string }

func (v *violations) addf(format string, args ...any) {
	v.list = append(v.list, fmt.Sprintf(format, args...))
}

// ---- 通用遍历 ----

func asMap(x any) obj       { m, _ := x.(map[string]any); return m }
func asSlice(x any) []any   { s, _ := x.([]any); return s }
func asString(x any) string { s, _ := x.(string); return s }
func strList(x any) []string {
	var out []string
	switch t := x.(type) {
	case string:
		out = append(out, t)
	case []any:
		for _, e := range t {
			if s, ok := e.(string); ok {
				out = append(out, s)
			}
		}
	}
	return out
}

func contains(list []string, s string) bool {
	for _, e := range list {
		if e == s {
			return true
		}
	}
	return false
}

func sortedKeys(m obj) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// scanForbidden 递归扫描禁用键。path 形如 "inbounds[].domain_strategy"（数组下标折叠成 []）。
func scanForbidden(v *violations, path string, x any) {
	switch t := x.(type) {
	case map[string]any:
		for _, k := range sortedKeys(t) {
			p := k
			if path != "" {
				p = path + "." + k
			}
			if why, ok := forbiddenKeys[k]; ok && why != "" {
				v.addf("禁用键 %s：%s", p, why)
			}
			if strings.HasPrefix(k, "sniff") {
				v.addf("禁用键 %s：入站嗅探字段已移除（1.13 起是路由动作）", p)
			}
			if strings.HasPrefix(k, "inet4_route_") || strings.HasPrefix(k, "inet6_route_") {
				v.addf("禁用键 %s：旧 TUN 路由字段（1.10 起改为 route_address 等）", p)
			}
			if k == "domain_strategy" && strings.HasPrefix(path, "inbounds[]") {
				v.addf("禁用键 %s：入站 domain_strategy 已移除（1.13 起改为路由 / DNS 策略）", p)
			}
			if k == "address" && path == "dns.servers[]" {
				v.addf("禁用键 %s：DNS 服务器旧 address 格式已移除（1.14 起用 type + server）", p)
			}
			if k == "outbound" && asString(t[k]) == "dns-out" {
				v.addf("禁用值 %s=dns-out：dns 出站已移除（1.13 起用 hijack-dns 动作）", p)
			}
			scanForbidden(v, p, t[k])
		}
	case []any:
		for _, e := range t {
			scanForbidden(v, path+"[]", e)
		}
	}
}

// ---- 标签图 ----

type graph struct {
	cfg       obj
	inbounds  map[string]obj
	nodes     map[string]obj // outbounds ∪ endpoints
	endpoints map[string]bool
	dns       map[string]obj
	dupTags   []string
}

func newGraph(c obj) *graph {
	g := &graph{cfg: c, inbounds: map[string]obj{}, nodes: map[string]obj{}, endpoints: map[string]bool{}, dns: map[string]obj{}}
	for _, e := range asSlice(c["inbounds"]) {
		if m := asMap(e); m != nil {
			g.inbounds[asString(m["tag"])] = m
		}
	}
	add := func(list []any, endpoint bool) {
		for _, e := range list {
			m := asMap(e)
			if m == nil {
				continue
			}
			tag := asString(m["tag"])
			if _, dup := g.nodes[tag]; dup {
				g.dupTags = append(g.dupTags, tag)
			}
			g.nodes[tag] = m
			if endpoint {
				g.endpoints[tag] = true
			}
		}
	}
	add(asSlice(c["outbounds"]), false)
	add(asSlice(c["endpoints"]), true)
	if d := asMap(c["dns"]); d != nil {
		for _, e := range asSlice(d["servers"]) {
			if m := asMap(e); m != nil {
				g.dns[asString(m["tag"])] = m
			}
		}
	}
	return g
}

func isGroup(m obj) bool { t := asString(m["type"]); return t == "selector" || t == "urltest" }

// isEmptyDirect：只有 type / tag（其余键全是零值）的 direct 出站。
// sing-box 对它的判定是「与默认值 DeepEqual」，作为 detour 目标时 Start 会拒绝（CheckConfig 放行）。
func isEmptyDirect(m obj) bool {
	if asString(m["type"]) != "direct" {
		return false
	}
	for k, val := range m {
		if k == "type" || k == "tag" {
			continue
		}
		switch t := val.(type) {
		case nil:
		case bool:
			if t {
				return false
			}
		case string:
			if t != "" {
				return false
			}
		case float64:
			if t != 0 {
				return false
			}
		case []any:
			if len(t) != 0 {
				return false
			}
		case map[string]any:
			if len(t) != 0 {
				return false
			}
		default:
			return false
		}
	}
	return true
}

// resolverTag 取 domain_resolver：字符串，或 {"server": "..."}。
func resolverTag(x any) string {
	if s, ok := x.(string); ok {
		return s
	}
	if m := asMap(x); m != nil {
		return asString(m["server"])
	}
	return ""
}

func (g *graph) checkRefs(v *violations) {
	for _, t := range g.dupTags {
		v.addf("出站 / 端点 tag 重复: %s", t)
	}
	// 出站、端点
	for tag, m := range g.nodes {
		if isGroup(m) {
			members := strList(m["outbounds"])
			for _, mem := range members {
				if _, ok := g.nodes[mem]; !ok {
					v.addf("%s 的成员 %q 不存在", tag, mem)
				}
			}
			if asString(m["type"]) == "selector" {
				if def := asString(m["default"]); def != "" && !contains(members, def) {
					v.addf("selector %s 的 default %q 不在成员里（CheckConfig 放行，Start 会拒绝）", tag, def)
				}
			}
		}
		if d := asString(m["detour"]); d != "" {
			target, ok := g.nodes[d]
			switch {
			case !ok:
				v.addf("%s 的 detour %q 不存在", tag, d)
			case isEmptyDirect(target):
				v.addf("%s 的 detour 指向空 direct %q（CheckConfig 放行，Start 会拒绝）", tag, d)
			}
		}
		if r := resolverTag(m["domain_resolver"]); r != "" {
			if _, ok := g.dns[r]; !ok {
				v.addf("%s 的 domain_resolver %q 不是 DNS 服务器", tag, r)
			}
		}
	}
	// DNS
	d := asMap(g.cfg["dns"])
	if d == nil {
		v.addf("缺少 dns 块")
		return
	}
	for tag, m := range g.dns {
		if det := asString(m["detour"]); det != "" {
			target, ok := g.nodes[det]
			switch {
			case !ok:
				v.addf("DNS 服务器 %s 的 detour %q 不存在", tag, det)
			case isEmptyDirect(target):
				v.addf("DNS 服务器 %s 的 detour 指向空 direct %q（CheckConfig 放行，Start 会拒绝）", tag, det)
			}
		}
		if r := resolverTag(m["domain_resolver"]); r != "" {
			if _, ok := g.dns[r]; !ok {
				v.addf("DNS 服务器 %s 的 domain_resolver %q 不存在", tag, r)
			} else if r == tag {
				v.addf("DNS 服务器 %s 的 domain_resolver 指向自己", tag)
			}
		}
	}
	if f := asString(d["final"]); f != "" {
		if _, ok := g.dns[f]; !ok {
			v.addf("dns.final %q 不存在", f)
		}
	}
	for i, e := range asSlice(d["rules"]) {
		r := asMap(e)
		if s := asString(r["server"]); s != "" {
			if _, ok := g.dns[s]; !ok {
				v.addf("dns.rules[%d].server %q 不存在", i, s)
			}
		}
		for _, in := range strList(r["inbound"]) {
			if _, ok := g.inbounds[in]; !ok {
				v.addf("dns.rules[%d].inbound %q 不存在", i, in)
			}
		}
	}
	// 路由
	rt := asMap(g.cfg["route"])
	if rt == nil {
		v.addf("缺少 route 块")
		return
	}
	if f := asString(rt["final"]); f != "" {
		if _, ok := g.nodes[f]; !ok {
			v.addf("route.final %q 不存在", f)
		}
	}
	if r := resolverTag(rt["default_domain_resolver"]); r != "" {
		if _, ok := g.dns[r]; !ok {
			v.addf("route.default_domain_resolver %q 不是 DNS 服务器", r)
		}
	}
	for i, e := range asSlice(rt["rules"]) {
		r := asMap(e)
		if out := asString(r["outbound"]); out != "" {
			if _, ok := g.nodes[out]; !ok {
				v.addf("route.rules[%d].outbound %q 不存在", i, out)
			}
		}
		for _, in := range strList(r["inbound"]) {
			if _, ok := g.inbounds[in]; !ok {
				v.addf("route.rules[%d].inbound %q 不存在", i, in)
			}
		}
	}
}

// checkDetourCycles：出站 / 端点的 detour 链无环。
func (g *graph) checkDetourCycles(v *violations) {
	for _, start := range sortedMapKeys(g.nodes) {
		seen := map[string]bool{start: true}
		cur := start
		for {
			next := asString(g.nodes[cur]["detour"])
			if next == "" {
				break
			}
			if seen[next] {
				v.addf("detour 成环: 从 %s 出发回到 %s", start, next)
				break
			}
			if _, ok := g.nodes[next]; !ok {
				break
			}
			seen[next] = true
			cur = next
		}
	}
}

// checkMemberCycles：selector / urltest 的成员关系无环。
func (g *graph) checkMemberCycles(v *violations) {
	const (
		white = iota
		grey
		black
	)
	state := map[string]int{}
	var visit func(tag string) bool
	visit = func(tag string) bool {
		m, ok := g.nodes[tag]
		if !ok || !isGroup(m) {
			return false
		}
		switch state[tag] {
		case grey:
			return true
		case black:
			return false
		}
		state[tag] = grey
		for _, mem := range strList(m["outbounds"]) {
			if visit(mem) {
				state[tag] = black
				return true
			}
		}
		state[tag] = black
		return false
	}
	for _, tag := range sortedMapKeys(g.nodes) {
		if visit(tag) {
			v.addf("分组成员关系成环（含 %s）", tag)
			return
		}
	}
}

func sortedMapKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// ---- 必有 tag 与条件 tag ----

// 始终要有的 tag。
var (
	requiredOutbounds = []string{"select", "auto", "direct", "bypass", "direct-fragment"}
	requiredDNS       = []string{"dns-remote", "dns-direct", "dns-local"}
	requiredInbounds  = []string{"mixed-in"}
)

func checkTags(v *violations, g *graph, c obj, o *options.Options, env build.Env) {
	for _, t := range requiredOutbounds {
		if _, ok := g.nodes[t]; !ok {
			v.addf("缺少必有出站 %s", t)
		}
	}
	for _, t := range requiredDNS {
		if _, ok := g.dns[t]; !ok {
			v.addf("缺少必有 DNS 服务器 %s", t)
		}
	}
	for _, t := range requiredInbounds {
		if _, ok := g.inbounds[t]; !ok {
			v.addf("缺少必有入站 %s", t)
		}
	}

	cond := func(name string, present, want bool) {
		switch {
		case want && !present:
			v.addf("条件 tag %s 应当存在却缺失", name)
		case !want && present:
			v.addf("条件 tag %s 不该存在却存在", name)
		}
	}
	_, hasTun := g.inbounds["tun-in"]
	cond("tun-in", hasTun, o.EnableTun)
	_, hasDNSIn := g.inbounds["dns-in"]
	cond("dns-in", hasDNSIn, o.LocalDNSPort != 0)
	_, hasFake := g.dns["dns-fake"]
	cond("dns-fake", hasFake, o.EnableFakeDNS && hasTun)
	_, hasBootstrap := g.dns["dns-bootstrap"]
	cond("dns-bootstrap", hasBootstrap, g.hasDomainTypeDNS())
	_, hasWarp := g.nodes["warp"]
	cond("warp", hasWarp, o.Warp.Enable)

	// 没有 tun-in 时，任何位置都不得再引用它。
	if !hasTun {
		if where := findString(c, "tun-in"); where != "" {
			v.addf("没有 tun-in，却仍有引用: %s", where)
		}
	}
	if !hasFake {
		if where := findString(c, "dns-fake"); where != "" {
			v.addf("没有 dns-fake，却仍有引用: %s", where)
		}
	}

	rt := asMap(c["route"])
	override, _ := rt["override_android_vpn"].(bool)
	if override != (env.GOOS == "android") {
		v.addf("override_android_vpn=%v 与 Env.GOOS=%q 不符（仅 Android 才生成）", override, env.GOOS)
	}
}

// hasDomainTypeDNS：是否有（自举器以外的）DNS 服务器的 server 是域名而非 IP 字面量。
func (g *graph) hasDomainTypeDNS() bool {
	for tag, m := range g.dns {
		if tag == "dns-bootstrap" {
			continue
		}
		switch asString(m["type"]) {
		case "local", "fakeip", "dhcp", "hosts", "resolved":
			continue
		}
		srv := asString(m["server"])
		if srv == "" {
			continue
		}
		if _, err := netip.ParseAddr(srv); err != nil {
			return true
		}
	}
	return false
}

// findString 在整份配置里找值等于 s 的字符串（含数组元素），返回第一处路径。
func findString(x any, s string) string {
	var walk func(path string, x any) string
	walk = func(path string, x any) string {
		switch t := x.(type) {
		case string:
			if t == s {
				return path
			}
		case []any:
			for i, e := range t {
				if r := walk(fmt.Sprintf("%s[%d]", path, i), e); r != "" {
					return r
				}
			}
		case map[string]any:
			for _, k := range sortedKeys(t) {
				// 入站自己的 tag 不算引用（有 tun-in 才会走到这里的反向检查，这里只在它不该存在时调用）。
				if r := walk(path+"."+k, t[k]); r != "" {
					return r
				}
			}
		}
		return ""
	}
	return walk("$", x)
}

// ---- 规则顺序与最终出口 ----

// ExpectedRouteFinal 是 route.final 应有的值：业务出口，常态 select；warp_over_proxy 时是 warp。
func ExpectedRouteFinal(o *options.Options) string {
	if p, ok := build.PolicyFor(o); ok {
		return p.Egress
	}
	return "select"
}

func checkOrderAndFinals(v *violations, g *graph, c obj, o *options.Options) {
	rt := asMap(c["route"])
	sniffAt, hijackAt := -1, -1
	for i, e := range asSlice(rt["rules"]) {
		switch asString(asMap(e)["action"]) {
		case "sniff":
			if sniffAt < 0 {
				sniffAt = i
			}
		case "hijack-dns":
			if hijackAt < 0 {
				hijackAt = i
			}
		}
	}
	switch {
	case sniffAt < 0:
		v.addf("route.rules 里没有 sniff 动作")
	case hijackAt < 0:
		v.addf("route.rules 里没有 hijack-dns 动作")
	case sniffAt > hijackAt:
		v.addf("sniff（第 %d 条）必须在 hijack-dns（第 %d 条）之前", sniffAt, hijackAt)
	}
	if f := asString(asMap(c["dns"])["final"]); f != "dns-remote" {
		v.addf("dns.final = %q，应为 dns-remote", f)
	}
	if want, got := ExpectedRouteFinal(o), asString(rt["final"]); got != want {
		v.addf("route.final = %q，应为 %q", got, want)
	}
}

// checkWarpGraph：WARP 启用时按模式逐条断言出站图（断言与装配读同一张策略表，见 build.CheckWarpGraph）；
// 未启用时配置里不得出现 warp 端点，dns-remote 的 detour 必须是 select。
func checkWarpGraph(v *violations, raw []byte, o *options.Options) {
	p, on := build.PolicyFor(o)
	if !on {
		return
	}
	vs, err := build.CheckWarpGraph(raw, p)
	if err != nil {
		v.addf("WARP 图检查失败: %v", err)
		return
	}
	for _, m := range vs {
		v.addf("WARP（%s）：%s", p.Mode, m)
	}
}

// checkWarpMembership：warp 不得是 select / auto 的成员（它是内部出口，不让用户手选或测速）。
func checkWarpMembership(v *violations, g *graph) {
	for _, grp := range []string{"select", "auto"} {
		if m, ok := g.nodes[grp]; ok && contains(strList(m["outbounds"]), "warp") {
			v.addf("warp 不得是 %s 的成员", grp)
		}
	}
}

// checkDNSDeps 复用构建器自己的依赖环检查（同一份 CheckDNSDeps）：DNS 服务器 → domain_resolver / detour，
// 出站 → default_domain_resolver 三类边无环，且 domain_resolver 链的终点是 IP 字面量服务器。
func checkDNSDeps(v *violations, raw []byte) {
	var c cfg.Config
	if err := json.Unmarshal(raw, &c); err != nil {
		v.addf("配置无法按 schema 类型解码: %v", err)
		return
	}
	if err := build.CheckDNSDeps(&c); err != nil {
		v.addf("DNS 依赖检查: %v", err)
	}
	if err := build.ValidateGraph(&c); err != nil {
		v.addf("标签图检查: %v", err)
	}
}
