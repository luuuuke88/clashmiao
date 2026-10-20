// Package options 解码、默认值与校验 App 传给内核的 configOptions（kebab-case 的 JSON）。
// 本包不 import sing-box。
package options

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"reflect"
	"strconv"
	"strings"
)

// ErrorPrefix 是所有选项错误的稳定前缀（spec §6.4）。
const ErrorPrefix = "option-invalid:"

// Error 是选项错误，Error() 以 ErrorPrefix 开头。
type Error struct{ Msg string }

func (e *Error) Error() string { return ErrorPrefix + " " + e.Msg }

// IsOptionError 判断 err 链里是否有选项错误。
func IsOptionError(err error) bool {
	var oe *Error
	return errors.As(err, &oe)
}

func invalid(format string, args ...any) error { return &Error{Msg: fmt.Sprintf(format, args...)} }

// Warning 的 Code 是稳定的机器可读码，Message 给日志看。
type Warning struct {
	Code    string
	Message string
}

// Warnings 是不致命的提示（未知键、被忽略的选项等）。
type Warnings []Warning

// Has 判断是否含有某个码。
func (w Warnings) Has(code string) bool {
	for _, it := range w {
		if it.Code == code {
			return true
		}
	}
	return false
}

// Messages 返回 "<code>: <message>" 的列表，便于上层合并成字符串 warnings。
func (w Warnings) Messages() []string {
	out := make([]string, 0, len(w))
	for _, it := range w {
		out = append(out, it.Code+": "+it.Message)
	}
	return out
}

const (
	WarnUnknownKey        = "unknown-key"
	WarnClashAPI          = "clash-api-unsupported"
	WarnRegion            = "region-unsupported"
	DefaultBootstrapDNS   = "223.5.5.5"
	defaultClashAPIPort   = 6756
	defaultRemoteDNS      = "https://1.1.1.1/dns-query"
	defaultDirectDNS      = "223.5.5.5"
	defaultConnectionTest = "http://connectivitycheck.gstatic.com/generate_204"
)

// Options 覆盖 spec §2.4 列出的全部键。键名与 Dart 的 getDefaultConfigOptions 一一对应。
type Options struct {
	Region                  string `json:"region"`
	ExecuteConfigAsIs       bool   `json:"execute-config-as-is"`
	EnableFullConfig        bool   `json:"enable-full-config"`
	BlockAds                bool   `json:"block-ads"`
	LogLevel                string `json:"log-level"`
	ResolveDestination      bool   `json:"resolve-destination"`
	IPv6Mode                string `json:"ipv6-mode"`
	RemoteDNSAddress        string `json:"remote-dns-address"`
	RemoteDNSDomainStrategy string `json:"remote-dns-domain-strategy"`
	DirectDNSAddress        string `json:"direct-dns-address"`
	DirectDNSDomainStrategy string `json:"direct-dns-domain-strategy"`
	// BootstrapDNSAddress 是 Go 独有的键（Dart 不产生）：自举解析器 dns-bootstrap 的地址，必须是 IP 字面量。
	BootstrapDNSAddress    string    `json:"bootstrap-dns-address"`
	MixedPort              int       `json:"mixed-port"`
	TProxyPort             int       `json:"tproxy-port"`
	LocalDNSPort           int       `json:"local-dns-port"`
	TunImplementation      string    `json:"tun-implementation"`
	MTU                    int       `json:"mtu"`
	StrictRoute            bool      `json:"strict-route"`
	ConnectionTestURL      string    `json:"connection-test-url"`
	URLTestInterval        int       `json:"url-test-interval"`
	EnableClashAPI         bool      `json:"enable-clash-api"`
	ClashAPIPort           int       `json:"clash-api-port"`
	WebSecret              string    `json:"web-secret"`
	EnableTun              bool      `json:"enable-tun"`
	EnableTunService       bool      `json:"enable-tun-service"`
	SetSystemProxy         bool      `json:"set-system-proxy"`
	BypassLAN              bool      `json:"bypass-lan"`
	AllowConnectionFromLAN bool      `json:"allow-connection-from-lan"`
	EnableFakeDNS          bool      `json:"enable-fake-dns"`
	EnableDNSRouting       bool      `json:"enable-dns-routing"`
	IndependentDNSCache    bool      `json:"independent-dns-cache"`
	Rules                  []Rule    `json:"rules"`
	Mux                    Mux       `json:"mux"`
	TLSTricks              TLSTricks `json:"tls-tricks"`
	Warp                   Warp      `json:"warp"`
	Warp2                  Warp      `json:"warp2"`
}

