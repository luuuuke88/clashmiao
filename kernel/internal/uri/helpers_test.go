package uri

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
)

var update = flag.Bool("update", false, "重写 testdata/uri/*.txt（样例行由测试表生成）")

// 合成 UUID / 密码 / 密钥：不对应任何真实凭据。
const (
	testUUID = "11111111-2222-4333-8444-555555555555"
	testPK   = "ivDROKaq354cSx7DJ6wLY49DSI3S8pMXN47fhzmty4Y"
	testKey1 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
	testKey2 = "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8="
)

// convCase 是一行表驱动用例：输入链接 → 期望的节点（或期望的错误）。
type convCase struct {
	name     string
	in       string
	want     map[string]any
	endpoint bool   // 期望是端点
	err      string // 非空：期望 Convert 失败且错误含这段文字（并满足 ErrInvalid）
}

// m 是写期望 map 的简写。
func m(kv ...any) map[string]any {
	out := map[string]any{}
	for i := 0; i+1 < len(kv); i += 2 {
		out[kv[i].(string)] = kv[i+1]
	}
	return out
}

func list(s ...string) []any {
	out := make([]any, len(s))
	for i, e := range s {
		out[i] = e
	}
	return out
}

func b64(s string) string  { return base64.StdEncoding.EncodeToString([]byte(s)) }
func b64u(s string) string { return base64.RawURLEncoding.EncodeToString([]byte(s)) }

func jsonOf(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// canon 经 JSON 往返，让期望值与实际值的数字类型（int / float64）一致。
func canon(t testing.TB, v any) any {
	t.Helper()
	var out any
	if err := json.Unmarshal([]byte(jsonOf(v)), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// runCases 跑一张表，并校验（或在 -update 时重写）这一组的样例文件 testdata/uri/<group>.txt。
// 样例文件只放能成功转换的行，供闸门测试（gate 包）把它们塞进最小配置跑 CheckConfig。
func runCases(t *testing.T, group string, cases []convCase) {
	t.Helper()
	if len(cases) < 10 {
		t.Fatalf("%s：每个 scheme 至少 10 行用例，现在只有 %d", group, len(cases))
	}
	var valid []string
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ent, err := Convert(tc.in)
			if tc.err != "" {
				if err == nil {
					t.Fatalf("应当失败（含 %q），却得到 %v", tc.err, ent.Map)
				}
				if !errors.Is(err, ErrInvalid) && !errors.Is(err, ErrUnsupportedScheme) {
					t.Errorf("错误应满足 ErrInvalid: %v", err)
				}
				if !strings.Contains(err.Error(), tc.err) {
					t.Errorf("错误 %q 应含 %q", err, tc.err)
				}
				return
			}
			if err != nil {
				t.Fatalf("Convert(%q): %v", tc.in, err)
			}
			if ent.Endpoint != tc.endpoint {
				t.Errorf("Endpoint = %v，期望 %v", ent.Endpoint, tc.endpoint)
			}
			if !reflect.DeepEqual(canon(t, ent.Map), canon(t, tc.want)) {
				t.Errorf("\n got  %s\n want %s", jsonOf(ent.Map), jsonOf(tc.want))
			}
			// 往返性质：Convert 的输出再过 legacy.Clean 不变（新形态不被清洗器改动）。
			var outbounds, endpoints []map[string]any
			if ent.Endpoint {
				endpoints = []map[string]any{ent.Map}
			} else {
				outbounds = []map[string]any{ent.Map}
			}
			res := legacy.Clean(outbounds, endpoints, legacy.CleanOptions{})
			after := append(append([]map[string]any{}, res.Outbounds...), res.Endpoints...)
			if !reflect.DeepEqual(canon(t, after), canon(t, []map[string]any{ent.Map})) || len(res.Removed) != 0 {
				t.Errorf("legacy.Clean 改动了 Convert 的输出:\n%s\n%s", jsonOf(ent.Map), jsonOf(after))
			}
		})
		if tc.err == "" {
			valid = append(valid, tc.in)
		}
	}
	checkSamples(t, group, valid)
}

func checkSamples(t *testing.T, group string, lines []string) {
	t.Helper()
	path := filepath.Join("testdata", "uri", group+".txt")
	want := "# 合成数据：主机用 example.net / RFC 5737 / RFC 3849 保留地址，UUID、密钥、密码均为随机生成，不对应任何真实服务器与凭据。\n" +
		"# 每行是一个能成功转换的分享链接；由 " + group + " 的表驱动测试生成（go test ./internal/uri -update）。\n" +
		strings.Join(lines, "\n") + "\n"
	if *update {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(want), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("缺样例文件（-update 生成）: %v", err)
	}
	if string(got) != want {
		t.Errorf("%s 与测试表不一致（-update 重写）", path)
	}
}
