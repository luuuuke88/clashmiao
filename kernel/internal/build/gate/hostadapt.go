package gate

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"sort"
	"strings"
)

// AdaptOptions 是主机适配的参数。端口为 0 时自动挑一个空闲端口。
type AdaptOptions struct {
	MixedPort int
	DNSPort   int
	// CAPEM 非空时注入为受信根证书（DoH 用例的本地 CA）。
	CAPEM string
}

func freePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

// Resolve 把 0 端口换成真实的空闲端口。
func (a AdaptOptions) Resolve() (AdaptOptions, error) {
	var err error
	if a.MixedPort == 0 {
		if a.MixedPort, err = freePort(); err != nil {
			return a, err
		}
	}
	if a.DNSPort == 0 {
		if a.DNSPort, err = freePort(); err != nil {
			return a, err
		}
	}
	return a, nil
}

// HostAdapt 把 Android 原始配置改成主机上能跑的副本。**只做白名单里的改动**（与 spec §7.1 同一份清单）：
//
//  1. 删 tun-in，以及引用它的路由 / DNS 规则与 dns-fake 服务器（主机没有权限创建 TUN）；
//  2. 删 route.override_android_vpn（非 Android 内核会拒绝）；
//  3. mixed-in / dns-in 换成 127.0.0.1 的随机端口；
//  4. （DoH 用例）注入测试 CA。
//
// 白名单之外的任何差异都会让 CheckWhitelist 失败，防止适配悄悄把真 bug 抹掉。
func HostAdapt(raw []byte, ap AdaptOptions) ([]byte, AdaptOptions, error) {
	ap, err := ap.Resolve()
	if err != nil {
		return nil, ap, err
	}
	var c obj
	if err := json.Unmarshal(raw, &c); err != nil {
		return nil, ap, err
	}

	refersTun := func(r obj) bool { return contains(strList(r["inbound"]), "tun-in") }
	filter := func(list []any, drop func(obj) bool) []any {
		out := []any{}
		for _, e := range list {
			if m := asMap(e); m != nil && drop(m) {
				continue
			}
			out = append(out, e)
		}
		return out
	}

	c["inbounds"] = filter(asSlice(c["inbounds"]), func(m obj) bool { return asString(m["tag"]) == "tun-in" })
	for _, e := range asSlice(c["inbounds"]) {
		m := asMap(e)
		switch asString(m["tag"]) {
		case "mixed-in":
			m["listen"], m["listen_port"] = "127.0.0.1", float64(ap.MixedPort)
		case "dns-in":
			m["listen"], m["listen_port"] = "127.0.0.1", float64(ap.DNSPort)
		}
	}
	if rt := asMap(c["route"]); rt != nil {
		delete(rt, "override_android_vpn")
		if _, has := rt["rules"]; has {
			rt["rules"] = filter(asSlice(rt["rules"]), refersTun)
		}
	}
	if d := asMap(c["dns"]); d != nil {
		if _, has := d["servers"]; has {
			d["servers"] = filter(asSlice(d["servers"]), func(m obj) bool { return asString(m["tag"]) == "dns-fake" })
		}
		if _, has := d["rules"]; has {
			d["rules"] = filter(asSlice(d["rules"]), func(m obj) bool {
				return refersTun(m) || asString(m["server"]) == "dns-fake"
			})
		}
	}
	if ap.CAPEM != "" {
		c["certificate"] = caBlock(ap.CAPEM)
	}
	out, err := json.MarshalIndent(c, "", "  ")
	return out, ap, err
}

func caBlock(pem string) obj {
	return obj{"store": "system", "certificate": strings.Split(strings.TrimSpace(pem), "\n")}
}

// ---- 差异 ----

// Change 是两份配置之间的一处结构差异。数组按元素的规范化 JSON 做最长公共子序列比较，
// 所以「删掉中间一条规则」只会报这一条，而不是后面全部错位。
type Change struct {
	Op   string // removed / added / changed
	Path string // 数组元素写成 "route.rules[]"
	Old  any
	New  any
}

func (c Change) String() string {
	switch c.Op {
	case "removed":
		return fmt.Sprintf("removed %s %s", c.Path, canon(c.Old))
	case "added":
		return fmt.Sprintf("added %s %s", c.Path, canon(c.New))
	}
	return fmt.Sprintf("changed %s: %s -> %s", c.Path, canon(c.Old), canon(c.New))
}

func canon(x any) string {
	b, _ := json.Marshal(x) // map 的键按字典序输出，天然规范
	return string(b)
}

// Diff 计算 a → b 的结构差异。
func Diff(a, b []byte) ([]Change, error) {
	var x, y any
	if err := json.Unmarshal(a, &x); err != nil {
		return nil, err
	}
	if err := json.Unmarshal(b, &y); err != nil {
		return nil, err
	}
	var out []Change
	diffValue("", x, y, &out)
	return out, nil
}

func joinPath(path, key string) string {
	if path == "" {
		return key
	}
	return path + "." + key
}

func diffValue(path string, a, b any, out *[]Change) {
	switch x := a.(type) {
	case map[string]any:
		if y, ok := b.(map[string]any); ok {
			keys := map[string]bool{}
			for k := range x {
				keys[k] = true
			}
			for k := range y {
				keys[k] = true
			}
			sorted := make([]string, 0, len(keys))
			for k := range keys {
				sorted = append(sorted, k)
			}
			sort.Strings(sorted)
			for _, k := range sorted {
				p := joinPath(path, k)
				av, aok := x[k]
				bv, bok := y[k]
				switch {
				case aok && !bok:
					*out = append(*out, Change{Op: "removed", Path: p, Old: av})
				case !aok && bok:
					*out = append(*out, Change{Op: "added", Path: p, New: bv})
				default:
					diffValue(p, av, bv, out)
				}
			}
			return
		}
	case []any:
		if y, ok := b.([]any); ok {
			diffSlice(path+"[]", x, y, out)
			return
		}
	}
	if canon(a) != canon(b) {
		*out = append(*out, Change{Op: "changed", Path: path, Old: a, New: b})
	}
}

