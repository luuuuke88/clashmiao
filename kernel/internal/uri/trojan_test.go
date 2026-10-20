package uri

import "testing"

func TestTrojan(t *testing.T) {
	cases := []convCase{
		{name: "默认启用 tls", in: "trojan://pw1@t.example.net:443#t1",
			want: m("type", "trojan", "tag", "t1", "server", "t.example.net", "server_port", 443, "password", "pw1",
				"tls", m("enabled", true, "server_name", "t.example.net"))},
		{name: "sni 与 alpn 与指纹", in: "trojan://pw2@t2.example.net:443?security=tls&sni=front.example.net&alpn=h2%2Chttp%2F1.1&fp=chrome#t2",
			want: m("type", "trojan", "tag", "t2", "server", "t2.example.net", "server_port", 443, "password", "pw2",
				"tls", m("enabled", true, "server_name", "front.example.net", "alpn", list("h2", "http/1.1"), "utls", m("enabled", true, "fingerprint", "chrome")))},
		{name: "ws", in: "trojan://pw3@w.example.net:443?type=ws&host=cdn.example.net&path=%2Ftrojan#ws",
			want: m("type", "trojan", "tag", "ws", "server", "w.example.net", "server_port", 443, "password", "pw3",
				"tls", m("enabled", true, "server_name", "cdn.example.net"),
				"transport", m("type", "ws", "path", "/trojan", "headers", m("Host", "cdn.example.net")))},
		{name: "grpc", in: "trojan://pw4@g.example.net:443?type=grpc&serviceName=tsvc&sni=g.example.net#grpc",
			want: m("type", "trojan", "tag", "grpc", "server", "g.example.net", "server_port", 443, "password", "pw4",
				"tls", m("enabled", true, "server_name", "g.example.net"), "transport", m("type", "grpc", "service_name", "tsvc"))},
		{name: "明文（security=none）", in: "trojan://pw5@192.0.2.8:8080?security=none#plain",
			want: m("type", "trojan", "tag", "plain", "server", "192.0.2.8", "server_port", 8080, "password", "pw5")},
		{name: "allowInsecure", in: "trojan://pw6@i.example.net:443?allowInsecure=1#ins",
			want: m("type", "trojan", "tag", "ins", "server", "i.example.net", "server_port", 443, "password", "pw6",
				"tls", m("enabled", true, "server_name", "i.example.net", "insecure", true))},
		{name: "密码百分号编码", in: "trojan://p%40ss%3Aword@e.example.net:443#enc",
			want: m("type", "trojan", "tag", "enc", "server", "e.example.net", "server_port", 443, "password", "p@ss:word",
				"tls", m("enabled", true, "server_name", "e.example.net"))},
		{name: "IPv6", in: "trojan://pw7@[2001:db8::3]:443?sni=v6.example.net#v6",
			want: m("type", "trojan", "tag", "v6", "server", "2001:db8::3", "server_port", 443, "password", "pw7",
				"tls", m("enabled", true, "server_name", "v6.example.net"))},
		{name: "无名称用 host:port", in: "trojan://pw8@n.example.net:8443",
			want: m("type", "trojan", "tag", "n.example.net:8443", "server", "n.example.net", "server_port", 8443, "password", "pw8",
				"tls", m("enabled", true, "server_name", "n.example.net"))},
		{name: "reality（trojan 上不常见但合法）", in: "trojan://pw9@r.example.net:443?security=reality&pbk=" + testPK + "&sid=ab#r",
			want: m("type", "trojan", "tag", "r", "server", "r.example.net", "server_port", 443, "password", "pw9",
				"tls", m("enabled", true, "server_name", "r.example.net", "utls", m("enabled", true, "fingerprint", "chrome"),
					"reality", m("enabled", true, "public_key", testPK, "short_id", "ab")))},
		{name: "httpupgrade", in: "trojan://pw10@h.example.net:443?type=httpupgrade&host=h.example.net&path=%2Fu#hu",
			want: m("type", "trojan", "tag", "hu", "server", "h.example.net", "server_port", 443, "password", "pw10",
				"tls", m("enabled", true, "server_name", "h.example.net"), "transport", m("type", "httpupgrade", "path", "/u", "host", "h.example.net"))},

		{name: "缺密码", in: "trojan://@a.example.net:443", err: "missing password"},
		{name: "缺端口", in: "trojan://pw@a.example.net", err: "missing port"},
		{name: "xtls 不支持", in: "trojan://pw@a.example.net:443?security=xtls", err: `unsupported security "xtls"`},
		{name: "kcp 传输不支持", in: "trojan://pw@a.example.net:443?type=kcp", err: `unsupported transport "kcp"`},
		{name: "reality 缺公钥", in: "trojan://pw@a.example.net:443?security=reality", err: "reality needs pbk"},
	}
	runCases(t, "trojan", cases)
}
