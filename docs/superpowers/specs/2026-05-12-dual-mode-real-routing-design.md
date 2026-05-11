# 双模式真实路由（macOS + Android 都生效）

**日期**：2026-05-12
**状态**：approved（user "赶紧开始"）
**前置**：参见 2026-05-11 三次 macOS 调试发现的 bug 链

---

## 目标

- UI 上"全局 / 智能"两个模式都**真生效**（修当前 connect 覆盖 user 选择的 bug）
- 两个模式都**能上网**：全局走所有代理，智能国内直连国外走代理
- macOS（在大陆 GFW 下）、Android 都能用

## 真相对账

```
现状（修复前）：

用户点 UI 全局 → _onModeTap 推 region='other' → mode 持久化 ✓
用户点连接 → connect() 调 getDefaultConfigOptions() （没传 executeConfigAsIs）
            → 默认 region='cn' → 覆盖用户选择 ✗
            → fork 在 region=cn 时强制 append remote rule-set
              URL = hiddify-geo（中国大陆 GFW 阻断）
            → rule-set 下载失败 → DNS/Route 规则不完整
            → 流量去向错乱 → TLS 半路断

修复后：
mode 状态 → connect/restart/main 真传到 native；
两 mode 都用 region='other'（避开 fork 强制 append），由 Dart 端
自己用 bundled local .srs 实现智能模式分流。
```

## 整体方案

### 改动 1：mode state 真生效

`connect()` / `restart()` / `main.dart` 启动时都读 `proxyModeProvider`（持久化到 prefs 的 mode 索引），传给 `getDefaultConfigOptions(executeConfigAsIs: ...)`。

`proxyModeProvider`：0 = 全局，1 = 智能（保持现有约定）。

### 改动 2：避开 fork 强制 append

`getDefaultConfigOptions` 内 region 永远 `'other'`（无论 executeConfigAsIs）：

```dart
'region': 'other',  // 永远 other，避开 fork 强制 append hiddify-geo remote rule-set
```

这样 libcore `BuildConfig` 跳过 `region != "other"` 那段强制注入。

### 改动 3：bundled .srs 文件

```
assets/rule-sets/
├── geoip-cn.srs       # ~2MB 从 SagerNet/sing-geoip 取固定版本
├── geosite-cn.srs     # ~4MB 从 SagerNet/sing-geosite 取固定版本
├── VERSION            # 记 SagerNet release tag（如 20240811）
└── README.md          # 说明来源 + 升级流程
```

pubspec.yaml 注册 `assets/rule-sets/`。

### 改动 4：app 启动时 provision .srs

新增 `lib/core/box_service/rule_set_provisioner.dart`：

```dart
class RuleSetProvisioner {
  /// 把 bundled .srs copy 到 sing-box workingDir。
  /// 已存在 + version 一致就跳过；version 升级或不存在就重写。
  Future<void> ensureProvisioned(Directory workingDir) async {
    final versionFile = File('${workingDir.path}/.rule-set-version');
    final bundledVersion = await rootBundle.loadString('assets/rule-sets/VERSION');
    if (await versionFile.exists()) {
      final existing = await versionFile.readAsString();
      if (existing.trim() == bundledVersion.trim()) return;  // 已最新
    }
    for (final name in ['geoip-cn.srs', 'geosite-cn.srs']) {
      final bytes = await rootBundle.load('assets/rule-sets/$name');
      await File('${workingDir.path}/$name').writeAsBytes(bytes.buffer.asUint8List());
    }
    await versionFile.writeAsString(bundledVersion);
  }
}
```

main.dart 在 `boxService.setup(dirs)` 之后调用。

### 改动 5：profile_repository 剥离 + 智能模式注入

`_normalizeAndWrite` 写完 sing-box JSON 后再做 post-process：

- **永远剥离** profile 自带的 `route.rule_set` / `dns.rules` / `route.rules` 里所有 rule_set 引用——避免 sing-box 找不到 tag 时报错

`runtime_config_builder.dart`（新）：

```dart
/// connect 时根据 mode 现场组装 runtime config，写到 workingDir/runtime-config.json
Future<File> buildRuntimeConfig({
  required File baseProfile,     // 已剥离 rule-set 引用的基础版
  required bool isSmart,         // 智能模式
  required Directory workingDir, // .srs 所在目录
}) async {
  final cfg = jsonDecode(await baseProfile.readAsString());
  if (isSmart) {
    // 注入 local rule-set
    (cfg['route'] ??= {})['rule_set'] = [
      {'tag': 'geoip-cn', 'type': 'local', 'format': 'binary', 'path': './geoip-cn.srs'},
      {'tag': 'geosite-cn', 'type': 'local', 'format': 'binary', 'path': './geosite-cn.srs'},
    ];
    // 注入 cn 流量走 direct outbound
    final routeRules = (cfg['route']['rules'] ??= []) as List;
    routeRules.insert(0, {'rule_set': ['geoip-cn', 'geosite-cn'], 'outbound': 'direct'});
    // dns 也跟着走 local 解析
    final dnsRules = (cfg['dns']?['rules'] ??= []) as List;
    dnsRules.insert(0, {'rule_set': ['geosite-cn'], 'server': 'local'});
  }
  final out = File('${workingDir.path}/runtime-config.json');
  await out.writeAsString(jsonEncode(cfg));
  return out;
}
```

