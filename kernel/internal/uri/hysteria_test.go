package uri

import "testing"

func TestHysteria(t *testing.T) {
	tls := func(sni string, extra ...any) map[string]any {
		return m(append([]any{"enabled", true, "server_name", sni}, extra...)...)
	}
	cases := []convCase{
		{name: "基本", in: "hysteria://h1.example.net:443?auth=a1&upmbps=50&downmbps=100&peer=h1.example.net#h1",
			want: m("type", "hysteria", "tag", "h1", "server", "h1.example.net", "server_port", 443, "auth_str", "a1", "up_mbps", 50, "down_mbps", 100, "tls", tls("h1.example.net"))},
		{name: "insecure 与 alpn", in: "hysteria://h2.example.net:443?auth=a2&upmbps=10&downmbps=20&insecure=1&alpn=hysteria#h2",
			want: m("type", "hysteria", "tag", "h2", "server", "h2.example.net", "server_port", 443, "auth_str", "a2", "up_mbps", 10, "down_mbps", 20,
				"tls", tls("h2.example.net", "insecure", true, "alpn", list("hysteria")))},
		{name: "xplus 混淆", in: "hysteria://h3.example.net:443?auth=a3&upmbps=10&downmbps=20&obfs=xplus&obfsParam=op3#h3",
			want: m("type", "hysteria", "tag", "h3", "server", "h3.example.net", "server_port", 443, "auth_str", "a3", "up_mbps", 10, "down_mbps", 20, "obfs", "op3", "tls", tls("h3.example.net"))},
		{name: "端口跳跃", in: "hysteria://h4.example.net:443?auth=a4&upmbps=10&downmbps=20&mport=10000-20000#h4",
			want: m("type", "hysteria", "tag", "h4", "server", "h4.example.net", "server_port", 443, "auth_str", "a4", "up_mbps", 10, "down_mbps", 20,
				"server_ports", list("10000:20000"), "tls", tls("h4.example.net"))},
		{name: "protocol=udp 显式写出", in: "hysteria://h5.example.net:443?protocol=udp&auth=a5&upmbps=10&downmbps=20#h5",
			want: m("type", "hysteria", "tag", "h5", "server", "h5.example.net", "server_port", 443, "auth_str", "a5", "up_mbps", 10, "down_mbps", 20, "tls", tls("h5.example.net"))},
		{name: "sni 参数", in: "hysteria://h6.example.net:443?auth=a6&upmbps=10&downmbps=20&sni=front.example.net#h6",
			want: m("type", "hysteria", "tag", "h6", "server", "h6.example.net", "server_port", 443, "auth_str", "a6", "up_mbps", 10, "down_mbps", 20, "tls", tls("front.example.net"))},
		{name: "带单位的带宽", in: "hysteria://h7.example.net:443?auth=a7&upmbps=10%20mbps&downmbps=1%20gbps#h7",
			want: m("type", "hysteria", "tag", "h7", "server", "h7.example.net", "server_port", 443, "auth_str", "a7", "up_mbps", 10, "down_mbps", 1000, "tls", tls("h7.example.net"))},
		{name: "IPv6", in: "hysteria://[2001:db8::11]:443?auth=a8&upmbps=10&downmbps=20&peer=v6.example.net#v6",
			want: m("type", "hysteria", "tag", "v6", "server", "2001:db8::11", "server_port", 443, "auth_str", "a8", "up_mbps", 10, "down_mbps", 20, "tls", tls("v6.example.net"))},
		{name: "无 auth", in: "hysteria://h9.example.net:443?upmbps=10&downmbps=20#h9",
			want: m("type", "hysteria", "tag", "h9", "server", "h9.example.net", "server_port", 443, "up_mbps", 10, "down_mbps", 20, "tls", tls("h9.example.net"))},
		{name: "无名称", in: "hysteria://h10.example.net:8443?auth=a10&upmbps=10&downmbps=20",
			want: m("type", "hysteria", "tag", "h10.example.net:8443", "server", "h10.example.net", "server_port", 8443, "auth_str", "a10", "up_mbps", 10, "down_mbps", 20, "tls", tls("h10.example.net"))},

		{name: "faketcp 不支持", in: "hysteria://a.example.net:443?protocol=faketcp&upmbps=10&downmbps=20", err: "unsupported protocol"},
		{name: "wechat-video 不支持", in: "hysteria://a.example.net:443?protocol=wechat-video&upmbps=10&downmbps=20", err: "unsupported protocol"},
		{name: "缺上行带宽", in: "hysteria://a.example.net:443?downmbps=20", err: "missing upmbps"},
		{name: "缺下行带宽", in: "hysteria://a.example.net:443?upmbps=20", err: "missing downmbps"},
		{name: "未知混淆", in: "hysteria://a.example.net:443?upmbps=10&downmbps=20&obfs=other", err: "unsupported obfs"},
		{name: "xplus 缺参数", in: "hysteria://a.example.net:443?upmbps=10&downmbps=20&obfs=xplus", err: "needs obfsParam"},
		{name: "缺端口", in: "hysteria://a.example.net?upmbps=10&downmbps=20", err: "missing port"},
	}
	runCases(t, "hysteria", cases)
}
