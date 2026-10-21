package build

import (
	"fmt"
	"net/netip"
	"sort"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
)

// CheckDNSDeps 检查 DNS 的依赖图（spec §5.2.1），每次 Build 都跑，gate 的不变量复用同一份：
//
//	边 1：DNS 服务器 → 它的 domain_resolver 服务器
//	边 2：DNS 服务器 → 它的 detour 出站 / 端点
//	边 3：地址是域名的出站 / 端点 → 它实际生效的解析器：自己写的 domain_resolver（字符串或 {"server": …} 对象），
//	      没写才是 route.default_domain_resolver
//
// 要求：图无环；并且凡地址是域名的 DNS 服务器都必须有 domain_resolver，沿 domain_resolver 走到的终点
// 必须是地址为 IP 字面量的服务器（域名不能自己解析自己，也不能绕一圈再解析自己）。
// 失败返回 `build-failed: dns dependency cycle: a -> b -> a` 之类，不产出配置。
func CheckDNSDeps(c *cfg.Config) error {
	if c.DNS == nil {
		return nil
	}
	servers := map[string]cfg.DNSServer{}
	for _, s := range c.DNS.Servers {
		servers[s.Tag] = s
	}
	entities := map[string]map[string]any{}
	for _, o := range c.Outbounds {
		entities[o.Tag()] = o
	}
	for _, e := range c.Endpoints {
		entities[e.Tag()] = e
	}
	defaultResolver := ""
	if c.Route != nil && c.Route.DefaultDomainResolver != nil {
		defaultResolver = c.Route.DefaultDomainResolver.Server
	}

	// 节点 key 用前缀区分：dns 服务器与出站 / 端点的 tag 空间是独立的。
	const dnsPrefix, outPrefix = "dns:", "out:"
	edges := map[string][]string{}
	for tag, s := range servers {
		from := dnsPrefix + tag
		if s.DomainResolver != "" {
			edges[from] = append(edges[from], dnsPrefix+s.DomainResolver)
		}
		if s.Detour != "" {
			edges[from] = append(edges[from], outPrefix+s.Detour)
		}
	}
	for tag, e := range entities {
		// 节点自己指定的解析器优先于默认解析器：边必须按实际生效的那个建，否则
		// dns-remote → select → node → dns-remote 这类环会被按 node → default 放行。
		if r := entityResolver(e); r != "" {
			if _, ok := servers[r]; !ok {
				return fmt.Errorf("%s %s: domain_resolver %q is not a dns server", PrefixBuildFailed, tag, r)
			}
			if entityNeedsResolver(e) {
				edges[outPrefix+tag] = append(edges[outPrefix+tag], dnsPrefix+r)
			}
		} else if defaultResolver != "" && entityNeedsResolver(e) {
			edges[outPrefix+tag] = append(edges[outPrefix+tag], dnsPrefix+defaultResolver)
		}
		// 分组把「走到它」传递给成员：dns-remote → select → 域名型节点 → default_domain_resolver。
		if t, _ := e["type"].(string); t == "selector" || t == "urltest" {
			if members, ok := e["outbounds"].([]string); ok {
				for _, m := range members {
					edges[outPrefix+tag] = append(edges[outPrefix+tag], outPrefix+m)
				}
			} else if members, ok := e["outbounds"].([]any); ok {
				for _, m := range members {
					if ms, ok := m.(string); ok {
						edges[outPrefix+tag] = append(edges[outPrefix+tag], outPrefix+ms)
					}
				}
			}
		}
		if d, _ := e["detour"].(string); d != "" {
			edges[outPrefix+tag] = append(edges[outPrefix+tag], outPrefix+d)
		}
	}
	for k := range edges {
		sort.Strings(edges[k])
	}

	// 找环（确定性：按 key 排序遍历）。
	const (
		white = iota
		grey
		black
	)
	state := map[string]int{}
	var stack []string
	var cycle []string
	var visit func(n string) bool
	visit = func(n string) bool {
		state[n] = grey
		stack = append(stack, n)
		for _, m := range edges[n] {
			switch state[m] {
			case grey:
				i := len(stack) - 1
				for stack[i] != m {
					i--
				}
				cycle = append(append([]string{}, stack[i:]...), m)
				return true
			case white:
				if visit(m) {
					return true
				}
			}
		}
		stack = stack[:len(stack)-1]
		state[n] = black
		return false
	}
	keys := make([]string, 0, len(edges))
	for k := range edges {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if state[k] == white && visit(k) {
			names := make([]string, len(cycle))
			for i, n := range cycle {
				names[i] = strings.TrimPrefix(strings.TrimPrefix(n, dnsPrefix), outPrefix)
			}
			return fmt.Errorf("%s dns dependency cycle: %s", PrefixBuildFailed, strings.Join(names, " -> "))
		}
	}

	// domain_resolver 链的终点必须是 IP 字面量服务器。
	tags := make([]string, 0, len(servers))
	for t := range servers {
		tags = append(tags, t)
	}
	sort.Strings(tags)
	for _, tag := range tags {
		s := servers[tag]
		if !serverAddressIsDomain(s) {
			continue
		}
		if s.DomainResolver == "" {
			return fmt.Errorf("%s dns server %s has a domain address but no domain_resolver", PrefixBuildFailed, tag)
		}
		end, err := resolverEnd(servers, tag)
		if err != nil {
			return err
		}
		if serverAddressIsDomain(end) || end.Server == "" {
			return fmt.Errorf("%s dns domain_resolver chain of %s ends at %s, which is not an IP-literal server", PrefixBuildFailed, tag, end.Tag)
		}
	}
	if defaultResolver != "" {
		if _, ok := servers[defaultResolver]; !ok {
			return fmt.Errorf("%s route.default_domain_resolver %q is not a dns server", PrefixBuildFailed, defaultResolver)
		}
	}
	return nil
}

