//go:build !race

// 这组测试是纯结构校验（没有并发），-race 下慢 10 倍以上而没有收益，所以放在 !race 文件里由 gotest.sh 的第二遍运行。

package gate

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"

	"github.com/luuuuke88/clashmiao/kernel/internal/build"
	"github.com/luuuuke88/clashmiao/kernel/internal/subscription"
)

// uri 包的样例行（internal/uri/testdata/uri/*.txt，由各 scheme 的表驱动测试生成）逐行经 Parse → BuildConfig →
// 不变量 → 适配副本 libbox.CheckConfig：证明 URI 转换器的输出在 1.14 schema 下合法。
// （计划把这组测试放在 uri 包里；uri 包按约定不得 import sing-box，所以放在闸门包。）
func TestURISampleLinesPassCheckConfig(t *testing.T) {
	dir := filepath.Join(TestdataDir(), "..", "..", "uri", "testdata", "uri")
	files, err := filepath.Glob(filepath.Join(dir, "*.txt"))
	if err != nil || len(files) == 0 {
		t.Fatalf("没有样例文件: %v", err)
	}
	total := 0
	for _, f := range files {
		group := strings.TrimSuffix(filepath.Base(f), ".txt")
		raw, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		n := 0
		for i, line := range strings.Split(string(raw), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			n++
			total++
			t.Run(group+"/"+strconv.Itoa(i+1), func(t *testing.T) {
				p, _, err := subscription.Parse([]byte(line))
				if err != nil {
					t.Fatalf("Parse(%q): %v", line, err)
				}
				o := Option("O1")
				cfgRaw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
				if err != nil {
					t.Fatalf("Build: %v", err)
				}
				if vs := CheckInvariants(cfgRaw, o, build.AndroidEnv()); len(vs) != 0 {
					t.Errorf("不变量违规: %v", vs)
				}
				adapted, ap, err := HostAdapt(cfgRaw, AdaptOptions{})
				if err != nil {
					t.Fatal(err)
				}
				if bad, err := CheckWhitelist(cfgRaw, adapted, ap); err != nil || len(bad) != 0 {
					t.Fatalf("%v %v", err, bad)
				}
				if err := CheckConfig(adapted); err != nil {
					t.Fatalf("CheckConfig(%s): %v", line, err)
				}
			})
		}
		if n < 10 {
			t.Errorf("%s 只有 %d 行样例，每个 scheme 至少 10 行", group, n)
		}
	}
	t.Logf("共校验 %d 行样例", total)
}

// ssh 的私钥与主机密钥不把真的密钥放进仓库：这里运行时生成一对合成密钥，拼成链接，走同样的 Parse → Build → CheckConfig。
func TestSSHKeyLinksPassCheckConfig(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(priv, "")
	if err != nil {
		t.Fatal(err)
	}
	pemText := string(pem.EncodeToMemory(block))
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	hostKey := strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub)))

	for name, link := range map[string]string{
		"私钥":        "ssh://user@192.0.2.20:2222?private_key=" + url.PathEscape(pemText) + "#k1",
		"私钥 + 主机密钥": "ssh://user@192.0.2.21:22?private_key=" + url.PathEscape(pemText) + "&host_key=" + url.PathEscape(hostKey) + "#k2",
		"密码 + 主机密钥": "ssh://user:pw@192.0.2.22:22?host_key=" + url.PathEscape(hostKey) + "#k3",
	} {
		t.Run(name, func(t *testing.T) {
			p, _, err := subscription.Parse([]byte(link))
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			if got := p.Outbounds[0]["private_key"]; strings.Contains(link, "private_key=") && got != pemText {
				t.Errorf("私钥应原样保留（含换行）")
			}
			o := Option("O1")
			cfgRaw, _, err := build.Build(toBuildProfile(p), o, build.AndroidEnv())
			if err != nil {
				t.Fatal(err)
			}
			adapted, _, err := HostAdapt(cfgRaw, AdaptOptions{})
			if err != nil {
				t.Fatal(err)
			}
			if err := CheckConfig(adapted); err != nil {
				t.Fatalf("CheckConfig: %v", err)
			}
		})
	}
}
