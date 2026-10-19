# Contributing to ClashMiao

感谢你对 ClashMiao（喵速）的兴趣！本文档帮你快速上手贡献流程。

## 项目结构

```
clashmiao-client/
├── lib/                       Flutter 代码，按五层组织（依赖规则与归属原则见 docs/ARCHITECTURE.md「分层」）
│   ├── main.dart              启动组装
│   ├── app/                   应用外壳：路由、Shell、托盘、快捷键、窗口守卫、深链编排
│   ├── features/<功能>/        页面级功能（about / assets / config / home / logs / profile / proxy / settings / splash），
│   │                          内部按 model / data / application / presentation 分
│   ├── domain/<概念>/          跨功能的业务概念（config / profile / routing / connection），
│   │                          内部按 model / data / application 分
│   ├── core/<模块>/            平台与基础设施，零业务（box_service、theme、localization、http_client 等）
│   └── shared/                不懂业务的通用 UI（components）与导航状态（navigation）
├── android/                   Android 原生（VpnService + libcore.aar）
├── ios/                       iOS 原生（PacketTunnelProvider + libcore.xcframework）
├── macos/                     macOS Flutter shell
├── windows/                   Windows shell + libs/libcore.dll
├── linux/                     Linux shell + libs/libcore.so
├── pigeons/                   Pigeon 接口定义（改完跑 bin/regen-pigeon.sh）
├── core/                      sing-box 核心构建脚本
├── test/                      unit + widget 测试，目录与 lib/ 一一对应；test/architecture/ 是架构测试
├── integration_test/          真机 / 模拟器集成测试
├── bin/                       脚本（测试、拉取 libcore、重新生成 Pigeon、发布辅助等）
└── .github/workflows/         CI（analyze + unit test + 各平台构建）
```

新增文件放哪一层、什么样的跨层依赖会被 CI 拒绝，见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的「分层」一节；架构测试（`test/architecture/`）报错时按该节「架构测试」里的顺序处理，**不要靠往白名单里加条目过关**。

## 环境准备

- Flutter **3.44.2**（CI 使用的版本；pubspec 要求 Dart SDK `^3.11.0`，更旧的版本 pub get 会失败。格式化请用同版本，不同版本的格式化器会改动无关行）
- Android Studio + SDK + 至少一个 AVD
- Xcode（iOS / macOS）
- Go 1.21+（编 libcore，可选）

## 本地开发循环

```bash
flutter pub get                                  # 一次
bash bin/test-all.sh                             # 全套：format + analyze + unit/widget + Android/macOS E2E（并行）
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
- `flutter test` 全部通过（含 `test/architecture/` 的分层检查）
- 新增功能至少加一个 unit test 或 widget test

## 代码风格约定

- 注释解释 **WHY**，不解释 WHAT。
- 状态用 Riverpod（hooks_riverpod），不用 setState 跨 widget 共享。
- 新文件归属：被多个功能（或 `app` / `domain`）用到的业务逻辑放 `lib/domain/<概念>/`；与业务无关的通用 UI 放 `lib/shared/`，通用基础能力放 `lib/core/`；只服务一个页面的放该功能目录。判定细则见 docs/ARCHITECTURE.md。
- 一律用 `package:clashmiao/...` 导入，不用相对路径（`always_use_package_imports` lint 会拦）。
- 翻译用 slang，不要硬编码字符串（已有部分历史遗留待清理）。

## 平台移植 / 验证

每个非 Android / 非 macOS 平台都有 `<platform>/SCAFFOLDING.md`，说明拿到对应硬件
后还需要做什么。如果你有那个平台的环境，验证后欢迎 PR 更新该文档。

## 协议

GPL-3.0。所有贡献视为接受 GPL-3.0 协议。
