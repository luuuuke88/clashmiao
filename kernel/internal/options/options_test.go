package options

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
)

// 与 Dart `getDefaultConfigOptions()` 在默认设置（Android，VPN 档，非智能分流）下的输出逐键对照。
// 这是硬编码的期望表，不从 Default() 派生：任何一边改了默认值，这里都会失败。
var dartDefaults = map[string]any{
	"region": "other", "execute-config-as-is": false, "enable-full-config": true, "block-ads": false,
	"log-level": "warn", "resolve-destination": false, "ipv6-mode": "ipv4_only",
	"remote-dns-address": "https://1.1.1.1/dns-query", "remote-dns-domain-strategy": "",
	"direct-dns-address": "223.5.5.5", "direct-dns-domain-strategy": "",
	"bootstrap-dns-address": "223.5.5.5", // Go 独有
	"mixed-port":            float64(2080), "tproxy-port": float64(2081), "local-dns-port": float64(6450),
	"tun-implementation": "mixed", "mtu": float64(9000), "strict-route": true,
	"connection-test-url": "http://connectivitycheck.gstatic.com/generate_204", "url-test-interval": float64(600),
	"enable-clash-api": true, "clash-api-port": float64(6756), "web-secret": "", // web-secret：Go 独有
	"enable-tun": true, "enable-tun-service": false, "set-system-proxy": false, "bypass-lan": false,
	"allow-connection-from-lan": false, "enable-fake-dns": false, "enable-dns-routing": true,
	"independent-dns-cache": true, "rules": []any{},
	"mux": map[string]any{"enable": false, "padding": false, "max-streams": float64(8), "protocol": "h2mux"},
	"tls-tricks": map[string]any{
		"enable-fragment": false, "fragment-size": "10-30", "fragment-sleep": "50-200",
		"mixed-sni-case": false, "enable-padding": false, "padding-size": "100-200",
	},
	"warp": map[string]any{
		"enable": false, "mode": "proxy_over_warp", "wireguard-config": "", "license-key": "",
		"account-id": "", "access-token": "", "clean-ip": "auto", "clean-port": float64(0),
		"noise": "1-3", "noise-size": "10-30", "noise-delay": "10-30", "noise-mode": "m6",
	},
	"warp2": map[string]any{
		"enable": false, "mode": "proxy_over_warp", "wireguard-config": "", "license-key": "",
		"account-id": "", "access-token": "", "clean-ip": "", "clean-port": float64(0),
		"noise": "10-15", "noise-size": "5-10", "noise-delay": "1-1", "noise-mode": "m4",
	},
}

func TestDefaultMatchesDartDefaults(t *testing.T) {
	raw, err := json.Marshal(Default())
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, dartDefaults) {
		for k, want := range dartDefaults {
			if !reflect.DeepEqual(got[k], want) {
				t.Errorf("%s: got %#v, want %#v", k, got[k], want)
			}
		}
		for k := range got {
			if _, ok := dartDefaults[k]; !ok {
				t.Errorf("Default() has key %q that the table does not know", k)
			}
		}
	}
	if err := Default().Validate(); err != nil {
		t.Fatalf("Default() must validate: %v", err)
	}
}

func TestDecodeDefaultFixtureEqualsDefault(t *testing.T) {
	raw, err := os.ReadFile("../../testdata/options/default.json")
	if err != nil {
		t.Fatal(err)
	}
	o, warns, err := Decode(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(warns) != 0 {
		t.Fatalf("unexpected warnings: %v", warns)
	}
	if !reflect.DeepEqual(o, Default()) {
		t.Fatalf("decoded fixture != Default():\n got: %+v\nwant: %+v", o, Default())
	}
}

func TestDecodePartialKeepsDefaults(t *testing.T) {
	o, warns, err := Decode([]byte(`{"mixed-port": 7890, "mux": {"enable": true}}`))
	if err != nil || len(warns) != 0 {
		t.Fatalf("err=%v warns=%v", err, warns)
	}
	if o.MixedPort != 7890 || !o.Mux.Enable {
		t.Fatalf("overrides lost: %+v", o)
	}
	if o.Mux.MaxStreams != 8 || o.Mux.Protocol != "h2mux" || o.MTU != 9000 {
		t.Fatalf("defaults lost: %+v", o)
	}
}

func TestDecodeUnknownKeysAreWarnings(t *testing.T) {
	o, warns, err := Decode([]byte(`{"mixed-port": 2080, "brand-new": 1, "mux": {"enable": true, "future": "x"}, "warp": {"nope": 1}}`))
	if err != nil {
		t.Fatalf("unknown keys must not be errors: %v", err)
	}
	if o.MixedPort != 2080 {
		t.Fatal("known key lost")
	}
	var got []string
	for _, w := range warns {
		if w.Code != WarnUnknownKey {
			t.Fatalf("unexpected warning %v", w)
		}
		got = append(got, w.Message)
	}
	want := []string{"unknown option key brand-new", "unknown option key mux.future", "unknown option key warp.nope"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("warnings = %v, want %v", got, want)
	}
}

func TestDecodeErrors(t *testing.T) {
	cases := []struct{ name, in, want string }{
		{"empty", ``, "empty options"},
		{"blank", "  \n", "empty options"},
		{"not json", `{`, "not a JSON object"},
		{"array", `[1]`, "not a JSON object"},
		{"port as string", `{"mixed-port": "2080"}`, "mixed-port"},
		{"bool as number", `{"strict-route": 1}`, "strict-route"},
		{"nested type", `{"mux": {"enable": "yes"}}`, "enable"},
		{"rules as object", `{"rules": {}}`, "rules"},
		{"top-level null", `null`, "got null"},
		{"null for a known number", `{"mixed-port": null}`, "mixed-port: must not be null"},
		{"null for a known bool", `{"strict-route": null}`, "strict-route: must not be null"},
		{"null for a known string", `{"remote-dns-address": null}`, "remote-dns-address: must not be null"},
		{"null for a nested key", `{"mux": {"enable": null}}`, "mux.enable: must not be null"},
		{"null for a nested object", `{"mux": null}`, "mux: must not be null"},
	}
	for _, c := range cases {
		_, _, err := Decode([]byte(c.in))
		if err == nil {
			t.Errorf("%s: want error", c.name)
			continue
		}
		if !IsOptionError(err) || !strings.HasPrefix(err.Error(), ErrorPrefix) || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: error %q should start with %q and mention %q", c.name, err, ErrorPrefix, c.want)
		}
	}
}

