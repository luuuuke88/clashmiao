# Pigeon 强类型 Native Bridge

替代散落的 MethodChannel 字符串契约。在这里定义一次，三端（Dart / Kotlin / Swift）
强类型对齐，增删字段编译期就能报错。

## 工作流

1. 编辑 `box_api.dart`（添 method / field / class）
2. 生成：
   ```bash
   dart run pigeon --input pigeons/box_api.dart
   ```
3. 三端 `.g.{dart,kt,swift}` 自动更新
4. 在 Dart 端用 `BoxHostApi` 调原生；在 Kotlin/Swift 端实现 `BoxApi` 接口

## 生成产物

| 平台 | 路径 |
|---|---|
| Dart | `lib/core/box_service/pigeon/box_api.g.dart` |
| Android Kotlin | `android/app/src/main/kotlin/com/clashmiao/clashmiao/pigeon/BoxApi.g.kt` |
| iOS Swift | `ios/Runner/Pigeon/BoxApi.g.swift` |

## 迁移现状

- ✅ 接口已定义（lifecycle: init/setup/start/stop/restart/changeConfigOptions/selectOutbound/urlTest/clearLogs/validateConfig）
- ⏳ `PlatformBoxService` 还在用旧 MethodChannel（migration 单独 PR）
- ⏳ `MethodHandler.kt` 还在用 trigger string match（migration 单独 PR）
- ⏳ iOS Swift handlers 也待迁

**EventChannel 流（watchStatus / watchAlerts / watchStats / watchGroups / watchLogs）
不走 Pigeon** —— Pigeon 对流支持还在 stabilize，现有 EventChannel 实现没有可读性
问题，先不动。

## 迁移示例

之前：
```dart
await _channel.invokeMethod('start', {'path': configPath, 'name': profileName});
```

之后：
```dart
await _hostApi.start(StartRequest(configPath: configPath, profileName: profileName));
```

之前（Kotlin）：
```kotlin
"start" -> { val path = args["path"] as String? ?: ""; ... }
```

之后：
```kotlin
override fun start(req: StartRequest, callback: (Result<Unit>) -> Unit) {
  // 直接用 req.configPath / req.profileName，没有 cast / null check
}
```
