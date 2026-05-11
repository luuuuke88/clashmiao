# Rule-Sets

sing-box `rule-set` 二进制文件（`.srs`），用于智能模式分流：

- `geoip-cn.srs` — 中国大陆 IP 段
- `geosite-cn.srs` — 中国大陆域名

App 启动时由 `RuleSetProvisioner` copy 到 sing-box working dir，
profile runtime config 用 `type: local + path: ./<name>.srs` 引用。

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
