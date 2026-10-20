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
  SelectOutboundRequest({
    required this.groupTag,
    required this.outboundTag,
    this.expectedAttempt,
  });
  final String groupTag;
  final String outboundTag;

  /// 手选重放时传入目标 attempt（连接生命周期 spec §10.7）。非空且与协调器
  /// 当前 attempt 不一致时，原生**不写入**并以 `FlutterError("stale")` 回调；
  /// 为空则维持旧行为（不校验）。
  final int? expectedAttempt;
}

/// `KernelSnapshotMsg.lastFailure`：协调器把 desired 置 off 时附带的失败。
class KernelFailureMsg {
  KernelFailureMsg({
    required this.code,
    required this.message,
    required this.attempt,
    this.seq,
  });

  /// 失败码（字符串，见 Dart `KernelFailureCode`；未知码按 unexpected 处理）。
  final String code;
  final String message;
  final int attempt;

  /// 触发该失败的请求序号；与 Dart 请求无关的失败（内核意外退出等）为空。
  final int? seq;
}

/// 内核权威快照（连接生命周期 spec §2 + §10.5）。
///
/// 枚举字段用小写字符串，与事件通道 `com.clashmiao.app/kernel.snapshot` 的
/// JSON map 载荷逐字段一致：
///   - `status`: stopped | starting | started | stopping
///   - `desired`: on | off
///   - `source`: app | tile | shortcut | boot | system
class KernelSnapshotMsg {
  KernelSnapshotMsg({
    required this.epoch,
    required this.version,
    required this.status,
    required this.attempt,
    required this.desired,
    required this.source,
    required this.appliedSeq,
    required this.selectionsReplayNeeded,
    this.activeConfigRevision,
    this.lastFailure,
    this.retainedConfigPaths,
  });
  final String epoch;
  final int version;
  final String status;
  final int attempt;
  final String desired;
  final String source;
  final int appliedSeq;
  final int? activeConfigRevision;
  final KernelFailureMsg? lastFailure;
  final bool selectionsReplayNeeded;

  /// 原生之后可能还会读取的运行时配置文件路径（持久化 spec、当前意图、运行中、
  /// 在途启动）。为空 = 未知：Dart 不得删除任何运行时配置文件。
  /// 原生与 Dart 总在同一个二进制里发布，所以 Pigeon 查询响应必然带这个尾字段
  /// （不存在「旧原生 + 新 Dart」的组合，生成的解码不做缺字段兼容）。
  final List<String>? retainedConfigPaths;
}

/// 启动/重载所需的不可变产物（每请求独立）。
class LaunchSpecMsg {
  LaunchSpecMsg({
    required this.runtimeConfigPath,
    required this.optionsJson,
    required this.profileName,
    required this.configRevision,
  });
  final String runtimeConfigPath;
  final String optionsJson;
  final String profileName;
  final int configRevision;
}

/// Dart → 协调器的带序号期望请求。
class DesiredRequestMsg {
  DesiredRequestMsg({
    required this.epoch,
    required this.seq,
    required this.desired,
    required this.reason,
    this.launch,
  });

  /// Dart 据以分配 seq 的纪元；与协调器当前纪元不符时回执 `wrongEpoch`。
  final String epoch;
  final int seq;

  /// `on` | `off`
  final String desired;

  /// `userConnect` | `userDisconnect` | `applyConfig` | `retry`
  final String reason;

  /// `desired == on` 时必填。
  final LaunchSpecMsg? launch;
}

/// 请求回执：只表示「已入队/被拒绝」，不表示完成。
class ReceiptMsg {
  ReceiptMsg({
    required this.accepted,
    required this.epoch,
    required this.appliedSeq,
    this.reason,
  });
  final bool accepted;

  /// 被拒绝时：`stale`（seq ≤ appliedSeq）| `wrongEpoch`；受理时为空。
  final String? reason;

  /// 协调器当前纪元。
  final String epoch;

  /// 处理本请求之后的 appliedSeq（拒绝时即现值，供 Dart 重设基线）。
  final int appliedSeq;
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

class InstalledApp {
  InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
  });
  final String packageName;
  final String appName;
  final bool isSystemApp;
}

/// Dart 调原生：sing-box 生命周期 + 状态变更。
@HostApi()
abstract class BoxHostApi {
  @asyncCallback
  void initialize();

  @asyncCallback
  void setup(String baseDir, String workingDir, String tempDir, bool debug);

  @asyncCallback
  ValidateConfigResult validateConfig(ValidateConfigRequest req);

  @asyncCallback
  void changeConfigOptions(ConfigOptions options);

  @asyncCallback
  void start(StartRequest req);

  @asyncCallback
  void stop();

  @asyncCallback
  void restart(StartRequest req);

  @asyncCallback
  void selectOutbound(SelectOutboundRequest req);

  /// 当前权威快照（连接生命周期 spec §2）。Android 由进程级协调器提供；
  /// iOS 无原生实现，Dart 使用 `EmulatedKernelPort`。
  @asyncCallback
  KernelSnapshotMsg getSnapshot();

  /// 提交带序号的期望请求。回调只表示入队/被拒绝（见 [ReceiptMsg]）；
  /// 失败一律 `Result.failure(FlutterError)`，不 throw。
  @asyncCallback
  ReceiptMsg request(DesiredRequestMsg req);

  /// 确认 [attempt] 的手选重放已完成。幂等：attempt 不是当前值时忽略。
  @asyncCallback
  void acknowledgeReplay(int attempt);

  @asyncCallback
  void urlTest(String groupTag);

  @asyncCallback
  String? generateFullConfig(String path);

  @asyncCallback
  void clearLogs();

  @asyncCallback
  List<InstalledApp> getInstalledApps();

  @asyncCallback
  String? getAppIconBase64(String packageName);

  @asyncCallback
  void resetTunnel();

  /// iOS 专用：查询 App Group 共享容器内、sing-box 运行时文件（provisioned 的
  /// .srs rule-set、每次 connect 现场拼的 runtime-config.json）应该落地的目录。
  ///
  /// 背景：iOS 上 Runner 主 App 和 packet-tunnel extension 是两个独立沙盒
  /// 进程；`RuntimeConfigBuilder` 往生成的 config JSON 里嵌的 rule_set 绝对
  /// 路径最终要被 extension 进程读取，只有 App Group 共享容器两边都能访问
  /// （`path_provider` 的 `getApplicationDocumentsDirectory()` 拿到的是
  /// Runner 私有沙盒，extension 看不到）。
  ///
  /// Dart 侧只有 iOS 分支会调用这个方法（见
  /// `lib/core/box_service/model/directories.dart` 的 `resolveSingBoxWorkingDirectory`）；
  /// Android 走 `path_provider` 就够（单进程模型，没有这个问题），这里的
  /// Android 实现只是为了满足接口契约，返回值不会被 Dart 消费。
  @asyncCallback
  String getAppGroupWorkingDirectory();
}
