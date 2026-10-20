package build

import (
	"fmt"
	"sort"

	"github.com/luuuuke88/clashmiao/kernel/internal/build/cfg"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// 这个文件是 U4 的脚手架：让测试闸门有一份完整、能真启动的配置可以检查。
// 出站装配（outbounds）还没有自己的任务落地（U7）；dns（U5）与 route（U6）已经各自成文件，
// 这里只剩把它们接起来与暂用的出站装配，U7 会整体替换成 outbounds.go。

const (
	TagSelect         = "select"
	TagAuto           = "auto"
	TagDirect         = "direct"
	TagDirectFragment = "direct-fragment"
	TagBypass         = "bypass"
)

func scaffold(c *cfg.Config, p Profile, o *options.Options, env Env, warnings *[]string) error {
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

	var entities []map[string]any
	for _, n := range nodes {
		entities = append(entities, n)
	}
	for _, e := range c.Endpoints {
		entities = append(entities, e)
	}
	dns, err := BuildDNS(dnsInput{
		Options:       o,
		Egress:        TagSelect,
		HasTun:        o.EnableTun,
		DirectDomains: nodeHostnames(entities...),
	}, warnings)
	if err != nil {
		return err
	}
	c.DNS = dns

	route, err := BuildRoute(o, env, TagSelect, warnings)
	if err != nil {
		return err
	}
	c.Route = route
	return nil
}
