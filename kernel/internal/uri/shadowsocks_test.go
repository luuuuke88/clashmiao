package uri

import "testing"

func TestShadowsocks(t *testing.T) {
	sip002 := func(method, pw, hostPort, rest string) string {
		return "ss://" + b64u(method+":"+pw) + "@" + hostPort + rest
	}
	cases := []convCase{
		{name: "SIP002 base64url userinfo", in: sip002("aes-128-gcm", "pw1", "s1.example.net:8388", "#s1"),
			want: m("type", "shadowsocks", "tag", "s1", "server", "s1.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "pw1")},
		{name: "SIP002 末尾带 /", in: sip002("chacha20-ietf-poly1305", "pw2", "s2.example.net:8388", "/#s2"),
			want: m("type", "shadowsocks", "tag", "s2", "server", "s2.example.net", "server_port", 8388, "method", "chacha20-ietf-poly1305", "password", "pw2")},
		{name: "SIP002 标准 base64 userinfo（带 padding 与 + /）", in: "ss://" + b64("aes-256-gcm:p?w/+1") + "@s3.example.net:8388#s3",
			want: m("type", "shadowsocks", "tag", "s3", "server", "s3.example.net", "server_port", 8388, "method", "aes-256-gcm", "password", "p?w/+1")},
		{name: "明文 userinfo（2022 系列，密码百分号编码）", in: "ss://2022-blake3-aes-128-gcm:Zm9vYmFyMTIzNDU2Nzg5MA%3D%3D@s4.example.net:8388#s4",
			want: m("type", "shadowsocks", "tag", "s4", "server", "s4.example.net", "server_port", 8388, "method", "2022-blake3-aes-128-gcm", "password", "Zm9vYmFyMTIzNDU2Nzg5MA==")},
		{name: "旧式整体 base64", in: "ss://" + b64("aes-128-gcm:pw5@s5.example.net:8388") + "#s5",
			want: m("type", "shadowsocks", "tag", "s5", "server", "s5.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "pw5")},
		{name: "旧式整体 base64（无 padding、无名称）", in: "ss://" + b64u("aes-128-gcm:pw6@192.0.2.6:9000"),
			want: m("type", "shadowsocks", "tag", "192.0.2.6:9000", "server", "192.0.2.6", "server_port", 9000, "method", "aes-128-gcm", "password", "pw6")},
		{name: "IPv6 地址", in: sip002("aes-128-gcm", "pw7", "[2001:db8::5]:8388", "#v6"),
			want: m("type", "shadowsocks", "tag", "v6", "server", "2001:db8::5", "server_port", 8388, "method", "aes-128-gcm", "password", "pw7")},
		{name: "旧式 base64 里的 IPv6", in: "ss://" + b64("aes-128-gcm:pw8@[2001:db8::6]:8388") + "#v6b",
			want: m("type", "shadowsocks", "tag", "v6b", "server", "2001:db8::6", "server_port", 8388, "method", "aes-128-gcm", "password", "pw8")},
		{name: "obfs-local 插件", in: sip002("aes-128-gcm", "pw9", "o.example.net:8388", "/?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dcdn.example.com#obfs"),
			want: m("type", "shadowsocks", "tag", "obfs", "server", "o.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "pw9",
				"plugin", "obfs-local", "plugin_opts", "obfs=http;obfs-host=cdn.example.com")},
		{name: "simple-obfs 别名归一为 obfs-local", in: sip002("aes-128-gcm", "pw10", "o2.example.net:8388", "/?plugin=simple-obfs%3Bobfs%3Dtls#obfs2"),
			want: m("type", "shadowsocks", "tag", "obfs2", "server", "o2.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "pw10",
				"plugin", "obfs-local", "plugin_opts", "obfs=tls")},
		{name: "v2ray-plugin", in: sip002("aes-128-gcm", "pw11", "v.example.net:443", "/?plugin=v2ray-plugin%3Btls%3Bhost%3Dv.example.net%3Bpath%3D%2Fws#v2"),
			want: m("type", "shadowsocks", "tag", "v2", "server", "v.example.net", "server_port", 443, "method", "aes-128-gcm", "password", "pw11",
				"plugin", "v2ray-plugin", "plugin_opts", "tls;host=v.example.net;path=/ws")},
		{name: "名称百分号编码", in: sip002("aes-128-gcm", "pw12", "n.example.net:8388", "#%E9%A6%99%E6%B8%AF%2001"),
			want: m("type", "shadowsocks", "tag", "香港 01", "server", "n.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "pw12")},
		{name: "密码含冒号（base64 里）", in: sip002("aes-128-gcm", "a:b:c", "c.example.net:8388", "#colon"),
			want: m("type", "shadowsocks", "tag", "colon", "server", "c.example.net", "server_port", 8388, "method", "aes-128-gcm", "password", "a:b:c")},

		{name: "不是 base64 的 userinfo", in: "ss://!!!@a.example.net:8388", err: "userinfo is not base64"},
		{name: "userinfo 缺冒号", in: "ss://" + b64u("onlymethod") + "@a.example.net:8388", err: "not method:password"},
		{name: "缺端口", in: "ss://" + b64u("aes-128-gcm:pw") + "@a.example.net", err: "bad host:port"},
		{name: "端口非法", in: "ss://" + b64u("aes-128-gcm:pw") + "@a.example.net:70000", err: "bad host or port"},
		{name: "整体 base64 里没有 @", in: "ss://" + b64("aes-128-gcm:pw"), err: "no @"},
		{name: "整体不是 base64", in: "ss://this is not base64!", err: "neither SIP002 nor base64"},
		{name: "不支持的插件", in: sip002("aes-128-gcm", "pw", "a.example.net:8388", "/?plugin=kcptun%3Bkey%3D1"), err: `unsupported plugin "kcptun"`},
	}
	runCases(t, "shadowsocks", cases)
}
