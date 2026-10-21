// Package subscription 把订阅内容（sing-box JSON / Clash YAML / URI 列表）解析成 {outbounds, endpoints}。
// 输出只含节点：不补 inbounds / dns / route（那些由配置构建器生成）。本包不 import sing-box。
package subscription

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Profile 是订阅解析的产物。
type Profile struct {
	Outbounds []map[string]any `json:"outbounds"`
	Endpoints []map[string]any `json:"endpoints,omitempty"`
}

// Warnings 是不致命的提示（单节点失败、改名等），每条以稳定前缀开头：
// node-skipped: / tag-renamed: / tag-filled: / detour-remapped: / entry-skipped:
type Warnings []string

// Count 统计以 prefix 开头的警告数。
func (w Warnings) Count(prefix string) int {
	n := 0
	for _, x := range w {
		if strings.HasPrefix(x, prefix) {
			n++
		}
	}
	return n
}

// NodeCount 是节点数：真实出站 + 端点（selector / urltest / direct / block / dns 不算）。
// 口径与 spec §6.5 的「叶子视图」一致；outbounds 为空而端点非空是合法订阅。
func (p Profile) NodeCount() int {
	n := len(p.Endpoints)
	for _, o := range p.Outbounds {
		if t, _ := o["type"].(string); !isGroupOrDirectType(t) {
			n++
		}
	}
	return n
}

func isGroupOrDirectType(t string) bool {
	switch strings.ToLower(strings.NewReplacer("-", "", "_", "").Replace(strings.TrimSpace(t))) {
	case "direct", "block", "dns", "selector", "select", "urltest", "custom":
		return true
	}
	return false
}

// Parse 识别格式并解析（顺序固定，spec §6.1）：JSON → Clash YAML → URI 列表（含整体 base64）→ format-unknown。
// 错误带稳定前缀码，见 errors.go。
func Parse(in []byte) (Profile, Warnings, error) {
	return parse(in, 0)
}

func parse(in []byte, depth int) (Profile, Warnings, error) {
	if len(in) > MaxInputBytes {
		return Profile{}, nil, fail(CodeLimitExceeded, "the subscription is larger than %d bytes", MaxInputBytes)
	}
	in = normalizeInput(in)
	if len(in) == 0 {
		return Profile{}, nil, fail(CodeFormatUnknown, "empty input")
	}
	// 带头部注释的 JSON（以 // 或 /* 开头）：去掉注释再判断。
	if in[0] == '/' {
		if stripped := normalizeInput(stripJSONComments(in)); looksLikeJSON(stripped) {
			return parseJSON(stripped)
		}
	}
	text := string(in)
	switch {
	case looksLikeJSON(in):
		return parseJSON(in)
	case looksLikeHTML(text):
		return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format (the content looks like an HTML page)")
	case hasClashProxies(text):
		return parseClash(in)
	case hasShareLinks(text):
		return parseList(text)
	}
	// 整体 base64：解一次，里面可以是链接列表，也可以是 JSON / Clash。
	if depth == 0 {
		if dec, ok := decodeBase64Whole(text); ok {
			inner := normalizeInput(dec)
			if looksLikeJSON(inner) || hasClashProxies(string(inner)) || hasShareLinks(string(inner)) {
				return parse(inner, depth+1)
			}
		}
	}
	return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format")
}

func looksLikeHTML(text string) bool {
	head := strings.ToLower(text)
	if len(head) > 256 {
		head = head[:256]
	}
	return strings.HasPrefix(head, "<!doctype html") || strings.HasPrefix(head, "<html") ||
		strings.HasPrefix(head, "<head") || strings.HasPrefix(head, "<body") || strings.HasPrefix(head, "<?xml")
}

