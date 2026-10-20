// Package warp 负责 Cloudflare WARP：账号注册（register.go）、WireGuard 端点生成（endpoint.go）。
// 本包不 import sing-box；端点以 map[string]any 产出，由 internal/build 装配进出站图。
package warp

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"strings"
)

// WireguardConfig 是 `warp.wireguard-config` 选项里存的那份 JSON（旧 Dart 原样存取、不解析）：
// 键名与旧契约一致，由 GenerateWarpConfig 产出。
type WireguardConfig struct {
	PrivateKey       string `json:"private-key"`
	LocalAddressIPv4 string `json:"local-address-ipv4"`
	LocalAddressIPv6 string `json:"local-address-ipv6"`
	PeerPublicKey    string `json:"peer-public-key"`
	// ClientID 是 base64 的 3 个字节（Cloudflare 的 reserved 字段）。
	ClientID string `json:"client-id"`
}

// ErrConfig 表示 wireguard-config 不可用；错误信息以 "warp-config-invalid:" 开头。
var ErrConfig = errors.New("warp-config-invalid")

func configError(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrConfig, fmt.Sprintf(format, args...))
}

// ParseConfig 解析并校验 wireguard-config：密钥必须是 32 字节的 base64，地址必须可解析，client-id 解出 3 字节。
func ParseConfig(raw string) (WireguardConfig, error) {
	var c WireguardConfig
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return c, configError("wireguard-config is empty; generate a WARP account first")
	}
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		return c, configError("not a JSON object: %v", err)
	}
	for name, key := range map[string]string{"private-key": c.PrivateKey, "peer-public-key": c.PeerPublicKey} {
		if err := checkKey(key); err != nil {
			return c, configError("%s: %v", name, err)
		}
	}
	if _, err := prefixOf(c.LocalAddressIPv4, 4, 24); err != nil {
		return c, configError("local-address-ipv4: %v", err)
	}
	if c.LocalAddressIPv6 != "" {
		if _, err := prefixOf(c.LocalAddressIPv6, 6, 128); err != nil {
			return c, configError("local-address-ipv6: %v", err)
		}
	}
	if c.ClientID != "" {
		if _, err := c.Reserved(); err != nil {
			return c, configError("client-id: %v", err)
		}
	}
	return c, nil
}

func checkKey(k string) error {
	b, err := base64.StdEncoding.DecodeString(k)
	if err != nil {
		return fmt.Errorf("not base64: %v", err)
	}
	if len(b) != 32 {
		return fmt.Errorf("expected 32 bytes, got %d", len(b))
	}
	return nil
}

// Reserved 返回 client-id 的前 3 个字节；没有 client-id 返回 nil。
func (c WireguardConfig) Reserved() ([]int, error) {
	if c.ClientID == "" {
		return nil, nil
	}
	b, err := base64.StdEncoding.DecodeString(c.ClientID)
	if err != nil {
		return nil, fmt.Errorf("not base64: %v", err)
	}
	if len(b) < 3 {
		return nil, fmt.Errorf("expected at least 3 bytes, got %d", len(b))
	}
	return []int{int(b[0]), int(b[1]), int(b[2])}, nil
}

// prefixOf 把地址规范成带前缀长度的 CIDR：已经带前缀就原样保留；family 是 4 或 6。
func prefixOf(addr string, family, defaultBits int) (string, error) {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return "", errors.New("empty")
	}
	if strings.Contains(addr, "/") {
		p, err := netip.ParsePrefix(addr)
		if err != nil {
			return "", err
		}
		if (family == 4) != p.Addr().Is4() {
			return "", fmt.Errorf("%s is not an IPv%d address", addr, family)
		}
		return p.String(), nil
	}
	a, err := netip.ParseAddr(addr)
	if err != nil {
		return "", err
	}
	if (family == 4) != a.Is4() {
		return "", fmt.Errorf("%s is not an IPv%d address", addr, family)
	}
	return netip.PrefixFrom(a, defaultBits).String(), nil
}
