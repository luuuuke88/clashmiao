import 'dart:io';

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
