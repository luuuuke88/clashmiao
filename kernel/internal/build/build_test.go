package build_test

import (
	"bytes"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

func profile(t *testing.T) build.Profile {
	t.Helper()
	p, err := build.ParseProfile([]byte(`{"outbounds":[{"type":"shadowsocks","tag":"n1","server":"example.net","server_port":8388,"method":"aes-128-gcm","password":"x"}]}`))
	if err != nil {
		t.Fatal(err)
	}
	return p
}

// enable-clash-api 加非空 web-secret：产出里没有 clash_api，且带 warning。
func TestClashAPIOptionsProduceWarningNotConfig(t *testing.T) {
	o := options.Default()
	o.EnableClashAPI, o.WebSecret = true, "synthetic-secret"
	raw, warnings, err := build.Build(profile(t), o, build.AndroidEnv())
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("clash_api")) || bytes.Contains(raw, []byte("synthetic-secret")) {
		t.Fatalf("配置里不该有 clash_api 与它的密钥:\n%s", raw)
	}
	found := false
	for _, w := range warnings {
		if strings.HasPrefix(w, options.WarnClashAPI+":") {
			found = true
		}
	}
	if !found {
		t.Fatalf("应带 %s 警告，实际 %v", options.WarnClashAPI, warnings)
	}
}

// 默认选项不动 clash 相关键时，不产生多余警告。
func TestDefaultOptionsProduceNoWarnings(t *testing.T) {
	_, warnings, err := build.Build(profile(t), options.Default(), build.AndroidEnv())
	if err != nil || len(warnings) != 0 {
		t.Fatalf("err=%v warnings=%v", err, warnings)
	}
}

func TestBuildRejectsNilOptions(t *testing.T) {
	_, _, err := build.Build(profile(t), nil, build.AndroidEnv())
	if err == nil || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
		t.Fatalf("err = %v", err)
	}
}

// IPv6 开关控制 TUN 地址族；平台不支持 v6 时即使用户选了 v6 也不带 v6 地址。
func TestIPv6ControlsTunAddress(t *testing.T) {
	has := func(o *options.Options, env build.Env) bool {
		raw, _, err := build.Build(profile(t), o, env)
		if err != nil {
			t.Fatal(err)
		}
		return bytes.Contains(raw, []byte("fdfe:dcba:9876::1/126"))
	}
	o := options.Default()
	if has(o, build.AndroidEnv()) {
		t.Error("ipv4_only 不该有 v6 地址")
	}
	o.IPv6Mode = "prefer_ipv6"
	if !has(o, build.AndroidEnv()) {
		t.Error("prefer_ipv6 应有 v6 地址")
	}
	if has(o, build.Env{GOOS: "android", IPv6Supported: false}) {
		t.Error("平台不支持 v6 时不该有 v6 地址")
	}
}

// 允许局域网时 mixed-in / dns-in 监听所有地址，否则只监听回环。
func TestAllowLANControlsListen(t *testing.T) {
	o := options.Default()
	raw, _, _ := build.Build(profile(t), o, build.AndroidEnv())
	if bytes.Contains(raw, []byte(`"listen": "0.0.0.0"`)) {
		t.Error("默认不该监听 0.0.0.0")
	}
	o.AllowConnectionFromLAN = true
	raw, _, _ = build.Build(profile(t), o, build.AndroidEnv())
	if !bytes.Contains(raw, []byte(`"listen": "0.0.0.0"`)) {
		t.Error("允许局域网应监听 0.0.0.0")
	}
}

func TestParseProfileRejectsGarbage(t *testing.T) {
	if _, err := build.ParseProfile([]byte("not json")); err == nil || !strings.HasPrefix(err.Error(), build.PrefixBuildFailed) {
		t.Fatalf("err = %v", err)
	}
}