`connect()` 改：调 `buildRuntimeConfig` 拿到 runtime-config.json，把这个路径传 `boxService.start(...)`。

## 文件清单

| 文件 | 改动 |
|---|---|
| `assets/rule-sets/geoip-cn.srs` | 新增 |
| `assets/rule-sets/geosite-cn.srs` | 新增 |
| `assets/rule-sets/VERSION` | 新增 |
| `assets/rule-sets/README.md` | 新增（来源说明） |
| `pubspec.yaml` | 注册 assets/rule-sets/ |
| `lib/core/config/default_config_options.dart` | region 永远 'other' |
| `lib/core/box_service/rule_set_provisioner.dart` | 新增 |
| `lib/main.dart` | setup 后调 provisioner；启动时读 mode state 推 changeConfigOptions |
| `lib/core/config/runtime_config_builder.dart` | 新增 |
| `lib/features/profile/data/profile_repository.dart` | post-process 剥离 rule_set 引用 |
| `lib/core/providers/app_providers.dart` | connect/restart 读 mode + 调用 runtime_config_builder |

## 关键决策

| 项 | 决策 | 理由 |
|---|---|---|
| .srs 来源 | SagerNet/sing-geoip + sing-geosite 固定 release tag | 上游官方，比 hiddify-geo 中立 |
| .srs 版本 | 写死在 `VERSION` 文件；手动 bump | rule-set 格式偶尔 break，不自动升 |
| .srs 跨平台共用 | 是 | sing-box .srs 平台无关二进制 |
| region 默认值 | 永远 `'other'` | 唯一避开 fork 强制 append 的方式 |
| connect 时是否再写 profile | 不写 profile 本身；写 `runtime-config.json` | profile 是订阅原料，每次 connect 现场组装 runtime 配置 |
| 全局模式 dns / route rules | 不注入任何 cn 相关 rules，sing-box 兜底 default outbound 接管 | 这就是"全局"的语义 |
| 智能模式 cn rules 顺序 | 第一条插 `rule_set: [geoip-cn, geosite-cn] → direct` | sing-box 路由从前往后匹配，cn 直连优先 |
| Android 是否也用同套逻辑 | 是 | Android 上 mode 同样要生效；之前 Android 实测连接走通是因为 region=cn 时 Android 模拟器能直连 github raw，但这是侥幸 |

## 验证

**自动（dev_auto_boot）**：

1. 启动 macOS app：log 应该看到 `[Provisioner] copied 2 srs files to workingDir`
2. 自动连接走"智能"模式（mode 持久化默认 1）：
   - `[FFI] start configPath=...runtime-config.json` 而不是 `profiles/<id>.json`
   - sing-box 启动后 `box.log` 不再有 `fetch rule-set` 失败
   - `lsof` 看到 `127.0.0.1:2080 LISTEN`
   - `curl -x http://127.0.0.1:2080 https://www.google.com/generate_204` 返回 204
3. 在 UI 上切到"全局"模式 → 自动 reconnect → curl 测试仍通
4. 切回"智能" → 自动 reconnect → curl 测试仍通

**手动验证 Android 没退化**：跑一次 Android emulator，重复同样 mode 切换 + 浏览器 access。

## Out of scope

- 重编 libcore（Approach E）— 这套方案不需要
- 启动时自动下载新 .srs（Approach B）— 留给后续
- 用户在 settings 自选 rule-set provider — 留给后续
- 系统代理设置自动切换（macOS Wi-Fi 代理）— 默认 sing-box 自己处理；不依赖本 spec
- 其他 region（hk/jp 等）的智能分流 — 当前只支持 cn

## 风险

| 风险 | 缓解 |
|---|---|
| .srs 文件下载失败（GitHub 在大陆挂） | spec 实现时手动下载 + 提交到 repo；以后升级 SagerNet 时 user 翻墙取 |
| profile 自带的 dns.servers 用了 `detour: 节点选择` 等 selector tag → 我们注入的 dns rule 引用的 `server: local` 需要 profile 里真有 `local` server tag | 大部分订阅模板都有；如果没有 fallback：注入 dns server `{"address":"223.5.5.5","tag":"local-fallback"}` |
| Smart mode 注入的 rules 与 profile 自带 rules 冲突 | 插队到最前面，cn 流量先匹配；其他规则保留兜底 |
| .srs 版本与 sing-box 1.8 fork 不兼容 | SagerNet release 都标 sing-box 版本兼容性；锁的 .srs 选 1.8 兼容的 tag |

---

## 实施顺序

1. .srs 文件 + VERSION + assets 注册（user 协助下载或我手动 fetch）
2. RuleSetProvisioner
3. region 永久 'other' + profile post-process 剥离 rule_set
4. RuntimeConfigBuilder + connect/restart 改造
5. main.dart 读 mode state
6. 模拟器 / macOS 端到端验证
7. commit + push
