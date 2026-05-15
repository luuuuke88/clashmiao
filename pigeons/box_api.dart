// ClashMiao sing-box 桥接层 Pigeon 接口定义。
//
// 编辑此文件后跑：
//   dart run pigeon --input pigeons/box_api.dart
// 生成：
//   lib/core/box_service/pigeon/box_api.g.dart
//   android/app/src/main/kotlin/com/clashmiao/clashmiao/pigeon/BoxApi.g.kt
//   ios/Runner/Pigeon/BoxApi.g.swift
//
// Pigeon 替换之前散落 method name 字符串的 MethodChannel，让 Dart ↔
// Kotlin / Swift 调用变成强类型；增删字段编译期就能报错，省去三端
// 手动对齐的成本。

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/box_service/pigeon/box_api.g.dart',
    dartPackageName: 'clashmiao',
    kotlinOut:
        'android/app/src/main/kotlin/com/clashmiao/clashmiao/pigeon/BoxApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.clashmiao.clashmiao.pigeon'),
    swiftOut: 'ios/Runner/Pigeon/BoxApi.g.swift',
  ),
)
/// sing-box 调用入参 / 出参承载体。
class StartRequest {
  StartRequest({required this.configPath, this.profileName = ''});
  final String configPath;
  final String profileName;
}

class ConfigOptions {
  ConfigOptions({required this.jsonOptions});
  final String jsonOptions;
}

class SelectOutboundRequest {
  SelectOutboundRequest({required this.groupTag, required this.outboundTag});
  final String groupTag;
  final String outboundTag;
}

class ValidateConfigRequest {
  ValidateConfigRequest({
    required this.path,
    required this.tempPath,
    this.debug = false,
  });
  final String path;
  final String tempPath;
  final bool debug;
}

class ValidateConfigResult {
  ValidateConfigResult({this.error});

  /// `null` 表示成功；非空字符串为人类可读错误。
  final String? error;
}

/// Dart 调原生：sing-box 生命周期 + 状态变更。
@HostApi()
abstract class BoxHostApi {
  @async
  void init();

  @async
  void setup(String baseDir, String workingDir, String tempDir, bool debug);

  @async
  ValidateConfigResult validateConfig(ValidateConfigRequest req);

  @async
  void changeConfigOptions(ConfigOptions options);

  @async
  void start(StartRequest req);

  @async
  void stop();

  @async
  void restart(StartRequest req);

  @async
  void selectOutbound(SelectOutboundRequest req);

  @async
  void urlTest(String groupTag);

  @async
  String? generateFullConfig(String path);

  @async
  void clearLogs();
}
