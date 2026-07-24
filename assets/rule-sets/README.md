# Rule-Sets

sing-box `rule-set` 二进制文件（`.srs`）：

- `geoip-cn.srs` — 中国大陆 IP 段
- `geosite-cn.srs` — 中国大陆域名

## ⚠️ 这两个文件是**构建期数据源**，运行时没有任何代码读它们

早期设计是 App 启动时把它们 copy 到 sing-box working dir、再由 runtime config
用 `type: local + path: ./<name>.srs` 引用。**这条路走不通**——实际发布用的
libcore 在 `region:"other"` 前提下物理上不支持任何形式的 rule-set，三条独立
证据：

1. 它的 `Rule` 结构体虽然有 `rule-set-url` 字段，但 `MakeRule()` 从不读它——
   对预编译二进制做 `strings` 反查，`domains`/`outbound` 两个 tag 在，
   `rule-set-url` 这个 tag 根本不存在；
2. 构造 route 时 `RuleSet`/`GeoIP`/`Geosite` 三个 provider 配置全被注释掉，
   `strings` 也找不到 `GeoSitePath`——就算让 `MakeRule()` 填上 Geosite 引用，
   也没有 provider 去解析它，配置加载必然失败；
3. 唯一会创建 rule-set 的代码路径被 `if Region != "other"` 包住，且全是指向
   被墙 URL 的 remote 类型——本项目正是为了绕开它才故意永远传 `region:"other"`
   （见 `docs/superpowers/parity/deferred-and-blocked.md` H 节）。

因此这两个文件现在的唯一用途是：**在构建期被反编译成
`lib/core/config/cn_direct_rules.dart`**，分流数据以明文列表经
`configOptions.rules` 注入内核。原来那个 `RuleSetProvisioner` 已随此结论删除。

## 反编译（规则库更新后需要重跑）

```bash
docker run --rm -v "$PWD/core/sing-box:/src" \
  -v "$PWD/assets/rule-sets:/geo:ro" -v "$PWD/out:/out" \
  -w /src golang:1.22 sh -c \
  "go run ./cmd/srsdump /geo/geosite-cn.srs > /out/site.json && \
   go run ./cmd/srsdump /geo/geoip-cn.srs > /out/ip.json"
```

工具源码见 `tools/srsdump/`（含用法说明；`core/sing-box/` 在 .gitignore 里，
所以工具本体放在跟踪目录，用前复制进内核源码树再编）。原理：`srs.Read(reader, recovery=true)`
的 `recovery` 为 true 时，内核 `common/srs/binary.go` 会对域名规则调用
`matcher.Dump()`，把 succinct trie 还原成 `Domain`/`DomainSuffix` 两个字符串
列表——域名数据是能导出的（早前记录的"没有导出 API"是错的）。

## 为什么仍然打包进 App

`assets/rule-sets/` 仍在 `pubspec.yaml` 的 assets 列表里（约 84KB）。保留的
理由是 Geo 资源管理页把这两个文件名当作"可下载的规则库资源"来管理
（`lib/features/assets/model/geo_asset.dart`）。该页面本身因 CDN URL 未配置
而尚未真正可用，等它的去留有结论后，再决定这两个文件要不要从 bundle 里移出。

## 来源 + 升级流程

来源：[SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip)
+ [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite) 的 `rule-set` 分支。

当前快照见同目录 `VERSION` 文件。

升级（半年一次或 sing-box 行为变化时）：

```bash
curl -sSL -o assets/rule-sets/geoip-cn.srs \
  "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
curl -sSL -o assets/rule-sets/geosite-cn.srs \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"

# 更新 VERSION 文件，记新 commit sha
```

## 兼容

`.srs` 文件 magic header 是 `SRS\x01`（`0x53 0x52 0x53 0x01`）。
sing-box 1.8+ 兼容。当前 `core/build.sh` 编译的 sing-box 1.11.0 fork 兼容此格式。
