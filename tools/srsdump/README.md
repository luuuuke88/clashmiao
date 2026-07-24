# srsdump

把 `assets/rule-sets/` 下的 `.srs` rule-set 反编译成明文 JSON，用来生成
`lib/core/config/cn_direct_rules.dart`。

**为什么需要它**：实际发布用的 libcore 在 `region:"other"` 前提下物理上不支持
任何形式的 rule-set，分流数据只能以明文列表经 `configOptions.rules` 注入。
完整理由见 `assets/rule-sets/README.md`。

## 用法

`core/sing-box/`（内核源码）在 `.gitignore` 里，所以这个工具没法直接放在它
下面跟踪。先把它复制进去再编译——它要 import `sing-box` 模块内的
`common/srs` 包，必须在那个 module 里才编得过：

```bash
mkdir -p core/sing-box/cmd/srsdump
cp tools/srsdump/main.go core/sing-box/cmd/srsdump/main.go

mkdir -p out
docker run --rm -v "$PWD/core/sing-box:/src" \
  -v "$PWD/assets/rule-sets:/geo:ro" -v "$PWD/out:/out" \
  -w /src golang:1.22 sh -c \
  "go run ./cmd/srsdump /geo/geosite-cn.srs > /out/site.json && \
   go run ./cmd/srsdump /geo/geoip-cn.srs > /out/ip.json"
```

> 用 Docker 而不是本机 Go：本机 Go 工具链在这台 macOS 上跑这个会报
> `dyld: missing LC_UUID load command`，换 Go 版本和重新签名都没解决，容器里
> 直接就过。

产出的两个 json 形如：

```json
{"domain": ["265.com", ...], "domain_suffix": [".baidu", ...], "ip_cidr": ["1.0.1.0/24", ...]}
```

再据此重新生成 `lib/core/config/cn_direct_rules.dart`：`ip_cidr` 进
`cnDirectCidrRanges`，`domain` 进 `cnDirectDomains`（注入时加 `full:` 前缀），
`domain_suffix` 进 `cnDirectDomainSuffixes`（加 `domain:` 前缀）。两个前缀
语义不同不能混用。

## 原理

`srs.Read(reader, recovery)` 的 `recovery` 传 `true` 时，内核
`common/srs/binary.go` 会对域名规则调用 `matcher.Dump()`，把 succinct trie
还原回 `Domain`/`DomainSuffix` 两个字符串列表——域名数据是可以导出的。