// Mux 对应 `mux`。
type Mux struct {
	Enable     bool   `json:"enable"`
	Padding    bool   `json:"padding"`
	MaxStreams int    `json:"max-streams"`
	Protocol   string `json:"protocol"`
}

// TLSTricks 对应 `tls-tricks`。新内核只能兑现 enable-fragment，其余键保留但不生效（spec §5.6）。
type TLSTricks struct {
	EnableFragment bool   `json:"enable-fragment"`
	FragmentSize   string `json:"fragment-size"`
	FragmentSleep  string `json:"fragment-sleep"`
	MixedSNICase   bool   `json:"mixed-sni-case"`
	EnablePadding  bool   `json:"enable-padding"`
	PaddingSize    string `json:"padding-size"`
}

// Default 与 Dart 的 NetworkSettings 默认值一致，并取 Android 的口径：
// VPN 档（enable-tun 为真）、移动端不设置系统代理。缺省的键沿用这里的值。
func Default() *Options {
	return &Options{
		Region:                  "other",
		ExecuteConfigAsIs:       false,
		EnableFullConfig:        true,
		BlockAds:                false,
		LogLevel:                "warn",
		ResolveDestination:      false,
		IPv6Mode:                "ipv4_only",
		RemoteDNSAddress:        defaultRemoteDNS,
		RemoteDNSDomainStrategy: "",
		DirectDNSAddress:        defaultDirectDNS,
		DirectDNSDomainStrategy: "",
		BootstrapDNSAddress:     DefaultBootstrapDNS,
		MixedPort:               2080,
		TProxyPort:              2081,
		LocalDNSPort:            6450,
		TunImplementation:       "mixed",
		MTU:                     9000,
		StrictRoute:             true,
		ConnectionTestURL:       defaultConnectionTest,
		URLTestInterval:         600,
		EnableClashAPI:          true,
		ClashAPIPort:            defaultClashAPIPort,
		WebSecret:               "",
		EnableTun:               true,
		EnableTunService:        false,
		SetSystemProxy:          false,
		BypassLAN:               false,
		AllowConnectionFromLAN:  false,
		EnableFakeDNS:           false,
		EnableDNSRouting:        true,
		IndependentDNSCache:     true,
		Rules:                   []Rule{},
		Mux:                     Mux{Enable: false, Padding: false, MaxStreams: 8, Protocol: "h2mux"},
		TLSTricks: TLSTricks{
			EnableFragment: false, FragmentSize: "10-30", FragmentSleep: "50-200",
			MixedSNICase: false, EnablePadding: false, PaddingSize: "100-200",
		},
		Warp: Warp{
			Mode: WarpProxyOverWarp, CleanIP: "auto", CleanPort: 0,
			Noise: "1-3", NoiseSize: "10-30", NoiseDelay: "10-30", NoiseMode: "m6",
		},
		Warp2: Warp{
			Mode: WarpProxyOverWarp, CleanPort: 0,
			Noise: "10-15", NoiseSize: "5-10", NoiseDelay: "1-1", NoiseMode: "m4",
		},
	}
}

