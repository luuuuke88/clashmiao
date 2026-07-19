import 'dart:io';

import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 应用数据目录
class AppDirectories {
  const AppDirectories({
    required this.baseDir,
    required this.workingDir,
    required this.tempDir,
  });

  /// 应用主目录
  final Directory baseDir;

  /// 工作目录（配置文件、数据库等）
  final Directory workingDir;

  /// 临时目录
  final Directory tempDir;
}

/// sing-box 运行时文件（provisioned 的 .srs rule-set、每次 connect 现场拼的
/// runtime-config.json）应该落地的目录。
///
/// 背景：iOS 上 Runner 主 App 和 packet-tunnel extension 是两个独立沙盒进程。
/// `RuntimeConfigBuilder` 往生成的 config JSON 里嵌的 rule_set 绝对路径最终
/// 要交给 extension 进程去读，只有 App Group 共享容器两边都能访问——
/// `path_provider` 的 `getApplicationDocumentsDirectory()` 拿到的是 Runner
/// 私有沙盒，extension 看不到，会导致"智能模式"分流规则静默失效（表现得
/// 跟全局模式一样）。所以 iOS 换一条路径来源：查询原生侧
/// `BoxHostApi.getAppGroupWorkingDirectory()`。
///
/// 其它平台（Android / 桌面）是单进程模型，`getApplicationDocumentsDirectory()`
/// 本身没问题，维持原状。
///
/// `lib/main.dart`（首次 provision rule-set）和
/// `lib/core/providers/app_providers.dart`（每次 connect/reconnect 现场拼
/// runtime-config.json）共用这一个函数，避免两处各自计算出不一致的目录
/// ——这正是本次修复之前的 bug 根源之一。
Future<Directory> resolveSingBoxWorkingDirectory() {
  return resolveSingBoxWorkingDirectoryImpl(
    isIOS: Platform.isIOS,
    getAppGroupPath: () => pigeon.BoxHostApi().getAppGroupWorkingDirectory(),
    getDocumentsDirectory: getApplicationDocumentsDirectory,
  );
}

/// [resolveSingBoxWorkingDirectory] 的可测试实现：所有平台判断 / IO 都通过参数
/// 注入，单测里不需要真的跑在 iOS 上或者真的起一个 method channel mock，
/// 直接断言"iOS 分支调用了 getAppGroupPath 而不是 getDocumentsDirectory"
/// （反之亦然）即可。同一套模式见 `lib/main.dart` 的
/// `bootstrapSentryGatedApp` / `test/main_test.dart`。
@visibleForTesting
Future<Directory> resolveSingBoxWorkingDirectoryImpl({
  required bool isIOS,
  required Future<String> Function() getAppGroupPath,
  required Future<Directory> Function() getDocumentsDirectory,
}) async {
  if (isIOS) {
    final path = await getAppGroupPath();
    return Directory(path);
  }
  return getDocumentsDirectory();
}
