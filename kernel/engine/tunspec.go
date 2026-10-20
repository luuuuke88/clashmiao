package engine

import (
	"encoding/json"

	"github.com/sagernet/sing-box/experimental/libbox"
)

// tunSpec 是 spec §4.3 的 TunSpec：Go 把 libbox.TunOptions 拍平成 JSON 交给宿主。
// 所有数组都是非 nil 的（宿主按「有 / 无元素」判断，不用处理 null）。
type tunSpec struct {
	MTU               int32     `json:"mtu"`
	AutoRoute         bool      `json:"auto_route"`
	StrictRoute       bool      `json:"strict_route"`
	DNSMode           string    `json:"dns_mode"`
	DNSServers        []string  `json:"dns_servers"`
	Inet4Address      []string  `json:"inet4_address"`
	Inet6Address      []string  `json:"inet6_address"`
	Inet4Route        []string  `json:"inet4_route"`
	Inet6Route        []string  `json:"inet6_route"`
	Inet4RouteExclude []string  `json:"inet4_route_exclude"`
	Inet6RouteExclude []string  `json:"inet6_route_exclude"`
	Inet4RouteRange   []string  `json:"inet4_route_range"`
	Inet6RouteRange   []string  `json:"inet6_route_range"`
	IncludePackage    []string  `json:"include_package"`
	ExcludePackage    []string  `json:"exclude_package"`
	HTTPProxy         httpProxy `json:"http_proxy"`
}

type httpProxy struct {
	Enabled bool     `json:"enabled"`
	Server  string   `json:"server"`
	Port    int32    `json:"port"`
	Bypass  []string `json:"bypass"`
	Match   []string `json:"match"`
}

func drainStrings(it libbox.StringIterator) []string {
	out := []string{}
	if it == nil {
		return out
	}
	for it.HasNext() {
		out = append(out, it.Next())
	}
	return out
}

func drainPrefixes(it libbox.RoutePrefixIterator) []string {
	out := []string{}
	if it == nil {
		return out
	}
	for it.HasNext() {
		out = append(out, it.Next().String())
	}
	return out
}

// tunInput 是 buildTunSpec 的纯 Go 输入。libbox.TunOptions 里的 RoutePrefix 无法在包外构造，
// 所以把「从 libbox 读取」与「拼 JSON」拆成两步：前者由真实的启动流程覆盖（见 cancel_test 的 TUN 用例），
// 后者用这个结构体直接喂数据做表驱动测试。
type tunInput struct {
	MTU               int32
	AutoRoute         bool
	StrictRoute       bool
	DNSMode           string
	DNSServers        []string
	Inet4Address      []string
	Inet6Address      []string
	Inet4Route        []string
	Inet6Route        []string
	Inet4RouteExclude []string
	Inet6RouteExclude []string
	Inet4RouteRange   []string
	Inet6RouteRange   []string
	IncludePackage    []string
	ExcludePackage    []string
	HTTPProxy         *httpProxy
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func buildTunSpec(in tunInput) (string, error) {
	spec := tunSpec{
		MTU:               in.MTU,
		AutoRoute:         in.AutoRoute,
		StrictRoute:       in.StrictRoute,
		DNSMode:           in.DNSMode,
		DNSServers:        nonNil(in.DNSServers),
		Inet4Address:      nonNil(in.Inet4Address),
		Inet6Address:      nonNil(in.Inet6Address),
		Inet4Route:        nonNil(in.Inet4Route),
		Inet6Route:        nonNil(in.Inet6Route),
		Inet4RouteExclude: nonNil(in.Inet4RouteExclude),
		Inet6RouteExclude: nonNil(in.Inet6RouteExclude),
		Inet4RouteRange:   nonNil(in.Inet4RouteRange),
		Inet6RouteRange:   nonNil(in.Inet6RouteRange),
		IncludePackage:    nonNil(in.IncludePackage),
		ExcludePackage:    nonNil(in.ExcludePackage),
		HTTPProxy:         httpProxy{Bypass: []string{}, Match: []string{}},
	}
	if in.HTTPProxy != nil {
		spec.HTTPProxy = *in.HTTPProxy
		spec.HTTPProxy.Bypass = nonNil(spec.HTTPProxy.Bypass)
		spec.HTTPProxy.Match = nonNil(spec.HTTPProxy.Match)
	}
	if spec.DNSMode == "" {
		spec.DNSMode = "hijack" // 内核默认值；让宿主总是看到明确的取值
	}
	raw, err := json.Marshal(spec)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func tunSpecJSON(o libbox.TunOptions) (string, error) {
	in := tunInput{
		MTU:               o.GetMTU(),
		AutoRoute:         o.GetAutoRoute(),
		StrictRoute:       o.GetStrictRoute(),
		Inet4Address:      drainPrefixes(o.GetInet4Address()),
		Inet6Address:      drainPrefixes(o.GetInet6Address()),
		Inet4Route:        drainPrefixes(o.GetInet4RouteAddress()),
		Inet6Route:        drainPrefixes(o.GetInet6RouteAddress()),
		Inet4RouteExclude: drainPrefixes(o.GetInet4RouteExcludeAddress()),
		Inet6RouteExclude: drainPrefixes(o.GetInet6RouteExcludeAddress()),
		Inet4RouteRange:   drainPrefixes(o.GetInet4RouteRange()),
		Inet6RouteRange:   drainPrefixes(o.GetInet6RouteRange()),
		IncludePackage:    drainStrings(o.GetIncludePackage()),
		ExcludePackage:    drainStrings(o.GetExcludePackage()),
	}
	if box := o.GetDNSMode(); box != nil {
		in.DNSMode = box.Value
	}
	// 只有「有地址可用」时才有 DNS 服务器；取不到（比如没有可用的下一个地址）按没有处理，
	// 是否添加由宿主按 dns_mode 决定。
	if dns, err := o.GetDNSServerAddress(); err == nil {
		in.DNSServers = drainStrings(dns)
	}
	if o.IsHTTPProxyEnabled() {
		in.HTTPProxy = &httpProxy{
			Enabled: true,
			Server:  o.GetHTTPProxyServer(),
			Port:    o.GetHTTPProxyServerPort(),
			Bypass:  drainStrings(o.GetHTTPProxyBypassDomain()),
			Match:   drainStrings(o.GetHTTPProxyMatchDomain()),
		}
	}
	return buildTunSpec(in)
}
