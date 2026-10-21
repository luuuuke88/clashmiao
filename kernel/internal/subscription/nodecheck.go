package subscription

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

// validateNode 检查 sing-box JSON 里一个出站 / 端点对象的基本字段、类型与值域；未知但合法的字段原样保留。
// 返回非空串表示该节点应被跳过（原因）。订阅自带的分组 / 直连类（会被清洗丢弃）不检查。
//
// 只卡「缺了就一定启动失败」的东西：type 与 tag 的类型、server / server_port 的有无与范围、
// 各协议的凭据字段。字段值的深层语义（加密方法名、传输层选项）留给内核的 CheckConfig。
func validateNode(m map[string]any, endpoint bool) string {
	typ, ok := m["type"].(string)
	if !ok || strings.TrimSpace(typ) == "" {
		return "missing or invalid type"
	}
	if t, present := m["tag"]; present {
		if _, ok := t.(string); !ok {
			return "tag is not a string"
		}
	}
	if !endpoint && isGroupOrDirectType(typ) {
		return ""
	}
	if endpoint {
		return validateEndpoint(typ, m)
	}
	switch strings.ToLower(typ) {
	case "tor", "wireguard", "custom":
		// wireguard 出站由清洗转端点（字段形态更宽松），tor 没有 server。
		return ""
	}
	if reason := checkServer(typ, m); reason != "" {
		return reason
	}
	need := func(keys ...string) string {
		for _, k := range keys {
			if s, ok := m[k].(string); !ok || s == "" {
				return fmt.Sprintf("%s requires %s", typ, k)
			}
		}
		return ""
	}
	switch strings.ToLower(typ) {
	case "shadowsocks":
		return need("method", "password")
	case "vmess", "vless", "tuic":
		return need("uuid")
	case "trojan", "hysteria2", "anytls":
		return need("password")
	}
	return ""
}

func validateEndpoint(typ string, m map[string]any) string {
	if strings.ToLower(typ) != "wireguard" {
		return ""
	}
	if s, ok := m["private_key"].(string); !ok || s == "" {
		return "wireguard endpoint requires private_key"
	}
	peers, ok := m["peers"].([]any)
	if !ok || len(peers) == 0 {
		return "wireguard endpoint requires peers"
	}
	for i, p := range peers {
		pm, ok := p.(map[string]any)
		if !ok {
			return fmt.Sprintf("peers[%d] is not an object", i)
		}
		if a, ok := pm["address"].(string); !ok || a == "" {
			return fmt.Sprintf("peers[%d] requires address", i)
		}
		if pk, ok := pm["public_key"].(string); !ok || pk == "" {
			return fmt.Sprintf("peers[%d] requires public_key", i)
		}
		if port, present := pm["port"]; present && !validPort(port) {
			return fmt.Sprintf("peers[%d].port is out of range", i)
		}
	}
	return ""
}

// supportsServerPorts：sing-box 1.14 里只有 hysteria / hysteria2 出站有 server_ports（端口跳跃）；
// 其它协议带这个字段，配置解码时会因未知字段整体失败，所以按协议限定，不是「有就放行」。
func supportsServerPorts(typ string) bool {
	switch strings.ToLower(typ) {
	case "hysteria", "hysteria2":
		return true
	}
	return false
}

// checkServer：server 必须是非空字符串；server_port 必须是 1–65535 的整数；
// server_ports 只允许 hysteria / hysteria2，格式与内核一致（每项 "起:止"，止可省略表示到 65535），
// 此时可以不带 server_port。
func checkServer(typ string, m map[string]any) string {
	if s, ok := m["server"].(string); !ok || strings.TrimSpace(s) == "" {
		return "missing or invalid server"
	}
	ports, hasPorts := m["server_ports"]
	if hasPorts {
		if !supportsServerPorts(typ) {
			return fmt.Sprintf("server_ports is not supported by %s", typ)
		}
		if reason := checkServerPorts(ports); reason != "" {
			return reason
		}
	}
	port, has := m["server_port"]
	if !has {
		if hasPorts {
			return ""
		}
		return "missing server_port"
	}
	if !validPort(port) {
		return "server_port is out of range"
	}
	return ""
}

// checkServerPorts 校验 server_ports：字符串或字符串列表，每项形如 "20000:30000" / "20000:"。
func checkServerPorts(v any) string {
	var items []any
	switch t := v.(type) {
	case string:
		items = []any{t}
	case []any:
		items = t
	default:
		return "server_ports must be a string or a list of strings"
	}
	if len(items) == 0 {
		return "server_ports is empty"
	}
	for i, it := range items {
		s, ok := it.(string)
		if !ok {
			return fmt.Sprintf("server_ports[%d] is not a string", i)
		}
		start, end, ok := strings.Cut(s, ":")
		if !ok {
			return fmt.Sprintf("server_ports[%d] %q is not a range (want start:end)", i, s)
		}
		lo, err := strconv.ParseUint(start, 10, 16)
		if err != nil || lo < 1 {
			return fmt.Sprintf("server_ports[%d] %q has an invalid start port", i, s)
		}
		hi := uint64(math.MaxUint16)
		if end != "" {
			hi, err = strconv.ParseUint(end, 10, 16)
			if err != nil || hi < lo {
				return fmt.Sprintf("server_ports[%d] %q has an invalid end port", i, s)
			}
		}
	}
	return ""
}

func validPort(v any) bool {
	f, ok := v.(float64) // encoding/json 把数字解成 float64
	if !ok || f != math.Trunc(f) {
		return false
	}
	return f >= 1 && f <= 65535
}