// finalize 对所有路径的结果做同一套收尾：补空 tag、去重、检查节点数。
func finalize(outbounds, endpoints []map[string]any, warnings Warnings, emptyReason string) (Profile, Warnings, error) {
	used := map[string]bool{}
	for _, list := range [][]map[string]any{outbounds, endpoints} {
		for _, m := range list {
			if tag, _ := m["tag"].(string); tag != "" {
				used[tag] = true
			}
		}
	}
	seen := map[string]bool{}
	seq := 0
	fix := func(list []map[string]any) {
		for _, m := range list {
			seq++
			tag, _ := m["tag"].(string)
			typ, _ := m["type"].(string)
			switch {
			case tag == "":
				nt := fmt.Sprintf("%s-%d", typ, seq)
				for used[nt] {
					nt += "_"
				}
				used[nt], seen[nt] = true, true
				m["tag"] = nt
				warnings = append(warnings, fmt.Sprintf("tag-filled: an entry without a tag was named %q", nt))
			case seen[tag]:
				for i := 2; ; i++ {
					nt := fmt.Sprintf("%s (%d)", tag, i)
					if !used[nt] {
						used[nt], seen[nt] = true, true
						m["tag"] = nt
						warnings = append(warnings, fmt.Sprintf("tag-renamed: duplicate tag %q renamed to %q", tag, nt))
						break
					}
				}
			default:
				seen[tag] = true
			}
		}
	}
	fix(outbounds)
	fix(endpoints)
	defaultWireguardPeers(endpoints)

	p := Profile{Outbounds: outbounds, Endpoints: endpoints}
	if p.Outbounds == nil {
		p.Outbounds = []map[string]any{}
	}
	if p.NodeCount() == 0 {
		return Profile{}, warnings, fail(CodeNoOutbounds, "%s", emptyReason)
	}
	return p, warnings, nil
}

// ParseFile 是门面 Core.Parse 的实现：读 inPath，解析，把 {"outbounds":[…],"endpoints":[…]} 原子地写到 outPath。
// debug 为真时输出缩进的 JSON（便于人读）。
func ParseFile(outPath, inPath string, debug bool) error {
	raw, err := readBounded(inPath)
	if err != nil {
		return err
	}
	p, _, err := Parse(raw)
	if err != nil {
		return err
	}
	var out []byte
	if debug {
		out, err = json.MarshalIndent(p, "", "  ")
	} else {
		out, err = json.Marshal(p)
	}
	if err != nil {
		return fail(CodeBuildFailed, "marshal: %v", err)
	}
	if len(out) > maxOutputBytes {
		return fail(CodeLimitExceeded, "the parsed profile is larger than %d bytes", MaxOutputBytes)
	}
	out = append(bytes.TrimSpace(out), '\n')
	tmp, err := os.CreateTemp(filepath.Dir(outPath), ".parse-*")
	if err != nil {
		return fail(CodeBuildFailed, "write output: %v", err)
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(out); err != nil {
		tmp.Close()
		os.Remove(tmpName)
		return fail(CodeBuildFailed, "write output: %v", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return fail(CodeBuildFailed, "write output: %v", err)
	}
	if err := os.Rename(tmpName, outPath); err != nil {
		os.Remove(tmpName)
		return fail(CodeBuildFailed, "write output: %v", err)
	}
	return nil
}

// readBounded 读订阅文件，最多读 MaxInputBytes：先看文件大小，再用带上限的读取兜底（文件可能在两步之间变大）。
func readBounded(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fail(CodeBuildFailed, "read %s: %v", filepath.Base(path), err)
	}
	defer f.Close()
	if st, err := f.Stat(); err == nil && st.Size() > MaxInputBytes {
		return nil, fail(CodeLimitExceeded, "the subscription is larger than %d bytes", MaxInputBytes)
	}
	raw, err := io.ReadAll(io.LimitReader(f, MaxInputBytes+1))
	if err != nil {
		return nil, fail(CodeBuildFailed, "read %s: %v", filepath.Base(path), err)
	}
	if len(raw) > MaxInputBytes {
		return nil, fail(CodeLimitExceeded, "the subscription is larger than %d bytes", MaxInputBytes)
	}
	return raw, nil
}

// defaultWireguardPeers 给没写 allowed_ips 的 WireGuard 对端补默认值 ["0.0.0.0/0","::/0"]：
// Clash 的 wireguard 节点不写它（默认全部走隧道），而内核要求每个对端都有，缺了 CheckConfig 就失败。
func defaultWireguardPeers(endpoints []map[string]any) {
	for _, ep := range endpoints {
		if ep["type"] != "wireguard" {
			continue
		}
		peers, _ := ep["peers"].([]any)
		for _, p := range peers {
			if m, ok := p.(map[string]any); ok {
				if ips, has := m["allowed_ips"]; !has || ips == nil {
					m["allowed_ips"] = []any{"0.0.0.0/0", "::/0"}
				}
			}
		}
	}
}
