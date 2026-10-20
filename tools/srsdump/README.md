# srsdump

把 `assets/rule-sets/` 下的 `.srs` rule-set 反编译成明文 JSON，用来生成
`lib/domain/config/data/cn_direct_rules.dart`。

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

再跑生成器，据此重新生成 `lib/domain/config/data/cn_direct_rules.dart`：

```bash
dart tools/srsdump/gen_cn_direct_rules.dart out/site.json out/ip.json
```

生成器做两件事：

1. **应用排除表** [`cn_direct_exclusions.txt`](cn_direct_exclusions.txt)：
   geosite-cn 里带着一批谷歌系域名（当年谷歌北京节点还在时可直连），现在在
   大陆网络下直连全部超时。排除表里的域名连同子域从精确/后缀清单里删掉，
   排除表里的地址段（谷歌北京 GOOGLECN 段）从 CIDR 清单里挖掉。仍会盖住被
   排除域名的更宽后缀（顶级域 `cn` 盖住 `google.cn`）改写成一条"同样的后缀
   匹配、但跳过被排除域名"的正则，进 `cnDirectDomainRegexes`——否则删掉的
   条目会被 `cn` 重新捞回直连。排除逻辑在 [`cn_direct_filter.dart`](cn_direct_filter.dart)，
   单元测试和生成器共用同一份。
2. **写出 Dart 文件**：`ip_cidr` 进 `cnDirectCidrRanges`，`domain` 进
   `cnDirectDomains`（注入时加 `full:` 前缀），`domain_suffix` 进
   `cnDirectDomainSuffixes`（加 `domain:` 前缀），改写出的正则进
   `cnDirectDomainRegexes`（加 `regexp:` 前缀）。几个前缀语义不同不能混用。
   这次排除了哪些条目会打印到 stderr，提交前核对一遍。

规则库升级或排除表改动后，重跑上面两步即可，排除表每次都会自动重新应用；
`test/domain/config/data/cn_direct_rules_test.dart` 里有一条按谷歌系关键词
兜底的测试，新数据冒出排除表没覆盖的谷歌域名会直接失败，届时补进排除表再
重新生成。

## 原理

`srs.Read(reader, recovery)` 的 `recovery` 传 `true` 时，内核
`common/srs/binary.go` 会对域名规则调用 `matcher.Dump()`，把 succinct trie
还原回 `Domain`/`DomainSuffix` 两个字符串列表——域名数据是可以导出的。
