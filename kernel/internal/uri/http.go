package uri

func init() {
	Register("http", convertHTTPProxy)
	Register("https", convertHTTPProxy)
}

// convertHTTPProxy 把 http(s)://[user:pass@]host:port#name 当作代理出站。
//
// 只收「显式代理 URI」：必须带端口，且没有路径与查询——订阅列表里夹带的普通网址（订阅链接本身、说明页）
// 带路径或查询，一律拒绝，不能把它们当节点。
func convertHTTPProxy(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	if (l.path != "" && l.path != "/") || l.rawQuery != "" {
		return Entity{}, invalidf(l.scheme, "looks like a web URL, not a proxy (a proxy URI has no path or query)")
	}
	out := base("http", l.tag(), l.host, l.port)
	if l.user != "" {
		out["username"] = l.user
	}
	if l.password != "" {
		out["password"] = l.password
	}
	if l.scheme == "https" {
		out["tls"] = map[string]any{"enabled": true, "server_name": l.host}
	}
	return Entity{Map: out}, nil
}
