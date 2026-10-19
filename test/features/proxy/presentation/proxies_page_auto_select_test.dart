import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_box_service.dart';

/// 「自动选择」卡只在订阅里真有自动选择组时才出现。没有时它曾经照样画出来，
/// 点了只会弹一条「没有节点」的错误——一个必定失败的假入口。
class _SpyBoxService extends FakeBoxService {
  final List<(String, String)> selectCalls = [];

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {
    selectCalls.add((groupTag, outboundTag));
  }

  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

const _profile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

const _nodeA = OutboundProxy(tag: 'node-a', type: 'shadowsocks');
const _nodeB = OutboundProxy(tag: 'node-b', type: 'shadowsocks');

Future<_SpyBoxService> _pumpPage(
  WidgetTester tester, {
  required List<OutboundGroup> groups,
  bool connected = true,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final spy = _SpyBoxService();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _profile),
      boxServiceProvider.overrideWithValue(spy),
      offlineProxyGroupsProvider.overrideWith((_) async => groups),
      // 已连接时内核推送同一份实时分组：选择只对实时分组发起。
      if (connected)
        outboundGroupsProvider.overrideWith((_) => Stream.value(groups)),
      isConnectedProvider.overrideWith((_) => connected),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const ProxiesPage(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  return spy;
}

Future<void> _drainToasts(WidgetTester tester) async {
  // 已连接、有实时分组时测速协调器有 2 s 预热与 10 s 一轮的定时器：推过去。
  await tester.pump(const Duration(seconds: 13));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('订阅里没有自动选择组：不构建自动选择卡，节点照常列出', (tester) async {
    await _pumpPage(
      tester,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'node-a',
          items: [_nodeA, _nodeB],
        ),
      ],
    );

    expect(find.text('自动选择'), findsNothing);
    expect(find.text('自动连接到最快的节点'), findsNothing);
    expect(find.byIcon(FluentIcons.flash_24_filled), findsNothing);
    // 不再把列表第 0 项让给卡片：两个节点一个不少。
    expect(find.text('node-a'), findsOneWidget);
    expect(find.text('node-b'), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('订阅里有 urltest 自动选择组：卡片出现，点击选中它，且它不再作为普通节点重复列出', (tester) async {
    final spy = await _pumpPage(
      tester,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'node-a',
          items: [
            OutboundProxy(tag: 'auto-group', type: 'urltest'),
            _nodeA,
            _nodeB,
          ],
        ),
      ],
    );

    expect(find.text('自动选择'), findsOneWidget);
    expect(find.text('自动连接到最快的节点'), findsOneWidget);
    expect(find.text('node-a'), findsOneWidget);
    expect(find.text('node-b'), findsOneWidget);
    // 自动选择组本身的 tag 不当作普通节点再画一遍。
    expect(find.text('auto-group'), findsNothing);

    await tester.tap(find.text('自动选择'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectCalls, [('proxy', 'auto-group')]);
    await _drainToasts(tester);
  });

  testWidgets('tag 叫 auto 的条目同样被识别为自动选择组（兜底分支）', (tester) async {
    final spy = await _pumpPage(
      tester,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'auto',
          items: [
            _nodeA,
            OutboundProxy(tag: 'auto', type: 'selector'),
          ],
        ),
      ],
    );

    expect(find.text('自动选择'), findsOneWidget);
    // 当前选中的就是它：显示对勾，而不是箭头。
    expect(find.byIcon(FluentIcons.checkmark_24_filled), findsWidgets);

    await tester.tap(find.text('自动选择'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(spy.selectCalls, [('proxy', 'auto')]);
    await _drainToasts(tester);
  });
}
