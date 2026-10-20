// Package cfg 是运行配置（sing-box 1.14 schema）的最小类型集合。
//
// 只描述我们会生成的那部分字段：生成路径用结构体（字段顺序固定，黄金文件好读也稳定），
// 订阅里来的节点与端点原样用 map（保留上游未知字段，不替上游猜）。本包不 import sing-box。
package cfg

import "encoding/json"

// Config 是最终交给内核的配置。
type Config struct {
	Log          *Log          `json:"log,omitempty"`
	DNS          *DNS          `json:"dns,omitempty"`
	Inbounds     []Inbound     `json:"inbounds,omitempty"`
	Outbounds    []Outbound    `json:"outbounds"`
	Endpoints    []Endpoint    `json:"endpoints,omitempty"`
	Route        *Route        `json:"route,omitempty"`
	Experimental *Experimental `json:"experimental,omitempty"`
}

// Marshal 输出缩进的 JSON（黄金文件与错误信息都读它）。
func (c *Config) Marshal() ([]byte, error) {
	return json.MarshalIndent(c, "", "  ")
}

// Log 对应 `log`。默认不写文件：日志走命令服务器的环形缓冲。
type Log struct {
	Level     string `json:"level"`
	Timestamp bool   `json:"timestamp"`
	Output    string `json:"output,omitempty"`
}

// DNS 对应 `dns`。
type DNS struct {
	Servers  []DNSServer `json:"servers"`
	Rules    []DNSRule   `json:"rules,omitempty"`
	Final    string      `json:"final"`
	Strategy string      `json:"strategy,omitempty"`
}

// DNSServer 是类型化的 DNS 服务器（1.14 起旧的 address 格式已移除）。
type DNSServer struct {
	Type           string          `json:"type"`
	Tag            string          `json:"tag"`
	Server         string          `json:"server,omitempty"`
	ServerPort     int             `json:"server_port,omitempty"`
	Path           string          `json:"path,omitempty"`
	DomainResolver string          `json:"domain_resolver,omitempty"`
	Detour         string          `json:"detour,omitempty"`
	Inet4Range     string          `json:"inet4_range,omitempty"`
	Inet6Range     string          `json:"inet6_range,omitempty"`
	TLS            json.RawMessage `json:"tls,omitempty"` // 测试注入自签 CA 用，生产构建不写
}

// DNSRule 是一条 DNS 规则（动作默认 route）。
type DNSRule struct {
	Inbound       []string `json:"inbound,omitempty"`
	Domain        []string `json:"domain,omitempty"`
	DomainSuffix  []string `json:"domain_suffix,omitempty"`
	DomainRegex   []string `json:"domain_regex,omitempty"`
	DomainKeyword []string `json:"domain_keyword,omitempty"`
	Action        string   `json:"action,omitempty"`
	Server        string   `json:"server,omitempty"`
	Strategy      string   `json:"strategy,omitempty"`
	RewriteTTL    *uint32  `json:"rewrite_ttl,omitempty"`
	DisableCache  bool     `json:"disable_cache,omitempty"`
	Rcode         string   `json:"rcode,omitempty"`
}

// Inbound 覆盖 tun / mixed / direct 三种入站。
type Inbound struct {
	Type                   string   `json:"type"`
	Tag                    string   `json:"tag"`
	Listen                 string   `json:"listen,omitempty"`
	ListenPort             int      `json:"listen_port,omitempty"`
	Address                []string `json:"address,omitempty"`
	MTU                    int      `json:"mtu,omitempty"`
	AutoRoute              bool     `json:"auto_route,omitempty"`
	StrictRoute            bool     `json:"strict_route,omitempty"`
	Stack                  string   `json:"stack,omitempty"`
	EndpointIndependentNAT bool     `json:"endpoint_independent_nat,omitempty"`
}

// Outbound 是出站（订阅节点原样保留未知字段，所以是 map）。
type Outbound map[string]any

// Endpoint 是端点（WireGuard 等），形态同 Outbound。
type Endpoint map[string]any

// Tag / Type 读取常用字段。
func (o Outbound) Tag() string  { s, _ := o["tag"].(string); return s }
func (o Outbound) Type() string { s, _ := o["type"].(string); return s }
func (e Endpoint) Tag() string  { s, _ := e["tag"].(string); return s }
func (e Endpoint) Type() string { s, _ := e["type"].(string); return s }

// Route 对应 `route`。
type Route struct {
	Rules                 []RouteRule `json:"rules,omitempty"`
	RuleSet               []RuleSet   `json:"rule_set,omitempty"`
	Final                 string      `json:"final,omitempty"`
	AutoDetectInterface   bool        `json:"auto_detect_interface,omitempty"`
	OverrideAndroidVPN    bool        `json:"override_android_vpn,omitempty"`
	DefaultDomainResolver string      `json:"default_domain_resolver,omitempty"`
}

// RouteRule 是一条路由规则（动作默认 route）。
type RouteRule struct {
	Inbound       []string `json:"inbound,omitempty"`
	Protocol      []string `json:"protocol,omitempty"`
	Network       []string `json:"network,omitempty"`
	Port          []uint16 `json:"port,omitempty"`
	PortRange     []string `json:"port_range,omitempty"`
	Domain        []string `json:"domain,omitempty"`
	DomainSuffix  []string `json:"domain_suffix,omitempty"`
	DomainRegex   []string `json:"domain_regex,omitempty"`
	DomainKeyword []string `json:"domain_keyword,omitempty"`
	IPCIDR        []string `json:"ip_cidr,omitempty"`
	IPIsPrivate   bool     `json:"ip_is_private,omitempty"`
	Action        string   `json:"action,omitempty"`
	Outbound      string   `json:"outbound,omitempty"`
	Strategy      string   `json:"strategy,omitempty"`
}

// RuleSet 是本地规则集引用（U6 可选评估项；默认不生成）。
type RuleSet struct {
	Type   string `json:"type"`
	Tag    string `json:"tag"`
	Format string `json:"format"`
	Path   string `json:"path"`
}

// Experimental 对应 `experimental`。**永不含 clash_api**。
type Experimental struct {
	CacheFile *CacheFile `json:"cache_file,omitempty"`
}

// CacheFile 对应 `experimental.cache_file`。
type CacheFile struct {
	Enabled     bool   `json:"enabled"`
	Path        string `json:"path,omitempty"`
	StoreFakeIP bool   `json:"store_fakeip,omitempty"`
}
