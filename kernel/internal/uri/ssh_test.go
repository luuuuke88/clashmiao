package uri

import "testing"

// 私钥与主机密钥这几行用的是占位字符串（不放真的密钥进仓库）：只验证转换，不进样例文件；
// 真密钥在 gate 包的 TestSSHKeyLinksPassCheckConfig 里运行时生成。
func TestSSH(t *testing.T) {
	cases := []convCase{
		{name: "密码登录", in: "ssh://user:pass@h1.example.net:22#h1",
			want: m("type", "ssh", "tag", "h1", "server", "h1.example.net", "server_port", 22, "user", "user", "password", "pass")},
		{name: "端口缺省 22，用户缺省 root", in: "ssh://:pass@h2.example.net#h2",
			want: m("type", "ssh", "tag", "h2", "server", "h2.example.net", "server_port", 22, "user", "root", "password", "pass")},
		{name: "私钥登录", noSample: true, in: "ssh://user@h3.example.net:2222?private_key=-----BEGIN%20KEY-----%0Aabc%0A-----END%20KEY-----#h3",
			want: m("type", "ssh", "tag", "h3", "server", "h3.example.net", "server_port", 2222, "user", "user", "private_key", "-----BEGIN KEY-----\nabc\n-----END KEY-----")},
		{name: "私钥口令", noSample: true, in: "ssh://user@h4.example.net:22?private_key=k4&private_key_passphrase=pp#h4",
			want: m("type", "ssh", "tag", "h4", "server", "h4.example.net", "server_port", 22, "user", "user", "private_key", "k4", "private_key_passphrase", "pp")},
		{name: "主机密钥", noSample: true, in: "ssh://user:pass@h5.example.net:22?host_key=ssh-ed25519%20AAAA,ssh-rsa%20BBBB#h5",
			want: m("type", "ssh", "tag", "h5", "server", "h5.example.net", "server_port", 22, "user", "user", "password", "pass", "host_key", list("ssh-ed25519 AAAA", "ssh-rsa BBBB"))},
		{name: "客户端版本", in: "ssh://user:pass@h6.example.net:22?client_version=SSH-2.0-test#h6",
			want: m("type", "ssh", "tag", "h6", "server", "h6.example.net", "server_port", 22, "user", "user", "password", "pass", "client_version", "SSH-2.0-test")},
		{name: "密码百分号编码", in: "ssh://u:p%40ss@h7.example.net:22#h7",
			want: m("type", "ssh", "tag", "h7", "server", "h7.example.net", "server_port", 22, "user", "u", "password", "p@ss")},
		{name: "IPv6", in: "ssh://u:p@[2001:db8::16]:22#v6",
			want: m("type", "ssh", "tag", "v6", "server", "2001:db8::16", "server_port", 22, "user", "u", "password", "p")},
		{name: "无名称用 host:port", in: "ssh://u:p@h9.example.net",
			want: m("type", "ssh", "tag", "h9.example.net:22", "server", "h9.example.net", "server_port", 22, "user", "u", "password", "p")},
		{name: "名称百分号编码", in: "ssh://u:p@h10.example.net:22#%E8%B7%B3%E6%9D%BF",
			want: m("type", "ssh", "tag", "跳板", "server", "h10.example.net", "server_port", 22, "user", "u", "password", "p")},

		{name: "自定义端口", in: "ssh://root:pw@h11.example.net:2200#h11",
			want: m("type", "ssh", "tag", "h11", "server", "h11.example.net", "server_port", 2200, "user", "root", "password", "pw")},
		{name: "用户名含点", in: "ssh://deploy.user:pw@h12.example.net:22#h12",
			want: m("type", "ssh", "tag", "h12", "server", "h12.example.net", "server_port", 22, "user", "deploy.user", "password", "pw")},
		{name: "密码里有冒号", in: "ssh://u:p%3Aw@h13.example.net:22#h13",
			want: m("type", "ssh", "tag", "h13", "server", "h13.example.net", "server_port", 22, "user", "u", "password", "p:w")},
		{name: "客户端版本与密码", in: "ssh://u:p@h14.example.net:22?client_version=SSH-2.0-OpenSSH_9.0#h14",
			want: m("type", "ssh", "tag", "h14", "server", "h14.example.net", "server_port", 22, "user", "u", "password", "p", "client_version", "SSH-2.0-OpenSSH_9.0")},

		{name: "没有密码也没有私钥", in: "ssh://user@a.example.net:22", err: "needs a password or a private key"},
		{name: "缺主机", in: "ssh://u:p@:22", err: "missing host"},
		{name: "端口非法", in: "ssh://u:p@a.example.net:99999", err: "bad port"},
	}
	runCases(t, "ssh", cases)
}