// Decode 把 App 传来的选项 JSON 解成 Options：缺失的键沿用 Default()；未知键进 Warnings（不是错误）；
// 已知键类型不符是错误（option-invalid:）。解码后不做值域校验，调用 Validate。
func Decode(raw []byte) (*Options, Warnings, error) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return nil, nil, invalid("empty options")
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return nil, nil, invalid("options is not a JSON object: %v", err)
	}
	var warns Warnings
	for _, key := range unknownKeys(top, reflect.TypeOf(Options{}), "") {
		warns = append(warns, Warning{WarnUnknownKey, "unknown option key " + key})
	}

	o := Default()
	// json.Unmarshal 只覆盖 JSON 里出现的键，其余保持默认值；嵌套对象同样是「逐键覆盖」。
	dec := json.NewDecoder(bytes.NewReader(raw))
	if err := dec.Decode(o); err != nil {
		var ute *json.UnmarshalTypeError
		if errors.As(err, &ute) {
			return nil, nil, invalid("%s: expected %s, got %s", ute.Field, ute.Type, ute.Value)
		}
		return nil, nil, invalid("%v", err)
	}
	if o.Rules == nil {
		o.Rules = []Rule{}
	}

	if o.Region != "other" {
		warns = append(warns, Warning{WarnRegion, fmt.Sprintf("region %q is not supported, treated as \"other\"", o.Region)})
		o.Region = "other"
	}
	if o.ClashAPINonDefault() {
		warns = append(warns, Warning{WarnClashAPI, "clash api is not built in; enable-clash-api / clash-api-port / web-secret are kept but have no effect"})
	}
	return o, warns, nil
}

// ClashAPINonDefault 报告用户是否动过 Clash API 相关选项（内核不内置 clash_api，这些选项只会被忽略）。
func (o *Options) ClashAPINonDefault() bool {
	return o.WebSecret != "" || (o.EnableClashAPI && o.ClashAPIPort != defaultClashAPIPort)
}

// unknownKeys 用结构体的 json 标签反射出已知键，列出 raw 里多出来的（嵌套对象带路径前缀）。
func unknownKeys(raw map[string]json.RawMessage, t reflect.Type, prefix string) []string {
	known := map[string]reflect.Type{}
	for i := 0; i < t.NumField(); i++ {
		tag := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]
		if tag != "" && tag != "-" {
			known[tag] = t.Field(i).Type
		}
	}
	var out []string
	keys := make([]string, 0, len(raw))
	for k := range raw {
		keys = append(keys, k)
	}
	sortStrings(keys)
	for _, k := range keys {
		ft, ok := known[k]
		if !ok {
			out = append(out, prefix+k)
			continue
		}
		if ft.Kind() == reflect.Struct {
			var nested map[string]json.RawMessage
			if json.Unmarshal(raw[k], &nested) == nil && nested != nil {
				out = append(out, unknownKeys(nested, ft, prefix+k+".")...)
			}
		}
	}
	return out
}

func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}

var (
	validIPv6Modes  = set("ipv4_only", "prefer_ipv4", "prefer_ipv6", "ipv6_only")
	validStrategies = set("", "prefer_ipv4", "prefer_ipv6", "ipv4_only", "ipv6_only")
	validTunStacks  = set("mixed", "system", "gvisor")
	validLogLevels  = set("trace", "debug", "info", "warn", "error")
	validWarpModes  = set(WarpProxyOverWarp, WarpWarpOverProxy)
)

func set(vs ...string) map[string]bool {
	m := make(map[string]bool, len(vs))
	for _, v := range vs {
		m[v] = true
	}
	return m
}

func oneOf(name, v string, valid map[string]bool) error {
	if valid[v] {
		return nil
	}
	return invalid("%s: %q is not one of %s", name, v, joinKeys(valid))
}

func joinKeys(m map[string]bool) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, strconv.Quote(k))
	}
	sortStrings(keys)
	return strings.Join(keys, ", ")
}

