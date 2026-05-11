# 喵速 (ClashMiao)

跨平台代理客户端，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心。

## 特性

- 🐱 简洁现代的 UI 设计
- 📱 跨平台支持：iOS、Android、macOS、Windows、Linux
- 🔗 订阅管理：支持 base64/clash/singbox 格式
- ⚡ 延迟测试与自动选择
- 📊 实时流量统计
- 🎨 Material Design 3 + 动态颜色

## 技术栈

- **UI 框架**: Flutter
- **代理核心**: sing-box
- **状态管理**: Riverpod
- **路由**: go_router

## 编译

### 前置要求

- Flutter 3.41+
- Go 1.21+（用于编译 sing-box 核心）
- Xcode 15+（iOS/macOS）
- Android SDK

### 编译 sing-box 核心

```bash
cd core
./build.sh ios      # iOS
./build.sh android  # Android
./build.sh macos    # macOS
./build.sh all      # 全部平台
```

### 运行

```bash
flutter pub get
flutter run
```

## 许可证

GPL-3.0
