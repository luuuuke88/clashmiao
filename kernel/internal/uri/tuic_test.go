package uri

import "testing"

func TestTUIC(t *testing.T) {
	tls := func(sni string, extra ...any) map[string]any {
		return m(append([]any{"enabled", true, "server_name", sni}, extra...)...)
	}
	cases := []convCase{
		{name: "基本", in: "tuic://" + testUUID + ":pw1@t1.example.net:443?sni=t1.example.net#t1",
			want: m("type", "tuic", "tag", "t1", "server", "t1.example.net", "server_port", 443, "uuid", testUUID, "password", "pw1", "tls", tls("t1.example.net"))},
		{name: "拥塞控制与 udp 中继模式", in: "tuic://" + testUUID + ":pw2@t2.example.net:443?congestion_control=bbr&udp_relay_mode=native&sni=t2.example.net#t2",
			want: m("type", "tuic", "tag", "t2", "server", "t2.example.net", "server_port", 443, "uuid", testUUID, "password", "pw2",
				"congestion_control", "bbr", "udp_relay_mode", "native", "tls", tls("t2.example.net"))},
		{name: "alpn 与 allow_insecure", in: "tuic://" + testUUID + ":pw3@t3.example.net:443?alpn=h3&allow_insecure=1#t3",
			want: m("type", "tuic", "tag", "t3", "server", "t3.example.net", "server_port", 443, "uuid", testUUID, "password", "pw3",
				"tls", tls("t3.example.net", "alpn", list("h3"), "insecure", true))},
		{name: "disable_sni", in: "tuic://" + testUUID + ":pw4@t4.example.net:443?disable_sni=1#t4",
			want: m("type", "tuic", "tag", "t4", "server", "t4.example.net", "server_port", 443, "uuid", testUUID, "password", "pw4",
				"tls", tls("t4.example.net", "disable_sni", true))},
		{name: "连字符写法的参数", in: "tuic://" + testUUID + ":pw5@t5.example.net:443?congestion-control=cubic&udp-relay-mode=quic#t5",
			want: m("type", "tuic", "tag", "t5", "server", "t5.example.net", "server_port", 443, "uuid", testUUID, "password", "pw5",
				"congestion_control", "cubic", "udp_relay_mode", "quic", "tls", tls("t5.example.net"))},
		{name: "udp_over_stream 与 reduce_rtt", in: "tuic://" + testUUID + ":pw6@t6.example.net:443?udp_over_stream=1&reduce_rtt=1#t6",
			want: m("type", "tuic", "tag", "t6", "server", "t6.example.net", "server_port", 443, "uuid", testUUID, "password", "pw6",
				"udp_over_stream", true, "zero_rtt_handshake", true, "tls", tls("t6.example.net"))},
		{name: "密码百分号编码", in: "tuic://" + testUUID + ":p%40ss@t7.example.net:443#t7",
			want: m("type", "tuic", "tag", "t7", "server", "t7.example.net", "server_port", 443, "uuid", testUUID, "password", "p@ss", "tls", tls("t7.example.net"))},
		{name: "IPv6", in: "tuic://" + testUUID + ":pw8@[2001:db8::12]:443?sni=v6.example.net#v6",
			want: m("type", "tuic", "tag", "v6", "server", "2001:db8::12", "server_port", 443, "uuid", testUUID, "password", "pw8", "tls", tls("v6.example.net"))},
		{name: "无名称", in: "tuic://" + testUUID + ":pw9@t9.example.net:4443",
			want: m("type", "tuic", "tag", "t9.example.net:4443", "server", "t9.example.net", "server_port", 4443, "uuid", testUUID, "password", "pw9", "tls", tls("t9.example.net"))},
		{name: "名称百分号编码", in: "tuic://" + testUUID + ":pw10@t10.example.net:443#%E5%8F%B0%E6%B9%BE",
			want: m("type", "tuic", "tag", "台湾", "server", "t10.example.net", "server_port", 443, "uuid", testUUID, "password", "pw10", "tls", tls("t10.example.net"))},

		{name: "缺 uuid", in: "tuic://:pw@a.example.net:443", err: "missing uuid"},
		{name: "缺密码（v4 token 不支持）", in: "tuic://" + testUUID + "@a.example.net:443", err: "missing password"},
		{name: "缺端口", in: "tuic://" + testUUID + ":pw@a.example.net", err: "missing port"},
		{name: "端口非法", in: "tuic://" + testUUID + ":pw@a.example.net:0", err: "bad port"},
	}
	runCases(t, "tuic", cases)
}
