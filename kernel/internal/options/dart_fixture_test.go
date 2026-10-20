package options

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// 跨语言契约（Go 一侧）：Dart 的 getDefaultConfigOptions 在设置矩阵上的输出入库在
// testdata/options/*.json（由 test/domain/config/data/options_fixture_export_test.dart 生成）。
// 这里全部读进来：
//   - Decode 无「未知键」警告（含 rules 项里的键）、Validate 通过 —— Dart 产生任何 Go 不认识的键即失败；
//   - 反向：Go 已知键集合 == keys.txt 的 dart 一节 ∪ go-only 一节，且两节不相交；
//   - keys.txt 的 dart 一节 == 全部夹具里实际出现的键（两种语言对「键集合」的看法在夹具上闭合）。
const dartOptionsDir = "../../testdata/options"

func dartFixtureFiles(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(dartOptionsDir, "*.json"))
	if err != nil || len(files) < 20 {
		t.Fatalf("Dart 选项夹具太少（%d 个，err=%v）：路径写错或夹具被删", len(files), err)
	}
	sort.Strings(files)
	return files
}

// knownKeyPaths 反射出 Options 的全部键路径：顶层键、父.子、规则项 rules[].键。
func knownKeyPaths(t reflect.Type, prefix string, out map[string]bool) {
	for i := 0; i < t.NumField(); i++ {
		tag := strings.Split(t.Field(i).Tag.Get("json"), ",")[0]
		if tag == "" || tag == "-" {
			continue
		}
		path := prefix + tag
		out[path] = true
		ft := t.Field(i).Type
		switch {
		case ft.Kind() == reflect.Struct:
			knownKeyPaths(ft, path+".", out)
		case ft.Kind() == reflect.Slice && ft.Elem().Kind() == reflect.Struct:
			knownKeyPaths(ft.Elem(), path+"[].", out)
		}
	}
}

// fixtureKeyPaths 是一份夹具里出现的键路径（与 Dart 侧 _keyPaths 同口径）。
func fixtureKeyPaths(v any, prefix string, out map[string]bool) {
	switch x := v.(type) {
	case map[string]any:
		for k, val := range x {
			path := k
			if prefix != "" {
				path = prefix + "." + k
			}
			out[path] = true
			fixtureKeyPaths(val, path, out)
		}
	case []any:
		for _, item := range x {
			if m, ok := item.(map[string]any); ok {
				for k, val := range m {
					path := prefix + "[]." + k
					out[path] = true
					fixtureKeyPaths(val, path, out)
				}
			}
		}
	}
}

func TestDartFixturesDecodeWithoutUnknownKeys(t *testing.T) {
	known := map[string]bool{}
	knownKeyPaths(reflect.TypeOf(Options{}), "", known)
	for _, file := range dartFixtureFiles(t) {
		name := filepath.Base(file)
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			o, warns, err := Decode(raw)
			if err != nil {
				t.Fatalf("Decode: %v", err)
			}
			for _, w := range warns {
				t.Errorf("Dart 产生了 Go 不认识的键或警告: %s: %s", w.Code, w.Message)
			}
			if err := o.Validate(); err != nil {
				t.Errorf("Validate: %v", err)
			}
			// 规则项里的键不在 Decode 的未知键检查范围内（按切片解码），这里补上。
			var generic any
			if err := json.Unmarshal(raw, &generic); err != nil {
				t.Fatal(err)
			}
			seen := map[string]bool{}
			fixtureKeyPaths(generic, "", seen)
			for path := range seen {
				if !known[path] {
					t.Errorf("夹具里的键 %q 不是 Go 的已知键", path)
				}
			}
			// 每条规则都能解析成匹配条件（Dart 注入的全量直连清单也要能被规则层吃下）。
			for i, r := range o.Rules {
				if _, err := r.Matchers(); err != nil {
					t.Errorf("rules[%d] 解析失败: %v", i, err)
				}
			}
		})
	}
}

func readKeysTxt(t *testing.T) (dart, goOnly map[string]bool) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(dartOptionsDir, "keys.txt"))
	if err != nil {
		t.Fatal(err)
	}
	dart, goOnly = map[string]bool{}, map[string]bool{}
	var cur map[string]bool
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case line == "" || strings.HasPrefix(line, "#"):
		case line == "[dart]":
			cur = dart
		case line == "[go-only]":
			cur = goOnly
		default:
			if cur == nil {
				t.Fatalf("keys.txt：键 %q 出现在任何节之前", line)
			}
			cur[line] = true
		}
	}
	if len(dart) == 0 || len(goOnly) == 0 {
		t.Fatalf("keys.txt 的两节都不能为空：dart=%d go-only=%d", len(dart), len(goOnly))
	}
	return dart, goOnly
}

func keysDiff(a, b map[string]bool) []string {
	var out []string
	for k := range a {
		if !b[k] {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

// Go 已知键 == keys.txt 的 dart 一节 ∪ go-only 一节，两节不相交。
func TestGoKnownKeysMatchKeysTxt(t *testing.T) {
	dart, goOnly := readKeysTxt(t)
	known := map[string]bool{}
	knownKeyPaths(reflect.TypeOf(Options{}), "", known)

	for k := range goOnly {
		if dart[k] {
			t.Errorf("键 %q 同时在 dart 与 go-only 两节", k)
		}
	}
	union := map[string]bool{}
	for k := range dart {
		union[k] = true
	}
	for k := range goOnly {
		union[k] = true
	}
	if d := keysDiff(known, union); len(d) > 0 {
		t.Errorf("Go 已知、但 keys.txt 没有登记的键（新增选项键要同时在 Dart 导出里出现或标为 go-only）: %v", d)
	}
	if d := keysDiff(union, known); len(d) > 0 {
		t.Errorf("keys.txt 里有、Go 不认识的键（Dart 产生了 Go 没有的键，或 go-only 过期）: %v", d)
	}
}

// keys.txt 的 dart 一节 == 全部夹具里实际出现的键。
func TestKeysTxtMatchesFixtures(t *testing.T) {
	dart, _ := readKeysTxt(t)
	seen := map[string]bool{}
	for _, file := range dartFixtureFiles(t) {
		raw, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		var generic any
		if err := json.Unmarshal(raw, &generic); err != nil {
			t.Fatal(err)
		}
		fixtureKeyPaths(generic, "", seen)
	}
	if d := keysDiff(seen, dart); len(d) > 0 {
		t.Errorf("夹具里出现、keys.txt dart 一节没有的键: %v", d)
	}
	if d := keysDiff(dart, seen); len(d) > 0 {
		t.Errorf("keys.txt dart 一节有、夹具里从未出现的键: %v", d)
	}
}
