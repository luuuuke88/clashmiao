package uri

import (
	"errors"
	"strings"
	"testing"
)

func TestConvertDispatch(t *testing.T) {
	if _, err := Convert("hello"); err == nil || !strings.Contains(err.Error(), "not a share link") {
		t.Errorf("非链接: %v", err)
	}
	if _, err := Convert("ssconf://example.net/x"); !errors.Is(err, ErrUnsupportedScheme) || !strings.Contains(err.Error(), "ssconf") {
		t.Errorf("ssconf:// 应明确报不支持: %v", err)
	}
	if _, err := Convert("gopher://example.net"); !errors.Is(err, ErrUnsupportedScheme) {
		t.Errorf("未知 scheme: %v", err)
	}
	if SchemeOf("SS://x") != "ss" || SchemeOf("no scheme") != "" || SchemeOf("://x") != "" {
		t.Error("SchemeOf")
	}
}

func TestMinimalSS(t *testing.T) {
	// base64("aes-128-gcm:pw") = YWVzLTEyOC1nY206cHc=
	e, err := Convert("ss://YWVzLTEyOC1nY206cHc@192.0.2.1:8388#%E9%A6%99%E6%B8%AF")
	if err != nil {
		t.Fatal(err)
	}
	if e.Endpoint || e.Map["method"] != "aes-128-gcm" || e.Map["password"] != "pw" || e.Map["server_port"] != 8388 || e.Map["tag"] != "香港" {
		t.Errorf("%v", e.Map)
	}
	for _, bad := range []string{"ss://", "ss://x@host", "ss://@h:1", "ss://bm90LWJhc2U2NA@h:99999"} {
		if _, err := Convert(bad); err == nil {
			t.Errorf("%q 应失败", bad)
		}
	}
}
