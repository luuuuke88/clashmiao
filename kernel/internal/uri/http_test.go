package uri

import "testing"

func TestHTTPProxy(t *testing.T) {
	cases := []convCase{
		{name: "http 代理带账号", in: "http://user:pass@p1.example.net:8080#p1",
			want: m("type", "http", "tag", "p1", "server", "p1.example.net", "server_port", 8080, "username", "user", "password", "pass")},
		{name: "http 代理无账号", in: "http://p2.example.net:3128#p2",
			want: m("type", "http", "tag", "p2", "server", "p2.example.net", "server_port", 3128)},
		{name: "https 代理启用 tls", in: "https://user:pass@p3.example.net:443#p3",
			want: m("type", "http", "tag", "p3", "server", "p3.example.net", "server_port", 443, "username", "user", "password", "pass",
				"tls", m("enabled", true, "server_name", "p3.example.net"))},
		{name: "路径只有 /", in: "http://p4.example.net:8080/#p4",
			want: m("type", "http", "tag", "p4", "server", "p4.example.net", "server_port", 8080)},
		{name: "密码百分号编码", in: "http://u:p%40ss@p5.example.net:8080#p5",
			want: m("type", "http", "tag", "p5", "server", "p5.example.net", "server_port", 8080, "username", "u", "password", "p@ss")},
		{name: "IPv6", in: "http://[2001:db8::15]:8080#v6",
			want: m("type", "http", "tag", "v6", "server", "2001:db8::15", "server_port", 8080)},
		{name: "无名称", in: "http://192.0.2.16:8080",
			want: m("type", "http", "tag", "192.0.2.16:8080", "server", "192.0.2.16", "server_port", 8080)},
		{name: "只有用户名", in: "http://onlyuser@p8.example.net:8080#p8",
			want: m("type", "http", "tag", "p8", "server", "p8.example.net", "server_port", 8080, "username", "onlyuser")},
		{name: "名称百分号编码", in: "http://p9.example.net:8080#%E5%85%AC%E5%8F%B8",
			want: m("type", "http", "tag", "公司", "server", "p9.example.net", "server_port", 8080)},
		{name: "https 无账号", in: "https://p10.example.net:8443#p10",
			want: m("type", "http", "tag", "p10", "server", "p10.example.net", "server_port", 8443, "tls", m("enabled", true, "server_name", "p10.example.net"))},

		{name: "订阅链接本身（带路径与查询）不当节点", in: "https://sub.example.net:443/api/v1/client/subscribe?token=abc", err: "looks like a web URL"},
		{name: "带路径的网址不当节点", in: "http://example.net:80/docs/readme.html", err: "looks like a web URL"},
		{name: "只有查询的网址不当节点", in: "http://example.net:80?x=1", err: "looks like a web URL"},
		{name: "没写端口不当节点", in: "https://example.net", err: "missing port"},
	}
	runCases(t, "http", cases)
}
