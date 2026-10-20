package uri

import "testing"

func TestWireGuard(t *testing.T) {
	peer := func(host string, port int, extra ...any) map[string]any {
		return m(append([]any{"address", host, "port", port, "public_key", testKey2, "allowed_ips", list("0.0.0.0/0", "::/0")}, extra...)...)
	}
	cases := []convCase{
		{name: "基本（私钥在查询里）", endpoint: true, in: "wg://w1.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&address=10.0.0.2%2F32#w1",
			want: m("type", "wireguard", "tag", "w1", "address", list("10.0.0.2/32"), "private_key", testKey1, "peers", []any{peer("w1.example.net", 51820)})},
		{name: "wireguard:// 别名，私钥在 userinfo", endpoint: true, in: "wireguard://" + testKey1Q + "@w2.example.net:51820?publicKey=" + testKey2Q + "&ip=10.0.0.3#w2",
			want: m("type", "wireguard", "tag", "w2", "address", list("10.0.0.3/32"), "private_key", testKey1, "peers", []any{peer("w2.example.net", 51820)})},
		{name: "地址补掩码（v4 与 v6）", endpoint: true, in: "wg://w3.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&address=10.0.0.4,fd00::4#w3",
			want: m("type", "wireguard", "tag", "w3", "address", list("10.0.0.4/32", "fd00::4/128"), "private_key", testKey1, "peers", []any{peer("w3.example.net", 51820)})},
		{name: "ipv6 参数追加到地址", endpoint: true, in: "wg://w4.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.5&ipv6=fd00::5#w4",
			want: m("type", "wireguard", "tag", "w4", "address", list("10.0.0.5/32", "fd00::5/128"), "private_key", testKey1, "peers", []any{peer("w4.example.net", 51820)})},
		{name: "reserved 三个整数", endpoint: true, in: "wg://w5.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.6&reserved=1,2,3#w5",
			want: m("type", "wireguard", "tag", "w5", "address", list("10.0.0.6/32"), "private_key", testKey1, "peers", []any{peer("w5.example.net", 51820, "reserved", []any{1, 2, 3})})},
		{name: "reserved base64", endpoint: true, in: "wg://w6.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.7&reserved=AQID#w6",
			want: m("type", "wireguard", "tag", "w6", "address", list("10.0.0.7/32"), "private_key", testKey1, "peers", []any{peer("w6.example.net", 51820, "reserved", []any{1, 2, 3})})},
		{name: "mtu 与预共享密钥", endpoint: true, in: "wg://w7.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.8&mtu=1280&presharedKey=" + testKey1Q + "#w7",
			want: m("type", "wireguard", "tag", "w7", "address", list("10.0.0.8/32"), "private_key", testKey1, "mtu", 1280,
				"peers", []any{peer("w7.example.net", 51820, "pre_shared_key", testKey1)})},
		{name: "自定义 allowedIPs", endpoint: true, in: "wg://w8.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.9&allowedIPs=10.0.0.0/8,192.168.0.0/16#w8",
			want: m("type", "wireguard", "tag", "w8", "address", list("10.0.0.9/32"), "private_key", testKey1,
				"peers", []any{m("address", "w8.example.net", "port", 51820, "public_key", testKey2, "allowed_ips", list("10.0.0.0/8", "192.168.0.0/16"))})},
		{name: "IPv6 对端", endpoint: true, in: "wg://[2001:db8::17]:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.10#v6",
			want: m("type", "wireguard", "tag", "v6", "address", list("10.0.0.10/32"), "private_key", testKey1, "peers", []any{peer("2001:db8::17", 51820)})},
		{name: "无名称", endpoint: true, in: "wg://192.0.2.18:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.11",
			want: m("type", "wireguard", "tag", "192.0.2.18:51820", "address", list("10.0.0.11/32"), "private_key", testKey1, "peers", []any{peer("192.0.2.18", 51820)})},
		{name: "密钥里的 + 保持字面量（不被当成空格）", endpoint: true, in: "wg://w12.example.net:51820?privateKey=" + plusSlashKey + "&publicKey=" + testKey2Q + "&ip=10.0.0.12#w12",
			want: m("type", "wireguard", "tag", "w12", "address", list("10.0.0.12/32"), "private_key", plusSlashKeyRaw, "peers", []any{peer("w12.example.net", 51820)})},
		{name: "密钥里的 + 不转义也保持字面量", endpoint: true, in: "wg://w13.example.net:51820?privateKey=" + plusSlashKeyRaw + "&publicKey=" + testKey2Q + "&ip=10.0.0.13#w13",
			want: m("type", "wireguard", "tag", "w13", "address", list("10.0.0.13/32"), "private_key", plusSlashKeyRaw, "peers", []any{peer("w13.example.net", 51820)})},

		{name: "缺私钥", in: "wg://a.example.net:51820?publicKey=" + testKey2Q + "&ip=10.0.0.2", err: "missing private key"},
		{name: "缺对端公钥", in: "wg://a.example.net:51820?privateKey=" + testKey1Q + "&ip=10.0.0.2", err: "missing peer public key"},
		{name: "缺本地地址", in: "wg://a.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q, err: "missing local address"},
		{name: "reserved 非法", in: "wg://a.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.2&reserved=1,2", err: "bad reserved"},
		{name: "mtu 非法", in: "wg://a.example.net:51820?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.2&mtu=10", err: "bad mtu"},
		{name: "缺端口", in: "wg://a.example.net?privateKey=" + testKey1Q + "&publicKey=" + testKey2Q + "&ip=10.0.0.2", err: "missing port"},
	}
	runCases(t, "wireguard", cases)
}

// 一把含 + 与 / 的 32 字节合成密钥（0xfb × 16 + 0xff × 16）：URL 查询里的 + 不能被当成空格。
const plusSlashKeyRaw = "+/v7+/v7+/v7+/v7+/////////////////////8="

var plusSlashKey = quoteKey(plusSlashKeyRaw)

// 密钥在链接里要百分号编码（= 与 / 与 +）。
var (
	testKey1Q = quoteKey(testKey1)
	testKey2Q = quoteKey(testKey2)
)

func quoteKey(k string) string {
	var out []byte
	for i := 0; i < len(k); i++ {
		switch k[i] {
		case '=':
			out = append(out, "%3D"...)
		case '/':
			out = append(out, "%2F"...)
		case '+':
			out = append(out, "%2B"...)
		default:
			out = append(out, k[i])
		}
	}
	return string(out)
}
