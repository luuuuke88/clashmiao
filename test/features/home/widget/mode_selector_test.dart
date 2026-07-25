import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_box_service.dart';

class _SpyBoxService extends FakeBoxService {
  int changeConfigOptionsCalls = 0;
  String? lastJsonOptions;

  @override
  Future<void> changeConfigOptions(String jsonOptions) async {
    changeConfigOptionsCalls++;
    lastJsonOptions = jsonOptions;
  }

  // 其余方法在本测试里不会被触发，给最小实现避免编译错。
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

void main() {
  testWidgets('点击切换到「全局」 → proxyMode 更新 + changeConfigOptions 触发', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      'clashmiao_proxy_mode': 1, // 默认智能
    });
    final prefs = await SharedPreferences.getInstance();
    final spy = _SpyBoxService();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(spy),
      ],
    );
    await container.read(sharedPreferencesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const Scaffold(body: ModeSelectorForTest()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 初始：智能（index=1）
    expect(container.read(proxyModeProvider), 1);

    // 走当前 locale 的翻译：之前写死 '全局' 没多语言，现在走 t.home.routingMode.global
    final t = container.read(translationsProvider);
    final globalLabel = find.text(t.home.routingMode.global);
    expect(globalLabel, findsOneWidget);

    await tester.tap(globalLabel);
    // 等动画 + async changeConfigOptions
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 状态 + spy 双重断言
    expect(container.read(proxyModeProvider), 0);
    expect(spy.changeConfigOptionsCalls, 1);
    expect(spy.lastJsonOptions, contains('"execute-config-as-is":true'));
  });
}