func TestRegionOtherThanOtherWarnsAndNormalizes(t *testing.T) {
	o, warns, err := Decode([]byte(`{"region": "ir"}`))
	if err != nil || !warns.Has(WarnRegion) || o.Region != "other" {
		t.Fatalf("o=%v warns=%v err=%v", o, warns, err)
	}
}

func TestClashKeysNeverFailButWarnWhenNonDefault(t *testing.T) {
	for name, in := range map[string]string{
		"non-default port": `{"enable-clash-api": true, "clash-api-port": 9090}`,
		"secret":           `{"web-secret": "s3cr3t"}`,
		"port + secret":    `{"clash-api-port": 9090, "web-secret": "x"}`,
	} {
		o, warns, err := Decode([]byte(in))
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if !warns.Has(WarnClashAPI) {
			t.Errorf("%s: want %s warning, got %v", name, WarnClashAPI, warns)
		}
		if err := o.Validate(); err != nil {
			t.Errorf("%s: clash keys must not fail validation: %v", name, err)
		}
	}
	for name, in := range map[string]string{
		"defaults": `{"enable-clash-api": true, "clash-api-port": 6756, "web-secret": ""}`,
		"disabled": `{"enable-clash-api": false, "clash-api-port": 9090}`,
		"nothing":  `{}`,
	} {
		_, warns, err := Decode([]byte(in))
		if err != nil || warns.Has(WarnClashAPI) {
			t.Errorf("%s: err=%v warns=%v (no clash warning expected)", name, err, warns)
		}
	}
}

func TestBootstrapDNSAddress(t *testing.T) {
	ok := []string{"223.5.5.5", "223.5.5.5:53", "1.1.1.1:5353", "2400:3200::1", "[2400:3200::1]:53", "  8.8.8.8 "}
	bad := []string{"", " ", "dns.example.net", "dns.example.net:53", ":53", "223.5.5.5:", "223.5.5.5:0", "223.5.5.5:70000",
		"223.5.5.5:abc", "[2400:3200::1", "https://1.1.1.1/dns-query", "223.5.5.5/24", "localhost"}
	for _, a := range ok {
		if err := ValidateBootstrapDNSAddress(a); err != nil {
			t.Errorf("%q should be accepted: %v", a, err)
		}
	}
	for _, a := range bad {
		err := ValidateBootstrapDNSAddress(a)
		if err == nil {
			t.Errorf("%q should be rejected", a)
		} else if !IsOptionError(err) {
			t.Errorf("%q: not an option error: %v", a, err)
		}
	}
	// 通过 Options.Validate 也走同一条
	o := Default()
	o.BootstrapDNSAddress = "doh.example.net"
	if err := o.Validate(); err == nil || !strings.Contains(err.Error(), "bootstrap-dns-address") {
		t.Fatalf("Validate should reject a domain bootstrap: %v", err)
	}
	ip, port, err := ParseBootstrapDNSAddress("[2400:3200::1]:5353")
	if err != nil || ip.String() != "2400:3200::1" || port != 5353 {
		t.Fatalf("parse = %v %d %v", ip, port, err)
	}
}

func mutate(f func(*Options)) *Options {
	o := Default()
	f(o)
	return o
}

