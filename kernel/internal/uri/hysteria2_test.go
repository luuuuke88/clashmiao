package uri

import "testing"

func TestHysteria2(t *testing.T) {
	tls := func(sni string, extra ...any) map[string]any {
		return m(append([]any{"enabled", true, "server_name", sni}, extra...)...)
	}
	cases := []convCase{
		{name: "基本", in: "hysteria2://pw1@h.example.net:443?sni=h.example.net#h1",
			want: m("type", "hysteria2", "tag", "h1", "server", "h.example.net", "server_port", 443, "password", "pw1", "tls", tls("h.example.net"))},
		{name: "hy2 别名", in: "hy2://pw2@h2.example.net:443#h2",
			want: m("type", "hysteria2", "tag", "h2", "server", "h2.example.net", "server_port", 443, "password", "pw2", "tls", tls("h2.example.net"))},
		{name: "salamander 混淆", in: "hysteria2://pw3@h3.example.net:443?obfs=salamander&obfs-password=op3&sni=h3.example.net#h3",
			want: m("type", "hysteria2", "tag", "h3", "server", "h3.example.net", "server_port", 443, "password", "pw3",
				"obfs", m("type", "salamander", "password", "op3"), "tls", tls("h3.example.net"))},
		{name: "insecure 与 alpn", in: "hysteria2://pw4@h4.example.net:8443?insecure=1&alpn=h3&sni=front.example.net#h4",
			want: m("type", "hysteria2", "tag", "h4", "server", "h4.example.net", "server_port", 8443, "password", "pw4",
				"tls", tls("front.example.net", "insecure", true, "alpn", list("h3")))},
		{name: "端口跳跃 mport", in: "hysteria2://pw5@h5.example.net:443?mport=20000-30000&sni=h5.example.net#h5",
			want: m("type", "hysteria2", "tag", "h5", "server", "h5.example.net", "server_port", 443, "password", "pw5",
				"server_ports", list("20000:30000"), "tls", tls("h5.example.net"))},
		{name: "多段端口跳跃", in: "hysteria2://pw6@h6.example.net:443?mport=20000-30000,40000-50000,60000#h6",
			want: m("type", "hysteria2", "tag", "h6", "server", "h6.example.net", "server_port", 443, "password", "pw6",
				"server_ports", list("20000:30000", "40000:50000", "60000:60000"), "tls", tls("h6.example.net"))},
		{name: "只有 mport 没有端口", in: "hysteria2://pw7@h7.example.net?mport=30000-31000#h7",
			want: m("type", "hysteria2", "tag", "h7", "server", "h7.example.net", "server_port", 30000, "password", "pw7",
				"server_ports", list("30000:31000"), "tls", tls("h7.example.net"))},
		{name: "带宽", in: "hysteria2://pw8@h8.example.net:443?up=50%20mbps&down=1%20gbps#h8",
			want: m("type", "hysteria2", "tag", "h8", "server", "h8.example.net", "server_port", 443, "password", "pw8",
				"up_mbps", 50, "down_mbps", 1000, "tls", tls("h8.example.net"))},
		{name: "用户名:密码 整体作密码", in: "hysteria2://user:secret@h9.example.net:443#h9",
			want: m("type", "hysteria2", "tag", "h9", "server", "h9.example.net", "server_port", 443, "password", "user:secret", "tls", tls("h9.example.net"))},
		{name: "IPv6 服务器", in: "hysteria2://pw10@[2001:db8::10]:443?sni=v6.example.net#v6",
			want: m("type", "hysteria2", "tag", "v6", "server", "2001:db8::10", "server_port", 443, "password", "pw10", "tls", tls("v6.example.net"))},
		{name: "名称百分号编码", in: "hysteria2://pw11@n.example.net:443#%E6%97%A5%E6%9C%AC%2001",
			want: m("type", "hysteria2", "tag", "日本 01", "server", "n.example.net", "server_port", 443, "password", "pw11", "tls", tls("n.example.net"))},

		{name: "pinSHA256 不支持", in: "hysteria2://pw@a.example.net:443?pinSHA256=AB:CD:EF", err: "pinSHA256 pinning is not supported"},
		{name: "未知混淆", in: "hysteria2://pw@a.example.net:443?obfs=xplus", err: "unsupported obfs"},
		{name: "salamander 缺密码", in: "hysteria2://pw@a.example.net:443?obfs=salamander", err: "needs obfs-password"},
		{name: "缺密码", in: "hysteria2://@a.example.net:443", err: "missing password"},
		{name: "缺端口", in: "hysteria2://pw@a.example.net", err: "missing port"},
		{name: "端口跳跃区间反了", in: "hysteria2://pw@a.example.net:443?mport=30000-20000", err: "bad port range"},
		{name: "带宽非法", in: "hysteria2://pw@a.example.net:443?up=fast", err: "bad up"},
	}
	runCases(t, "hysteria2", cases)
}
