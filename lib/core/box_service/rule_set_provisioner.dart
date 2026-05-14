import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 把 app bundle 内的 sing-box `.srs` rule-set 文件 copy 到 sing-box working
/// directory，让智能模式分流可以走 `type: local + path: ./<name>.srs`。
///
/// 已有文件 + version 与 bundle 一致时跳过；否则原地覆写。
///
/// 之所以要预 copy：sing-box `type: local` 的 path 是相对 workingDir 解析，
/// 而 workingDir 又不一定是 assets 所在位置（特别是 macOS 沙箱外是 `~/Documents/`、
/// Android 是 app 数据目录）。
class RuleSetProvisioner {
  RuleSetProvisioner();

  static const _files = ['geoip-cn.srs', 'geosite-cn.srs'];
  static const _versionFileName = '.rule-set-version';

  Future<void> ensureProvisioned(Directory workingDir) async {
    if (!await workingDir.exists()) {
      await workingDir.create(recursive: true);
    }

    final bundledVersion = await _loadBundledVersion();
    final versionFile = File('${workingDir.path}/$_versionFileName');
    if (await versionFile.exists()) {
      final existing = (await versionFile.readAsString()).trim();
      if (existing == bundledVersion) {
        return;
      }
    }

    for (final name in _files) {
      final bytes = await rootBundle.load('assets/rule-sets/$name');
      final out = File('${workingDir.path}/$name');
      await out.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      debugPrint(
        '[RuleSetProvisioner] wrote ${out.path} (${bytes.lengthInBytes} bytes)',
      );
    }
    await versionFile.writeAsString(bundledVersion);
  }

  Future<String> _loadBundledVersion() async {
    final raw = await rootBundle.loadString('assets/rule-sets/VERSION');
    return raw.trim();
  }
}
