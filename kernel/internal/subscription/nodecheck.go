package subscription

import (
	"fmt"
	"math"
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
	if reason := checkServer(m); reason != "" {
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

// checkServer：server 必须是非空字符串；server_port 必须是 1–65535 的整数（hysteria 系允许改用 server_ports 跳端口）。
func checkServer(m map[string]any) string {
	if s, ok := m["server"].(string); !ok || strings.TrimSpace(s) == "" {
		return "missing or invalid server"
	}
	port, has := m["server_port"]
	if !has {
		if _, hop := m["server_ports"]; hop {
			return ""
		}
		return "missing server_port"
	}
	if !validPort(port) {
		return "server_port is out of range"
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
