package subscription

import (
	"fmt"
	"strings"

	"github.com/luuuuke88/clashmiao/kernel/internal/legacy"
	"github.com/luuuuke88/clashmiao/kernel/internal/uri"
)

// parseList：URI 列表，每行一个分享链接，交给 internal/uri。
// 空行与 # 开头的注释行忽略；单行失败记警告，至少一个成功即成功；全部失败才报错并带首个失败原因。
func parseList(text string) (Profile, Warnings, error) {
	var outbounds, endpoints []map[string]any
	var warnings Warnings
	var firstReason string
	attempted := 0

	for i, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strings.TrimRight(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		attempted++
		if attempted > MaxNodes {
			return Profile{}, warnings, fail(CodeLimitExceeded, "the list has more than %d links", MaxNodes)
		}
		skip := func(reason string) {
			msg := fmt.Sprintf("line %d: %s", i+1, reason)
			if firstReason == "" {
				firstReason = msg
			}
			warnings = append(warnings, "node-skipped: "+msg)
		}
		if !isLinkLine(line) {
			skip("not a share link")
			continue
		}
		ent, err := uri.Convert(line)
		if err != nil {
			skip(err.Error())
			continue
		}
		if ent.Endpoint {
			endpoints = append(endpoints, ent.Map)
		} else {
			outbounds = append(outbounds, ent.Map)
		}
	}
	if attempted == 0 {
		return Profile{}, nil, fail(CodeFormatUnknown, "unable to determine config format (no share links)")
	}
	if len(outbounds)+len(endpoints) == 0 {
		return Profile{}, warnings, fail(CodeURIInvalid, "none of the %d links could be converted: %s", attempted, firstReason)
	}
	// 链接转换出来的是新形态，过一遍清洗只为与其它路径保持同一套收尾（幂等）。
	res := legacy.Clean(outbounds, endpoints, legacy.CleanOptions{RemapTarget: "direct"})
	warnings = append(warnings, res.Warnings...)
	return finalize(res.Outbounds, res.Endpoints, warnings, "profile has no usable outbound")
}
