package uri

import (
	"strconv"
	"strings"
)

func init() {
	Register("wg", convertWireGuard)
	Register("wireguard", convertWireGuard)
}

// convertWireGuard：wg://host:port?publicKey=…&privateKey=…&address=10.0.0.2/32&reserved=1,2,3&mtu=1420&presharedKey=…&allowedIPs=…#name
// 私钥也可以放在 userinfo（wireguard://privateKey@host:port）。产出是端点（Endpoint=true），不是出站。
func convertWireGuard(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	priv := l.query.get("privateKey", "private_key", "secretKey", "secret_key")
	if priv == "" {
		priv = l.credentials()
	}
	pub := l.query.get("publicKey", "public_key", "peerPublicKey", "peer_public_key")
	if priv == "" {
		return Entity{}, invalidf("wireguard", "missing private key")
	}
	if pub == "" {
		return Entity{}, invalidf("wireguard", "missing peer public key")
	}
	var addrs []string
	for _, a := range append(splitList(l.query.get("address", "ip", "localAddress", "local_address")), splitList(l.query.get("ipv6"))...) {
		addrs = append(addrs, withMask(a))
	}
	if len(addrs) == 0 {
		return Entity{}, invalidf("wireguard", "missing local address")
	}

	peer := map[string]any{"address": l.host, "port": l.port, "public_key": pub}
	if psk := l.query.get("presharedKey", "preSharedKey", "pre_shared_key", "psk"); psk != "" {
		peer["pre_shared_key"] = psk
	}
	allowed := splitList(l.query.get("allowedIPs", "allowed_ips", "allowedips"))
	if len(allowed) == 0 {
		allowed = []string{"0.0.0.0/0", "::/0"}
	}
	peer["allowed_ips"] = toAnyList(allowed)
	if r := l.query.get("reserved"); r != "" {
		res, err := parseReserved(r)
		if err != nil {
			return Entity{}, invalidf("wireguard", "bad reserved %q", r)
		}
		peer["reserved"] = res
	}

	out := map[string]any{"type": "wireguard", "tag": l.tag(), "address": toAnyList(addrs), "private_key": priv, "peers": []any{peer}}
	if v := l.query.get("mtu"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 576 || n > 65535 {
			return Entity{}, invalidf("wireguard", "bad mtu %q", v)
		}
		out["mtu"] = n
	}
	return Entity{Map: out, Endpoint: true}, nil
}

// withMask 给没带掩码的地址补 /32 或 /128。
func withMask(a string) string {
	if strings.Contains(a, "/") {
		return a
	}
	if strings.Contains(a, ":") {
		return a + "/128"
	}
	return a + "/32"
}

// parseReserved 接受「1,2,3」（三个 0–255 的整数）或 3 字节的 base64。
func parseReserved(s string) ([]any, error) {
	var out []any
	if strings.Contains(s, ",") {
		for _, p := range splitList(s) {
			n, err := strconv.Atoi(p)
			if err != nil || n < 0 || n > 255 {
				return nil, ErrInvalid
			}
			out = append(out, n)
		}
	} else if dec, err := decodeB64(s); err == nil {
		for _, b := range dec {
			out = append(out, int(b))
		}
	}
	if len(out) != 3 {
		return nil, ErrInvalid
	}
	return out, nil
}
