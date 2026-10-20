import 'dart:io';

import 'package:clashmiao/app/bootstrap/restore_wiring.dart';
import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/features/settings/application/app_filter_notifier.dart';
import 'package:clashmiao/features/settings/application/setting_toggles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('恢复后要失效的 feature 层 provider 清单包含全部读偏好的那几个', () {
    final targets = restoreExtraInvalidations();
    expect(
      targets,
      containsAll(<Object>[
        boolPreferenceProvider,
        appFilterProvider,
        proxiesSortProvider,
      ]),
    );
  });

  test('覆盖项把清单注入根容器，refresher 能读到', () {
    final container = ProviderContainer(overrides: restoreWiringOverrides());
    addTearDown(container.dispose);
    expect(
      container.read(restoreExtraInvalidationsProvider),
      restoreExtraInvalidations(),
    );
  });

  test('没有接线时默认清单为空（features/config 不依赖其它 feature）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(restoreExtraInvalidationsProvider), isEmpty);
  });

  // `main()` 本身没法在单测里跑；沿用 storage_bootstrap_test 的做法，对源码做断言，
  // 防止有人改 main.dart 时把恢复接线悄悄删掉。
  test('main.dart 接了：恢复标记检查、feature 层失效清单、定时刷新暂停', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('checkRestoreMarker: checkRestoreMarkerAtStartup'));
    expect(main, contains('overrides: restoreWiringOverrides(),'));
    expect(
      main,
      contains('isPaused: () => container.read(restoreInProgressProvider)'),
    );
    expect(
      main,
      contains(
        'startupRestoreRecoveryProvider.notifier).state =\n      lastRestoreRecoveryOutcome',
      ),
      reason: '启动恢复结果要交给界面提示',
    );
  });
}
