package uri

import (
	"strconv"
	"strings"
)

// transportSpec 是各协议里描述 V2Ray 传输层的字段（不同协议的参数名不同，由调用方收齐）。
type transportSpec struct {
	Network     string // tcp / ws / grpc / httpupgrade / h2 / http
	HeaderType  string // tcp 的伪装头：none / http
	Host        string
	Path        string
	ServiceName string // grpc
}

// transportFor 生成 sing-box 的 transport 块；tcp 且无伪装返回 nil。
// 不支持的网络类型（kcp / quic / xhttp / splithttp 等）报 uri-invalid，不静默降级成 tcp。
func transportFor(scheme string, s transportSpec) (map[string]any, error) {
	switch strings.ToLower(s.Network) {
	case "", "tcp", "raw":
		if strings.ToLower(s.HeaderType) == "http" {
			t := map[string]any{"type": "http", "path": orDefault(s.Path, "/"), "method": "GET"}
			if hosts := splitList(s.Host); len(hosts) > 0 {
				t["host"] = toAnyList(hosts)
			}
			return t, nil
		}
		if h := strings.ToLower(s.HeaderType); h != "" && h != "none" {
			return nil, invalidf(scheme, "unsupported tcp header type %q", s.HeaderType)
		}
		return nil, nil
	case "ws", "websocket":
		path, early := splitEarlyData(orDefault(s.Path, "/"))
		t := map[string]any{"type": "ws", "path": path}
		if s.Host != "" {
			t["headers"] = map[string]any{"Host": s.Host}
		}
		if early > 0 {
			t["max_early_data"] = early
			t["early_data_header_name"] = "Sec-WebSocket-Protocol"
		}
		return t, nil
	case "grpc":
		t := map[string]any{"type": "grpc"}
		if s.ServiceName != "" {
			t["service_name"] = s.ServiceName
		}
		return t, nil
	case "httpupgrade":
		t := map[string]any{"type": "httpupgrade", "path": orDefault(s.Path, "/")}
		if s.Host != "" {
			t["host"] = s.Host
		}
		return t, nil
	case "h2", "http":
		t := map[string]any{"type": "http", "path": orDefault(s.Path, "/")}
		if hosts := splitList(s.Host); len(hosts) > 0 {
			t["host"] = toAnyList(hosts)
		}
		return t, nil
	}
	return nil, invalidf(scheme, "unsupported transport %q", s.Network)
}

func orDefault(s, def string) string {
	if s == "" {
		return def
	}
	return s
}

// splitEarlyData 把路径里的 ?ed=N（V2Ray 约定的 WebSocket early data）拆出来，
// sing-box 用 max_early_data 与 early_data_header_name 表达。
func splitEarlyData(path string) (string, int) {
	i := strings.Index(path, "?")
	if i < 0 {
		return path, 0
	}
	base, q := path[:i], parseParams(path[i+1:])
	n, err := strconv.Atoi(q.get("ed"))
	if err != nil || n <= 0 {
		return path, 0
	}
	// 去掉 ed 参数，其余查询参数保留。
	var rest []string
	for _, kv := range strings.Split(path[i+1:], "&") {
		if k, _, _ := strings.Cut(kv, "="); !strings.EqualFold(k, "ed") && kv != "" {
			rest = append(rest, kv)
		}
	}
	if len(rest) > 0 {
		base += "?" + strings.Join(rest, "&")
	}
	return base, n
}
