package build

import (
	"fmt"
	"sort"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 这个文件是 U4 的脚手架：让测试闸门有一份完整、能真启动的配置可以检查。
// dns / route / outbounds 三块各有自己的任务（U5 / U6 / U7），到时分别换成 dns.go / route.go / outbounds.go
// 并删除这里对应的函数；脚手架里写的东西不是最终行为。

const (
	TagSelect         = "select"
	TagAuto           = "auto"
	TagDirect         = "direct"
	TagDirectFragment = "direct-fragment"
	TagBypass         = "bypass"
	TagDNSRemote      = "dns-remote"
	TagDNSDirect      = "dns-direct"
	TagDNSLocal       = "dns-local"
)

func scaffold(c *cfg.Config, p Profile, o *options.Options, env Env, warnings *[]string) {
	c.DNS = &cfg.DNS{
		Servers: []cfg.DNSServer{
			{Type: "udp", Tag: TagDNSRemote, Server: "1.1.1.1", Detour: TagSelect},
			{Type: "udp", Tag: TagDNSDirect, Server: "223.5.5.5"},
			{Type: "local", Tag: TagDNSLocal},
		},
		Final:    TagDNSRemote,
		Strategy: o.IPv6Mode,
	}

	var nodeTags []string
	var nodes []cfg.Outbound
	for _, n := range p.Outbounds {
		switch n["type"] {
		case "selector", "urltest", "direct", "block", "dns":
			continue
		}
		nodes = append(nodes, cfg.Outbound(n))
		nodeTags = append(nodeTags, cfg.Outbound(n).Tag())
	}
	var endpointTags []string
	for _, e := range p.Endpoints {
		c.Endpoints = append(c.Endpoints, cfg.Endpoint(e))
		endpointTags = append(endpointTags, cfg.Endpoint(e).Tag())
	}
	sort.Strings(endpointTags)
	members := append(append([]string{}, nodeTags...), endpointTags...)

	c.Outbounds = append(c.Outbounds,
		cfg.Outbound{"type": "selector", "tag": TagSelect, "outbounds": append([]string{TagAuto}, members...), "default": TagAuto},
		cfg.Outbound{"type": "urltest", "tag": TagAuto, "outbounds": members, "url": o.ConnectionTestURL,
			"interval": fmt.Sprintf("%ds", o.URLTestInterval), "idle_timeout": fmt.Sprintf("%ds", o.URLTestInterval*10)},
	)
	c.Outbounds = append(c.Outbounds, nodes...)
	c.Outbounds = append(c.Outbounds,
		cfg.Outbound{"type": "direct", "tag": TagDirect},
		cfg.Outbound{"type": "direct", "tag": TagDirectFragment, "udp_fragment": true},
		cfg.Outbound{"type": "direct", "tag": TagBypass},
	)

	c.Route = &cfg.Route{
		Rules: []cfg.RouteRule{
			{Action: "sniff"},
			{Protocol: []string{"dns"}, Action: "hijack-dns"},
		},
		Final:                 TagSelect,
		AutoDetectInterface:   true,
		OverrideAndroidVPN:    env.GOOS == "android",
		DefaultDomainResolver: TagDNSDirect,
	}
}
