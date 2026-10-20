package uri

import "testing"

func TestAnyTLS(t *testing.T) {
	tls := func(sni string, extra ...any) map[string]any {
		return m(append([]any{"enabled", true, "server_name", sni}, extra...)...)
	}
	cases := []convCase{
		{name: "基本", in: "anytls://pw1@a1.example.net:443?sni=a1.example.net#a1",
			want: m("type", "anytls", "tag", "a1", "server", "a1.example.net", "server_port", 443, "password", "pw1", "tls", tls("a1.example.net"))},
		{name: "默认 sni 取服务器", in: "anytls://pw2@a2.example.net:443#a2",
			want: m("type", "anytls", "tag", "a2", "server", "a2.example.net", "server_port", 443, "password", "pw2", "tls", tls("a2.example.net"))},
		{name: "insecure", in: "anytls://pw3@a3.example.net:443?insecure=1#a3",
			want: m("type", "anytls", "tag", "a3", "server", "a3.example.net", "server_port", 443, "password", "pw3", "tls", tls("a3.example.net", "insecure", true))},
		{name: "alpn 与指纹", in: "anytls://pw4@a4.example.net:443?alpn=h2&fp=chrome#a4",
			want: m("type", "anytls", "tag", "a4", "server", "a4.example.net", "server_port", 443, "password", "pw4",
				"tls", tls("a4.example.net", "alpn", list("h2"), "utls", m("enabled", true, "fingerprint", "chrome")))},
		{name: "密码百分号编码", in: "anytls://p%3Aw%40@a5.example.net:443#a5",
			want: m("type", "anytls", "tag", "a5", "server", "a5.example.net", "server_port", 443, "password", "p:w@", "tls", tls("a5.example.net"))},
		{name: "用户名:密码整体作密码", in: "anytls://u:p@a6.example.net:443#a6",
			want: m("type", "anytls", "tag", "a6", "server", "a6.example.net", "server_port", 443, "password", "u:p", "tls", tls("a6.example.net"))},
		{name: "IPv6", in: "anytls://pw7@[2001:db8::13]:443?sni=v6.example.net#v6",
			want: m("type", "anytls", "tag", "v6", "server", "2001:db8::13", "server_port", 443, "password", "pw7", "tls", tls("v6.example.net"))},
		{name: "无名称", in: "anytls://pw8@a8.example.net:8443",
			want: m("type", "anytls", "tag", "a8.example.net:8443", "server", "a8.example.net", "server_port", 8443, "password", "pw8", "tls", tls("a8.example.net"))},
		{name: "名称百分号编码", in: "anytls://pw9@a9.example.net:443#%E6%96%B0%E5%8A%A0%E5%9D%A1",
			want: m("type", "anytls", "tag", "新加坡", "server", "a9.example.net", "server_port", 443, "password", "pw9", "tls", tls("a9.example.net"))},
		{name: "peer 作 sni", in: "anytls://pw10@a10.example.net:443?peer=p.example.net#a10",
			want: m("type", "anytls", "tag", "a10", "server", "a10.example.net", "server_port", 443, "password", "pw10", "tls", tls("p.example.net"))},

		{name: "缺密码", in: "anytls://@a.example.net:443", err: "missing password"},
		{name: "缺端口", in: "anytls://pw@a.example.net", err: "missing port"},
		{name: "缺主机", in: "anytls://pw@:443", err: "missing host"},
	}
	runCases(t, "anytls", cases)
}
