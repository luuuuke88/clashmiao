import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_box_service.dart';
import '../../../support/fake_connection_controller.dart';

class _SpyBoxService extends FakeBoxService {
  // 其余方法在本测试里不会被触发，给最小实现避免编译错。
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

void main() {
  // 迁移说明：原来这条还断言 `changeConfigOptions` 被调用——那是「先把 options
  // 推给内核全局状态」的旧做法。现在 options 内联在每个启动请求里（见
  // connection_launcher_test：模式变化 → options 与 revision 都变化），切换模式
  // 只需要让控制器重新应用配置；未连接时它是无副作用的空操作。
  testWidgets('点击切换到「全局」 → proxyMode 更新 + 通知控制器重新应用配置', (tester) async {
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
        connectionControllerProvider.overrideWith(FakeConnectionController.new),
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
    // 等动画 + async updateMode
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 状态 + 控制器调用双重断言
    expect(container.read(proxyModeProvider), 0);
    expect(
      (container.read(connectionControllerProvider.notifier)
              as FakeConnectionController)
          .applyConfigCalls,
      1,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '选中项用 primaryContainer / onPrimaryContainer 成对角色，且带 selected 语义（$brightness）',
      (tester) async {
        // 原来选中项填的是 colorScheme.surface：深色主题下它比底槽还暗，
        // 选中跟没选中只差一点字重，真机上根本分不出来。
        SharedPreferences.setMockInitialValues({
          'locale': 'zhCn',
          'clashmiao_proxy_mode': 1,
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(_SpyBoxService()),
            connectionControllerProvider.overrideWith(
              FakeConnectionController.new,
            ),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        final isDark = brightness == Brightness.dark;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  isDark ? AiUiTheme.dark : AiUiTheme.light,
                ],
              ),
              home: const Scaffold(body: ModeSelectorForTest()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final t = container.read(translationsProvider);
        BoxDecoration fillOf(String label) =>
            tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text(label),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        Color? textColorOf(String label) => tester
            .widget<DefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(DefaultTextStyle),
                  )
                  .first,
            )
            .style
            .color;

        final smart = t.home.routingMode.smart;
        final global = t.home.routingMode.global;
        final scheme = Theme.of(
          tester.element(find.byType(Scaffold)),
        ).colorScheme;
        expect(fillOf(smart).color, scheme.primaryContainer);
        expect(textColorOf(smart), scheme.onPrimaryContainer);
        expect(fillOf(global).color!.a, 0);

        // 语义：选中项 selected，另一项不是；两项都是按钮。
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.text(smart)),
          isSemantics(isSelected: true, isButton: true),
        );
        expect(
          tester.getSemantics(find.text(global)),
          isSemantics(
            isSelected: false,
            hasSelectedState: true,
            isButton: true,
          ),
        );
        handle.dispose();
      },
    );
  }
}
