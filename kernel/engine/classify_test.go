package engine

import (
	"errors"
	"fmt"
	"net"
	"strings"
	"testing"
)

func startErr(t *testing.T, cfg string) error {
	t.Helper()
	e, _ := newTestEngine(t, newFakeHost())
	err := e.Start(cfg)
	if err == nil {
		t.Fatal("Start unexpectedly succeeded")
	}
	return err
}

func TestClassifyInvalidConfigIsCreateService(t *testing.T) {
	err := startErr(t, `{not json`)
	if !strings.HasPrefix(err.Error(), PrefixCreateService) {
		t.Fatalf("error = %q, want prefix %q", err, PrefixCreateService)
	}
	var se *StartError
	if !errors.As(err, &se) || se.Prefix != PrefixCreateService {
		t.Fatalf("not a create-service StartError: %v", err)
	}
}

func TestClassifyUnknownOutboundTypeIsCreateService(t *testing.T) {
	cfg := `{"outbounds":[{"type":"no-such-protocol","tag":"x"}]}`
	err := startErr(t, cfg)
	if !strings.HasPrefix(err.Error(), PrefixCreateService) {
		t.Fatalf("error = %q, want prefix %q", err, PrefixCreateService)
	}
}

func TestClassifyPortInUseIsStartService(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	port := l.Addr().(*net.TCPAddr).Port
	err = startErr(t, testConfig(port, ""))
	if !strings.HasPrefix(err.Error(), PrefixStartService) {
		t.Fatalf("error = %q, want prefix %q", err, PrefixStartService)
	}
}

// 附录 A.2 的坑：DNS 服务器的 detour 指向一个没有任何选项的 direct 出站，
// CheckConfig 放行、真正 Start 才拒绝。固化成回归测试：必须归类为 start-service。
func dnsDetourConfig(port int, directOutbound string) string {
	return fmt.Sprintf(`{
  "log": {"level": "warn"},
  "dns": {"servers": [{"type": "udp", "tag": "d", "server": "223.5.5.5", "detour": "direct"}], "final": "d"},
  "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": %d}],
  "outbounds": [%s],
  "route": {"final": "direct", "default_domain_resolver": "d"}
}`, port, directOutbound)
}

func TestClassifyDNSDetourToEmptyDirectIsStartService(t *testing.T) {
	err := startErr(t, dnsDetourConfig(freePort(t), `{"type": "direct", "tag": "direct"}`))
	if !strings.HasPrefix(err.Error(), PrefixStartService) {
		t.Fatalf("error = %q, want prefix %q", err, PrefixStartService)
	}
	if !strings.Contains(err.Error(), "empty direct") {
		t.Fatalf("error should name the empty-direct problem: %q", err)
	}
}

// 对照：direct 出站带了「不是零值」的选项之后才是合法的 detour 目标。
// udp_fragment 是 *bool：显式写 true 与 direct 的默认行为相同，但选项结构不再是空的。
// 注意 tcp_fast_open: false 是零值，上游照样判为「空 direct」（计划里原先的写法行不通）。
func TestDNSDetourToDirectWithOptions(t *testing.T) {
	t.Run("udp_fragment true is a valid target", func(t *testing.T) {
		e, _ := newTestEngine(t, newFakeHost())
		cfg := dnsDetourConfig(freePort(t), `{"type": "direct", "tag": "direct", "udp_fragment": true}`)
		if err := e.Start(cfg); err != nil {
			t.Fatalf("Start: %v", err)
		}
	})
	t.Run("tcp_fast_open false is still empty", func(t *testing.T) {
		err := startErr(t, dnsDetourConfig(freePort(t), `{"type": "direct", "tag": "direct", "tcp_fast_open": false}`))
		if !strings.HasPrefix(err.Error(), PrefixStartService) || !strings.Contains(err.Error(), "empty direct") {
			t.Fatalf("error = %q", err)
		}
	})
}