func diffSlice(path string, a, b []any, out *[]Change) {
	ca, cb := make([]string, len(a)), make([]string, len(b))
	for i := range a {
		ca[i] = canon(a[i])
	}
	for i := range b {
		cb[i] = canon(b[i])
	}
	// LCS
	lcs := make([][]int, len(a)+1)
	for i := range lcs {
		lcs[i] = make([]int, len(b)+1)
	}
	for i := len(a) - 1; i >= 0; i-- {
		for j := len(b) - 1; j >= 0; j-- {
			if ca[i] == cb[j] {
				lcs[i][j] = lcs[i+1][j+1] + 1
			} else if lcs[i+1][j] >= lcs[i][j+1] {
				lcs[i][j] = lcs[i+1][j]
			} else {
				lcs[i][j] = lcs[i][j+1]
			}
		}
	}
	i, j := 0, 0
	for i < len(a) || j < len(b) {
		switch {
		case i < len(a) && j < len(b) && ca[i] == cb[j]:
			i++
			j++
		case i < len(a) && (j == len(b) || lcs[i+1][j] >= lcs[i][j+1]):
			*out = append(*out, Change{Op: "removed", Path: path, Old: a[i]})
			i++
		default:
			*out = append(*out, Change{Op: "added", Path: path, New: b[j]})
			j++
		}
	}
}

// CheckWhitelist 断言「原始配置 → 适配副本」的差异恰好等于白名单允许的那些，返回白名单之外的差异。
// 同时要求白名单里该发生的改动确实发生了（例如有 tun-in 就必须被删掉），否则适配等于没做。
func CheckWhitelist(orig, adapted []byte, ap AdaptOptions) ([]string, error) {
	changes, err := Diff(orig, adapted)
	if err != nil {
		return nil, err
	}
	var origCfg obj
	if err := json.Unmarshal(orig, &origCfg); err != nil {
		return nil, err
	}

	var bad []string
	removedInbounds := map[string]obj{}
	addedInbounds := map[string]obj{}

	for _, ch := range changes {
		switch {
		case ch.Op == "removed" && ch.Path == "route.override_android_vpn":
		case ch.Op == "removed" && ch.Path == "inbounds[]" && asString(asMap(ch.Old)["tag"]) == "tun-in":
		case ch.Op == "removed" && ch.Path == "route.rules[]" && contains(strList(asMap(ch.Old)["inbound"]), "tun-in"):
		case ch.Op == "removed" && ch.Path == "dns.rules[]" &&
			(contains(strList(asMap(ch.Old)["inbound"]), "tun-in") || asString(asMap(ch.Old)["server"]) == "dns-fake"):
		case ch.Op == "removed" && ch.Path == "dns.servers[]" && asString(asMap(ch.Old)["tag"]) == "dns-fake":
		case ch.Op == "added" && ch.Path == "certificate" && ap.CAPEM != "" && canon(ch.New) == canon(caBlock(ap.CAPEM)):
		case ch.Op == "removed" && ch.Path == "inbounds[]" && isLocalInbound(asString(asMap(ch.Old)["tag"])):
			removedInbounds[asString(asMap(ch.Old)["tag"])] = asMap(ch.Old)
		case ch.Op == "added" && ch.Path == "inbounds[]" && isLocalInbound(asString(asMap(ch.New)["tag"])):
			addedInbounds[asString(asMap(ch.New)["tag"])] = asMap(ch.New)
		default:
			bad = append(bad, ch.String())
		}
	}

	// mixed-in / dns-in：删一条、加一条，且新的只允许在 listen / listen_port 上与旧的不同，值必须是约定的。
	for tag, was := range removedInbounds {
		now, ok := addedInbounds[tag]
		if !ok {
			bad = append(bad, fmt.Sprintf("inbound %s 被删除但没有对应的改写", tag))
			continue
		}
		wantPort := ap.MixedPort
		if tag == "dns-in" {
			wantPort = ap.DNSPort
		}
		want := cloneObj(was)
		want["listen"], want["listen_port"] = "127.0.0.1", float64(wantPort)
		if canon(want) != canon(now) {
			bad = append(bad, fmt.Sprintf("inbound %s 的改写超出白名单: %s -> %s", tag, canon(was), canon(now)))
		}
		delete(addedInbounds, tag)
	}
	for tag := range addedInbounds {
		bad = append(bad, fmt.Sprintf("inbound %s 是凭空新增的", tag))
	}

	// 反向：原始配置里有 tun-in，适配副本里必须没有（否则 Start 会因没有 TUN 权限失败，测试没有意义）。
	var adaptedCfg obj
	if err := json.Unmarshal(adapted, &adaptedCfg); err != nil {
		return nil, err
	}
	if _, has := newGraph(adaptedCfg).inbounds["tun-in"]; has {
		bad = append(bad, "适配副本里仍有 tun-in")
	}
	sort.Strings(bad)
	return bad, nil
}

func isLocalInbound(tag string) bool { return tag == "mixed-in" || tag == "dns-in" }

func cloneObj(m obj) obj {
	b, _ := json.Marshal(m)
	var out obj
	_ = json.NewDecoder(bytes.NewReader(b)).Decode(&out)
	return out
}
