package uri

func init() { Register("ssh", convertSSH) }

// convertSSH：ssh://user:password@host[:port]?private_key=…&private_key_passphrase=…&host_key=a,b&client_version=…#name
// 端口缺省 22，用户缺省 root；必须有密码或私钥之一。
func convertSSH(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if l.host == "" {
		return Entity{}, invalidf("ssh", "missing host")
	}
	port := l.port
	if port == 0 {
		port = 22
	}
	out := base("ssh", l.tagFor(port), l.host, port)
	out["user"] = orDefault(l.user, "root")
	if l.password != "" {
		out["password"] = l.password
	}
	if key := l.query.get("private_key", "privatekey"); key != "" {
		out["private_key"] = key
	}
	if v := l.query.get("private_key_passphrase", "passphrase"); v != "" {
		out["private_key_passphrase"] = v
	}
	if hk := splitList(l.query.get("host_key", "hostkey")); len(hk) > 0 {
		out["host_key"] = toAnyList(hk)
	}
	if v := l.query.get("client_version"); v != "" {
		out["client_version"] = v
	}
	if out["password"] == nil && out["private_key"] == nil {
		return Entity{}, invalidf("ssh", "needs a password or a private key")
	}
	return Entity{Map: out}, nil
}