// Validate 校验值域：端口、MTU、枚举、自举 DNS 地址、测速地址、规则、WARP 模式。
func (o *Options) Validate() error {
	port := func(name string, v int, allowZero bool) error {
		if (v == 0 && allowZero) || (v >= 1 && v <= 65535) {
			return nil
		}
		return invalid("%s: %d is not a valid port", name, v)
	}
	checks := []error{
		port("mixed-port", o.MixedPort, false),
		port("tproxy-port", o.TProxyPort, true),
		port("local-dns-port", o.LocalDNSPort, true),
		port("clash-api-port", o.ClashAPIPort, true),
		port("warp.clean-port", o.Warp.CleanPort, true),
		port("warp2.clean-port", o.Warp2.CleanPort, true),
		oneOf("ipv6-mode", o.IPv6Mode, validIPv6Modes),
		oneOf("remote-dns-domain-strategy", o.RemoteDNSDomainStrategy, validStrategies),
		oneOf("direct-dns-domain-strategy", o.DirectDNSDomainStrategy, validStrategies),
		oneOf("tun-implementation", o.TunImplementation, validTunStacks),
		oneOf("log-level", o.LogLevel, validLogLevels),
		oneOf("warp.mode", o.Warp.Mode, validWarpModes),
		oneOf("warp2.mode", o.Warp2.Mode, validWarpModes),
	}
	for _, err := range checks {
		if err != nil {
			return err
		}
	}
	if o.MTU < 576 || o.MTU > 65535 {
		return invalid("mtu: %d is out of range 576-65535", o.MTU)
	}
	if o.URLTestInterval < 1 {
		return invalid("url-test-interval: %d must be positive", o.URLTestInterval)
	}
	if o.RemoteDNSAddress == "" {
		return invalid("remote-dns-address: must not be empty")
	}
	if o.DirectDNSAddress == "" {
		return invalid("direct-dns-address: must not be empty")
	}
	if err := ValidateBootstrapDNSAddress(o.BootstrapDNSAddress); err != nil {
		return err
	}
	if u, err := url.Parse(o.ConnectionTestURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return invalid("connection-test-url: %q is not an http(s) URL", o.ConnectionTestURL)
	}
	for i, r := range o.Rules {
		if _, err := r.Matchers(); err != nil {
			return invalid("rules[%d]: %s", i, strings.TrimPrefix(err.Error(), ErrorPrefix+" "))
		}
	}
	return nil
}

// ParseBootstrapDNSAddress 把 `223.5.5.5`、`223.5.5.5:53`、`2400:3200::1`、`[2400:3200::1]:53` 切成 (IP, 端口)；
// 端口缺省为 0（由调用方补 53）。地址必须是 IP 字面量，域名一律拒绝——它是整个 DNS 自举链的根，不能再依赖别的解析。
func ParseBootstrapDNSAddress(addr string) (netip.Addr, uint16, error) {
	s := strings.TrimSpace(addr)
	if s == "" {
		return netip.Addr{}, 0, invalid("bootstrap-dns-address: must not be empty")
	}
	if ip, err := netip.ParseAddr(s); err == nil {
		return ip, 0, nil
	}
	host, portStr, err := net.SplitHostPort(s)
	if err != nil {
		return netip.Addr{}, 0, invalid("bootstrap-dns-address: %q is not an IP literal (a domain name cannot bootstrap itself)", addr)
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return netip.Addr{}, 0, invalid("bootstrap-dns-address: host %q is not an IP literal (a domain name cannot bootstrap itself)", host)
	}
	p, err := strconv.Atoi(portStr)
	if err != nil || p < 1 || p > 65535 {
		return netip.Addr{}, 0, invalid("bootstrap-dns-address: %q is not a valid port", portStr)
	}
	return ip, uint16(p), nil
}

// ValidateBootstrapDNSAddress 只校验、不返回结果。
func ValidateBootstrapDNSAddress(addr string) error {
	_, _, err := ParseBootstrapDNSAddress(addr)
	return err
}
