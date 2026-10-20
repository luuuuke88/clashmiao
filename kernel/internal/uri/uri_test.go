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
