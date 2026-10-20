package gate

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/build/e2e"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// ProfileDir 是 profile 夹具目录（相对 gate 包的测试工作目录）。
const ProfileDir = "../testdata/profiles"

// LoadProfile 读取 P1..P7 之一（测试数据全合成，见各文件头的 `_comment`）。
func LoadProfile(t testing.TB, name string) build.Profile {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(ProfileDir, name+".json"))
	if err != nil {
		t.Fatal(err)
	}
	p, err := build.ParseProfile(raw)
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return p
}

// ProfileNames 列出目录里的全部 profile 夹具名。
func ProfileNames(t testing.TB) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(ProfileDir, "P*.json"))
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, f := range files {
		b := filepath.Base(f)
		names = append(names, b[:len(b)-len(".json")])
	}
	sort.Strings(names)
	return names
}

// 选项夹具 O1–O9 的构造器。都从 Android 口径的 Default() 起步，只改该夹具关心的键。
var optionFixtures = map[string]func(o *options.Options){
	// O1：Android VPN 智能分流（默认）。
	"O1": func(o *options.Options) {},
	// O2：Android 仅线路（无 tun）。
	"O2": func(o *options.Options) { o.EnableTun = false },
	// O3：fake DNS + DNS 路由 + 绕过局域网。
	"O3": func(o *options.Options) { o.EnableFakeDNS, o.EnableDNSRouting, o.BypassLAN = true, true, true },
	// O4：mux + 分片。
	"O4": func(o *options.Options) { o.Mux.Enable, o.TLSTricks.EnableFragment = true, true },
	// O5a / O5b：WARP 两种模式（U13 才有实际行为；这里只定义选项）。
	"O5a": func(o *options.Options) { o.Warp.Enable, o.Warp.Mode = true, options.WarpProxyOverWarp },
	"O5b": func(o *options.Options) { o.Warp.Enable, o.Warp.Mode = true, options.WarpWarpOverProxy },
	// O6-*：远程与直连 DNS 各地址形态（U5 才有实际行为）。
	"O6-ip":                func(o *options.Options) { o.RemoteDNSAddress, o.DirectDNSAddress = "1.1.1.1", "223.5.5.5" },
	"O6-https-domain":      func(o *options.Options) { o.RemoteDNSAddress = "https://doh.example.net/dns-query" },
	"O6-https-ip":          func(o *options.Options) { o.RemoteDNSAddress = "https://1.1.1.1/dns-query" },
	"O6-h3":                func(o *options.Options) { o.RemoteDNSAddress = "h3://doh.example.net/dns-query" },
	"O6-tls":               func(o *options.Options) { o.RemoteDNSAddress = "tls://dot.example.net" },
	"O6-quic":              func(o *options.Options) { o.RemoteDNSAddress = "quic://doq.example.net" },
	"O6-tcp":               func(o *options.Options) { o.RemoteDNSAddress = "tcp://1.1.1.1" },
	"O6-udp":               func(o *options.Options) { o.RemoteDNSAddress = "udp://1.1.1.1" },
	"O6-local":             func(o *options.Options) { o.RemoteDNSAddress = "local" },
	"O6-direct-doh-domain": func(o *options.Options) { o.DirectDNSAddress = "https://doh.example.net/dns-query" },
	// O7：IPv6 三种模式。
	"O7-ipv4":   func(o *options.Options) { o.IPv6Mode = "ipv4_only" },
	"O7-prefer": func(o *options.Options) { o.IPv6Mode = "prefer_ipv6" },
	"O7-only":   func(o *options.Options) { o.IPv6Mode = "ipv6_only" },
	// O8：允许局域网连接。
	"O8": func(o *options.Options) { o.AllowConnectionFromLAN = true },
	// O9：屏蔽广告开关。
	"O9": func(o *options.Options) { o.BlockAds = true },
}

// OptionNames 列出全部选项夹具名。
func OptionNames() []string {
	names := make([]string, 0, len(optionFixtures))
	for n := range optionFixtures {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// Option 返回选项夹具（每次一份新的，可放心改）。
func Option(name string) *options.Options {
	mod, ok := optionFixtures[name]
	if !ok {
		panic(fmt.Sprintf("gate: 没有选项夹具 %q", name))
	}
	o := options.Default()
	mod(o)
	return o
}

// UseFakeNodes 把 profile 里的每个叶子出站换成指向假节点的 socks 出站（tag 不变），并丢掉端点：
// 主机上没有真实的远端，真启动与真流量测试都经假节点验证路径。
func UseFakeNodes(p build.Profile, node *e2e.Node) build.Profile {
	out := build.Profile{}
	for _, n := range p.Outbounds {
		tag, _ := n["tag"].(string)
		switch n["type"] {
		case "selector", "urltest", "direct", "block", "dns":
			out.Outbounds = append(out.Outbounds, n)
		default:
			out.Outbounds = append(out.Outbounds, node.Outbound(tag))
		}
	}
	return out
}