// resolverEnd 沿 domain_resolver 走到链尾（调用前环已排除）。
func resolverEnd(servers map[string]cfg.DNSServer, from string) (cfg.DNSServer, error) {
	cur := servers[from]
	for cur.DomainResolver != "" {
		next, ok := servers[cur.DomainResolver]
		if !ok {
			return cfg.DNSServer{}, fmt.Errorf("%s dns server %s: domain_resolver %q does not exist", PrefixBuildFailed, cur.Tag, cur.DomainResolver)
		}
		cur = next
	}
	return cur, nil
}

func serverAddressIsDomain(s cfg.DNSServer) bool {
	if s.Server == "" {
		return false
	}
	_, err := netip.ParseAddr(s.Server)
	return err != nil
}

// entityResolver 取出站 / 端点自己写的 domain_resolver：字符串，或 {"server": "…", "strategy": …} 对象。
func entityResolver(e map[string]any) string {
	switch v := e["domain_resolver"].(type) {
	case string:
		return v
	case map[string]any:
		s, _ := v["server"].(string)
		return s
	}
	return ""
}

// entityNeedsResolver：出站 / 端点的拨号地址是域名（保守地：任何非 IP 字面量的 server / peers.address）。
func entityNeedsResolver(e map[string]any) bool {
	if s, ok := e["server"].(string); ok && s != "" {
		if _, err := netip.ParseAddr(s); err != nil {
			return true
		}
	}
	if peers, ok := e["peers"].([]any); ok {
		for _, p := range peers {
			if m, ok := p.(map[string]any); ok {
				if a, ok := m["address"].(string); ok && a != "" {
					if _, err := netip.ParseAddr(a); err != nil {
						return true
					}
				}
			}
		}
	}
	return false
}

// nodeHostnames 取出站 / 端点里的域名（server、peers[].address），去重排序，用来生成「直连域名」DNS 规则。
func nodeHostnames(entities ...map[string]any) []string {
	seen := map[string]bool{}
	add := func(h string) {
		h = strings.ToLower(strings.TrimSpace(h))
		if h == "" {
			return
		}
		if _, err := netip.ParseAddr(h); err == nil {
			return
		}
		seen[h] = true
	}
	for _, e := range entities {
		if s, ok := e["server"].(string); ok {
			add(s)
		}
		if peers, ok := e["peers"].([]any); ok {
			for _, p := range peers {
				if m, ok := p.(map[string]any); ok {
					if a, ok := m["address"].(string); ok {
						add(a)
					}
				}
			}
		}
	}
	out := make([]string, 0, len(seen))
	for h := range seen {
		out = append(out, h)
	}
	sort.Strings(out)
	return out
}
