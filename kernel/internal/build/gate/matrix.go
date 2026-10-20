package gate

import (
	"testing"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/options"
)

// Case 是矩阵里的一格：profile × 选项夹具。名字同时是黄金文件名与 testdata/README 表里的键。
type Case struct {
	Name    string
	Profile string
	Option  string
}

// Matrix 是已落地的格子；每个任务往这里加格子，并在 testdata/README 的表里登记。
var Matrix = []Case{
	{"P1-O1", "P1", "O1"},
	{"P1-O2", "P1", "O2"},
	{"P1-O7-prefer", "P1", "O7-prefer"},
	{"P1-O8", "P1", "O8"},
	{"P2-O1", "P2", "O1"},
	{"P4b-O1", "P4b", "O1"},
	// U5：DNS 子系统（P2 的节点有域名，直连域名规则才有内容）。
	{"dns-O3", "P2", "O3"},
	{"dns-O6-ip", "P2", "O6-ip"},
	{"dns-O6-https-domain", "P2", "O6-https-domain"},
	{"dns-O6-https-ip", "P2", "O6-https-ip"},
	{"dns-O6-h3", "P2", "O6-h3"},
	{"dns-O6-tls", "P2", "O6-tls"},
	{"dns-O6-quic", "P2", "O6-quic"},
	{"dns-O6-tcp", "P2", "O6-tcp"},
	{"dns-O6-udp", "P2", "O6-udp"},
	{"dns-O6-local", "P2", "O6-local"},
	{"dns-O6-direct-doh-domain", "P2", "O6-direct-doh-domain"},
	{"dns-O7-only", "P2", "O7-only"},
	// U6：路由与规则（O3 带 bypass / block / IP / proxy 四类用户规则与 bypass-lan）。
	{"route-O3", "P1", "O3"},
	{"route-O9", "P1", "O9"},
	{"route-O10", "P1", "O10"},
}

// BuildCase 构建一个矩阵格子的原始（Android）配置，并返回它用的选项。
func BuildCase(t testing.TB, c Case) ([]byte, *options.Options) {
	t.Helper()
	o := Option(c.Option)
	if err := o.Validate(); err != nil {
		t.Fatalf("选项夹具 %s 不合法: %v", c.Option, err)
	}
	raw, _, err := build.Build(LoadProfile(t, c.Profile), o, build.AndroidEnv())
	if err != nil {
		t.Fatalf("Build(%s): %v", c.Name, err)
	}
	return raw, o
}
