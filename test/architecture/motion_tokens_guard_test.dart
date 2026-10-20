import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 界面里的**反馈 / 过渡**动画时长一律取 `Motion` 的 token（或
/// `Motion.duration(context, …)`）：这样同一类动效全 App 一个节奏，并且在系统
/// 开了「减少动画」时能一处统一归零。
///
/// 守的是两种写法：`duration: 300.ms`（flutter_animate）和
/// `duration: const Duration(milliseconds: …)`。
///
/// 不在守护范围内的是**产品语义本身带时长**的东西，不是视觉节奏：开屏动画、猫的
/// 呼吸 / 连接动画、业务超时与定时器。它们登记在 [_exempt]，新增条目要写清理由。
void main() {
  const roots = ['lib/features', 'lib/shared', 'lib/app'];

  /// 文件 → 理由。
  const exempt = <String, String>{
    'lib/features/splash/presentation/splash_page.dart': '开屏动画：时长是产品语义',
    'lib/features/home/presentation/sleeping_cat_aura.dart': '呼吸周期，不是反馈',
    'lib/features/home/presentation/speed_cat_connection_mark.dart':
        '连接动画编排，不是反馈',
    'lib/features/logs/application/box_log_stream_provider.dart': '重连间隔，不是动画',
    'lib/app/tray/tray_controller.dart': '退出清理的业务时限',
    'lib/app/update/startup_update_check.dart': '启动后延迟检查，不是动画',
    'lib/features/home/presentation/connection_button.dart': '每秒刷新一次计时，不是动画',
    'lib/shared/components/app_toast.dart': 'toast 停留时长与去重窗口，不是转场',
  };

  final raw = RegExp(
    r'duration:\s*(?:\d+\.ms|const\s+Duration\(\s*(?:milliseconds|seconds):)',
  );

  test('界面动画时长不写死数字，一律走 Motion token', () {
    final offenders = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (exempt.containsKey(path)) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (raw.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '这些位置写死了动画时长，请改用 Motion.short / medium / long（或 '
          'Motion.duration(context, …)）；确属产品语义的登记到 exempt 并写理由',
    );
  });

  test('豁免名单里的文件都还存在（过期条目要删）', () {
    final missing = [
      for (final path in exempt.keys)
        if (!File(path).existsSync()) path,
    ];
    expect(missing, isEmpty);
  });
}
