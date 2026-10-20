package uri

import "testing"

func TestSocks(t *testing.T) {
	cases := []convCase{
		{name: "socks5 带账号", in: "socks5://user:pass@s1.example.net:1080#s1",
			want: m("type", "socks", "tag", "s1", "server", "s1.example.net", "server_port", 1080, "version", "5", "username", "user", "password", "pass")},
		{name: "socks5 无账号", in: "socks5://s2.example.net:1080#s2",
			want: m("type", "socks", "tag", "s2", "server", "s2.example.net", "server_port", 1080, "version", "5")},
		{name: "socks:// base64 用户信息", in: "socks://" + b64u("user3:pass3") + "@s3.example.net:1080#s3",
			want: m("type", "socks", "tag", "s3", "server", "s3.example.net", "server_port", 1080, "version", "5", "username", "user3", "password", "pass3")},
		{name: "socks:// 明文账号", in: "socks://user4:pass4@s4.example.net:1080#s4",
			want: m("type", "socks", "tag", "s4", "server", "s4.example.net", "server_port", 1080, "version", "5", "username", "user4", "password", "pass4")},
		{name: "socks5h", in: "socks5h://s5.example.net:1080#s5",
			want: m("type", "socks", "tag", "s5", "server", "s5.example.net", "server_port", 1080, "version", "5")},
		{name: "socks4", in: "socks4://s6.example.net:1080#s6",
			want: m("type", "socks", "tag", "s6", "server", "s6.example.net", "server_port", 1080, "version", "4")},
		{name: "socks4a", in: "socks4a://s7.example.net:1080#s7",
			want: m("type", "socks", "tag", "s7", "server", "s7.example.net", "server_port", 1080, "version", "4a")},
		{name: "只有用户名", in: "socks5://onlyuser@s8.example.net:1080#s8",
			want: m("type", "socks", "tag", "s8", "server", "s8.example.net", "server_port", 1080, "version", "5", "username", "onlyuser")},
		{name: "密码百分号编码", in: "socks5://u:p%40ss@s9.example.net:1080#s9",
			want: m("type", "socks", "tag", "s9", "server", "s9.example.net", "server_port", 1080, "version", "5", "username", "u", "password", "p@ss")},
		{name: "IPv6", in: "socks5://[2001:db8::14]:1080#v6",
			want: m("type", "socks", "tag", "v6", "server", "2001:db8::14", "server_port", 1080, "version", "5")},
		{name: "无名称", in: "socks5://192.0.2.15:1080",
			want: m("type", "socks", "tag", "192.0.2.15:1080", "server", "192.0.2.15", "server_port", 1080, "version", "5")},
		{name: "不是 base64 的纯用户名（socks://）", in: "socks://name!@s12.example.net:1080#s12",
			want: m("type", "socks", "tag", "s12", "server", "s12.example.net", "server_port", 1080, "version", "5", "username", "name!")},

		{name: "缺端口", in: "socks5://a.example.net", err: "missing port"},
		{name: "缺主机", in: "socks5://:1080", err: "missing host"},
	}
	runCases(t, "socks", cases)
}