func TestValidateBoundaries(t *testing.T) {
	cases := []struct {
		name string
		o    *Options
		ok   bool
	}{
		{"mixed-port 1", mutate(func(o *Options) { o.MixedPort = 1 }), true},
		{"mixed-port 65535", mutate(func(o *Options) { o.MixedPort = 65535 }), true},
		{"mixed-port 0", mutate(func(o *Options) { o.MixedPort = 0 }), false},
		{"mixed-port 65536", mutate(func(o *Options) { o.MixedPort = 65536 }), false},
		{"local-dns-port 0 (disabled)", mutate(func(o *Options) { o.LocalDNSPort = 0 }), true},
		{"local-dns-port 65536", mutate(func(o *Options) { o.LocalDNSPort = 65536 }), false},
		{"tproxy-port -1", mutate(func(o *Options) { o.TProxyPort = -1 }), false},
		{"clash-api-port 70000", mutate(func(o *Options) { o.ClashAPIPort = 70000 }), false},
		{"warp clean-port 0", mutate(func(o *Options) { o.Warp.CleanPort = 0 }), true},
		{"warp clean-port 70000", mutate(func(o *Options) { o.Warp.CleanPort = 70000 }), false},
		{"mtu 576", mutate(func(o *Options) { o.MTU = 576 }), true},
		{"mtu 575", mutate(func(o *Options) { o.MTU = 575 }), false},
		{"mtu 65535", mutate(func(o *Options) { o.MTU = 65535 }), true},
		{"mtu 65536", mutate(func(o *Options) { o.MTU = 65536 }), false},
		{"ipv6-mode prefer_ipv6", mutate(func(o *Options) { o.IPv6Mode = "prefer_ipv6" }), true},
		{"ipv6-mode ipv6_only", mutate(func(o *Options) { o.IPv6Mode = "ipv6_only" }), true},
		{"ipv6-mode dual", mutate(func(o *Options) { o.IPv6Mode = "dual" }), false},
		{"remote strategy empty", mutate(func(o *Options) { o.RemoteDNSDomainStrategy = "" }), true},
		{"remote strategy prefer_ipv4", mutate(func(o *Options) { o.RemoteDNSDomainStrategy = "prefer_ipv4" }), true},
		{"remote strategy bogus", mutate(func(o *Options) { o.RemoteDNSDomainStrategy = "ipv4" }), false},
		{"direct strategy bogus", mutate(func(o *Options) { o.DirectDNSDomainStrategy = "x" }), false},
		{"tun stack gvisor", mutate(func(o *Options) { o.TunImplementation = "gvisor" }), true},
		{"tun stack system", mutate(func(o *Options) { o.TunImplementation = "system" }), true},
		{"tun stack lwip", mutate(func(o *Options) { o.TunImplementation = "lwip" }), false},
		{"log-level error", mutate(func(o *Options) { o.LogLevel = "error" }), true},
		{"log-level trace", mutate(func(o *Options) { o.LogLevel = "trace" }), true},
		{"log-level fatal", mutate(func(o *Options) { o.LogLevel = "fatal" }), false},
		{"warp mode warp_over_proxy", mutate(func(o *Options) { o.Warp.Mode = WarpWarpOverProxy }), true},
		{"warp mode bogus", mutate(func(o *Options) { o.Warp.Mode = "warpOverProxy" }), false}, // Dart 的驼峰串必须在 Dart 侧转好
		{"warp2 mode bogus", mutate(func(o *Options) { o.Warp2.Mode = "" }), false},
		{"url-test-interval 0", mutate(func(o *Options) { o.URLTestInterval = 0 }), false},
		{"url-test-interval 1", mutate(func(o *Options) { o.URLTestInterval = 1 }), true},
		{"test url not http", mutate(func(o *Options) { o.ConnectionTestURL = "ftp://example.com/x" }), false},
		{"test url empty", mutate(func(o *Options) { o.ConnectionTestURL = "" }), false},
		{"empty remote dns", mutate(func(o *Options) { o.RemoteDNSAddress = "" }), false},
		{"empty direct dns", mutate(func(o *Options) { o.DirectDNSAddress = "" }), false},
		{"bad rule", mutate(func(o *Options) { o.Rules = []Rule{{Outbound: "reject"}} }), false},
		{"good rule", mutate(func(o *Options) { o.Rules = []Rule{{IP: "10.0.0.0/8", Outbound: "bypass"}} }), true},
	}
	for _, c := range cases {
		err := c.o.Validate()
		if c.ok && err != nil {
			t.Errorf("%s: unexpected error %v", c.name, err)
		}
		if !c.ok {
			if err == nil {
				t.Errorf("%s: expected error", c.name)
			} else if !IsOptionError(err) {
				t.Errorf("%s: not an option error: %v", c.name, err)
			}
		}
	}
}

// 切片键的 null 仍按「空」处理（App 以前可能这么发），不属于类型错误。
func TestDecodeNullRulesIsEmpty(t *testing.T) {
	o, _, err := Decode([]byte(`{"rules": null}`))
	if err != nil || o.Rules == nil || len(o.Rules) != 0 {
		t.Fatalf("rules:null = %v %v", o.Rules, err)
	}
}
