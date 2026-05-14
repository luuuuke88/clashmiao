# Contributing to ClashMiao

感谢你对 ClashMiao（喵速）的兴趣！本文档帮你快速上手贡献流程。

## 项目结构

```
clashmiao-client/
├── lib/                       Flutter 代码
│   ├── app/                   外壳：路由、shell page、selected_tab
│   ├── core/                  核心抽象
│   │   ├── box_service/       sing-box 服务抽象（Android Platform / 桌面 FFI / Stub）
│   │   ├── config/            default_config_options / RuntimeConfigBuilder
│   │   ├── settings/          NetworkSettings 持久化
│   │   ├── providers/         全局 Riverpod provider（ConnectionController 等）
│   │   ├── theme/             AppTheme / AiUiTheme extension
│   │   ├── localization/      slang 翻译
│   │   ├── tray/              桌面端系统托盘
│   │   ├── auto_start/        macOS 开机启动
│   │   └── model/             BoxStatus / Outbound / Alert / Stats
│   ├── features/              业务页面
│   │   ├── home/              主页 + 连接按钮 + 模式选择
│   │   ├── profile/           订阅管理
│   │   ├── proxy/             节点列表 + 延迟测试
│   │   └── settings/          设置 + 日志页
│   └── shared/components/     公共 UI（toast / modal wrapper 等）
├── android/                   Android 原生（VpnService + libcore.aar）
├── ios/                       iOS 脚手架（PacketTunnelProvider + libcore.xcframework）
├── macos/                     macOS Flutter shell
├── windows/                   Windows shell + libs/libcore.dll
├── linux/                     Linux shell + libs/libcore.so
├── core/                      sing-box 核心交叉编译脚本
├── test/                      unit + widget 测试（92 个）
├── integration_test/          Android emulator E2E
├── bin/                       测试一键脚本
└── .github/workflows/         CI（analyze + unit test 跑在 PR / push）
```

## 环境准备

- Flutter **3.41.4**（项目用了 Dart 3.11.1 特性，旧版本 pub get 会失败）
- Android Studio + SDK + 至少一个 AVD
- Xcode（iOS / macOS）
- Go 1.21+（编 libcore，可选）

## 本地开发循环

```bash
flutter pub get                                  # 一次
bash bin/test-all.sh                             # 全套：format + analyze + 92 unit + Android/macOS E2E（并行）
flutter run -d macos                             # 起 macOS app
flutter run -d emulator-5554                     # 起 Android emulator
```

## 提交规范

Conventional Commits（中英文都接受）：

- `feat(scope): ...` 新功能
- `fix(scope): ...` bug 修复
- `chore(scope): ...` 杂项
- `test(scope): ...` 测试
- `docs(scope): ...` 文档
- `ci: ...` CI 改动
- `refactor(scope): ...` 重构

每次 commit 加 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
如果是 AI 协助产出的内容（避免误以为完全人写）。

## 测试要求

PR 必须：
- `dart format --set-exit-if-changed lib/ test/ integration_test/` 通过
- `flutter analyze --fatal-warnings` 0 个 issue
- `flutter test` 所有 92+ 个测试绿
- 新增功能至少加一个 unit test 或 widget test

## 代码风格约定

- **绝对不要在公开文档 / commit message 中提及上游具体项目名**
  （hiddify / baseproxy / NekoBox 等）。用通用术语"上游 fork" / "sing-box 核心"。
  源码内部技术注释解释 fork 行为时也用脱敏术语。
- 注释解释 **WHY**，不解释 WHAT。
- 状态用 Riverpod（hooks_riverpod），不用 setState 跨 widget 共享。
- 公共组件放 `lib/shared/components/`，feature-local 组件放 feature 目录。
- 翻译用 slang，不要硬编码字符串（已有部分历史遗留待清理）。

## 平台移植 / 验证

每个非 Android / 非 macOS 平台都有 `<platform>/SCAFFOLDING.md`，说明拿到对应硬件
后还需要做什么。如果你有那个平台的环境，验证后欢迎 PR 更新该文档。

## 协议

GPL-3.0。所有贡献视为接受 GPL-3.0 协议。
