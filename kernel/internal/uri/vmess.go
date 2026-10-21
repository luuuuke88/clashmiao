package uri

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

func init() { Register("vmess", convertVMess) }

// convertVMess 同时认两种写法：
//
//	vmess://base64(JSON)   —— v2rayN 的分享格式（v / ps / add / port / id / aid / scy / net / type / host / path / tls / sni / alpn / fp）
//	vmess://uuid@host:port?type=…&security=…#name —— URL 形式
func convertVMess(line string) (Entity, error) {
	rest := line[len("vmess://"):]
	body, name := rest, ""
	if i := strings.Index(rest, "#"); i >= 0 {
		body, name = rest[:i], unescape(rest[i+1:])
	}
	// base64 里不会出现 @：有 @ 就是 URL 形式。
	if strings.Contains(body, "@") {
		return vmessFromURL(line)
	}
	return vmessFromJSON(body, name)
}

func vmessFromJSON(b64, fragmentName string) (Entity, error) {
	raw, err := decodeB64(b64)
	if err != nil {
		return Entity{}, invalidf("vmess", "payload is neither base64 JSON nor a URL")
	}
	var j map[string]any
	if err := json.Unmarshal(raw, &j); err != nil {
		return Entity{}, invalidf("vmess", "payload is not JSON: %v", err)
	}
	str := func(keys ...string) string {
		for _, k := range keys {
			if s := jsonString(j[k]); s != "" {
				return s
			}
		}
		return ""
	}
	host := str("add")
	port, err := strconv.Atoi(str("port"))
	if host == "" || err != nil || port < 1 || port > 65535 {
		return Entity{}, invalidf("vmess", "bad server address or port")
	}
	id := str("id")
	if id == "" {
		return Entity{}, invalidf("vmess", "missing id (uuid)")
	}
	name := str("ps")
	if name == "" {
		name = fragmentName
	}
	if name == "" {
		name = defaultTag(host, port)
	}

	out := base("vmess", name, host, port)
	out["uuid"] = id
	out["security"] = orDefault(str("scy", "security"), "auto")
	if aid, err := strconv.Atoi(str("aid")); err == nil && aid > 0 {
		out["alter_id"] = aid
	}

	netw := strings.ToLower(str("net"))
	p := params{}
	setIf := func(k, v string) {
		if v != "" {
			p[k] = v
		}
	}
	// tls 字段是枚举：空 / none / 0 / false 为关，tls / 1 / true 为开；别的值（xtls、reality……）
	// 不能静默当成「无 TLS」——那会把本该加密的连接降级成明文。
	switch tv := strings.ToLower(strings.TrimSpace(str("tls"))); tv {
	case "", "none", "0", "false":
	case "tls", "1", "true":
		p["security"] = "tls"
	default:
		return Entity{}, invalidf("vmess", "unsupported tls value %q", tv)
	}
	setIf("sni", str("sni"))
	setIf("alpn", str("alpn"))
	setIf("fp", str("fp"))
	setIf("host", str("host"))
	if str("allowInsecure", "allowinsecure", "insecure") == "1" || strings.EqualFold(str("allowInsecure", "allowinsecure", "insecure"), "true") {
		p["allowinsecure"] = "1"
	}
	tls, err := tlsFor("vmess", p, host, false)
	if err != nil {
		return Entity{}, err
	}
	if tls != nil {
		out["tls"] = tls
	}
	spec := transportSpec{Network: netw, HeaderType: str("type"), Host: str("host"), Path: str("path")}
	if netw == "grpc" {
		spec.ServiceName = str("path")
	}
	tr, err := transportFor("vmess", spec)
	if err != nil {
		return Entity{}, err
	}
	if tr != nil {
		out["transport"] = tr
	}
	return Entity{Map: out}, nil
}

func vmessFromURL(line string) (Entity, error) {
	l, err := parseLink(line)
	if err != nil {
		return Entity{}, err
	}
	if err := l.need(); err != nil {
		return Entity{}, err
	}
	if l.user == "" {
		return Entity{}, invalidf("vmess", "missing uuid")
	}
	out := base("vmess", l.tag(), l.host, l.port)
	out["uuid"] = l.user
	out["security"] = orDefault(l.query.get("encryption", "scy", "security_method"), "auto")
	if aid, err := strconv.Atoi(l.query.get("aid", "alterid")); err == nil && aid > 0 {
		out["alter_id"] = aid
	}
	tls, err := tlsFor("vmess", l.query, l.host, false)
	if err != nil {
		return Entity{}, err
	}
	if tls != nil {
		out["tls"] = tls
	}
	tr, err := transportFor("vmess", transportSpec{
		Network: l.query.get("type", "net", "network"), HeaderType: l.query.get("headerType"),
		Host: l.query.get("host"), Path: l.query.get("path"), ServiceName: l.query.get("serviceName", "service_name"),
	})
	if err != nil {
		return Entity{}, err
	}
	if tr != nil {
		out["transport"] = tr
	}
	return Entity{Map: out}, nil
}

// jsonString 把 JSON 里可能是字符串或数字的值转成字符串。
func jsonString(v any) string {
	switch t := v.(type) {
	case string:
		return strings.TrimSpace(t)
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return fmt.Sprint(t)
	case bool:
		if t {
			return "true"
		}
	}
	return ""
}
