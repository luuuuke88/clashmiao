import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/model/advanced_config.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

const _remoteProfile = ProfileEntity(
  id: 'remote-profile',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
  updateInterval: Duration(hours: 12),
  subInfo: SubscriptionInfo(
    upload: 256 * 1024 * 1024,
    download: 256 * 1024 * 1024,
    total: 2 * 1024 * 1024 * 1024,
    expire: null,
  ),
);

const _localProfile = ProfileEntity(
  id: 'local-profile',
  name: '本地导入',
  url: 'content://local-node',
  active: false,
);

const _remoteProfileWithAdvanced = ProfileEntity(
  id: 'remote-profile-advanced',
  name: '测试订阅（高级）',
  url: 'https://example.com/sub-advanced',
  active: true,
  updateInterval: Duration(hours: 6),
  customUserAgent: 'ClashMiaoTest/1.0',
  advancedConfig: AdvancedConfig(muxEnabled: true),
  subInfo: SubscriptionInfo(
    upload: 10 * 1024 * 1024,
    download: 10 * 1024 * 1024,
    total: 1024 * 1024 * 1024,
    expire: null,
  ),
);

Future<Widget> _host({
  required ProfileEntity profile,
  bool debugOpenUpdateInterval = false,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(StubBoxService()),
      profileListProvider.overrideWith((_) => Future.value([profile])),
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileListProvider.future);
  await container.read(activeProfileProvider.future);

  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          // 测试环境的 shader 编译与 Material 3 默认的 InkSparkle 水波纹特效不兼容
          // （"ink_sparkle.frag ... Unsupported runtime stages format version"），
          // 仅在 widget test 里换成不依赖 fragment shader 的 splashFactory，不影响
          // 真机渲染（真机不经过这份测试专用 ThemeData）。
          splashFactory: NoSplash.splashFactory,
        ),
        home: ProfileDetailsPage(
          profile.id,
          debugOpenUpdateInterval: debugOpenUpdateInterval,
        ),
      ),
    ),
  );
}

void main() {
  group('ProfileDetailsPage UI', () {
    testWidgets('远程配置渲染详情页基础信息、订阅状态和选项区', (tester) async {
      await tester.pumpWidget(await _host(profile: _remoteProfile));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('配置文件'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('测试订阅'), findsOneWidget);
      expect(find.text('网址'), findsOneWidget);
      expect(find.text('https://example.com/sub'), findsOneWidget);
      expect(find.text('订阅状态'), findsOneWidget);
      expect(find.text('流量使用'), findsOneWidget);
      expect(find.text('上传'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('到期时间'), findsOneWidget);
      expect(find.text('无限期'), findsOneWidget);
      expect(find.text('选项'), findsOneWidget);
      expect(find.text('自动更新'), findsOneWidget);
      expect(find.text('12 小时'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });

    testWidgets('本地配置保持基础信息 + 删除结构 + Mux 开关，不显示远程订阅选项', (tester) async {
      await tester.pumpWidget(await _host(profile: _localProfile));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('配置文件'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('本地导入'), findsOneWidget);
      expect(find.text('网址'), findsNothing);
      expect(find.text('订阅状态'), findsNothing);
      expect(find.text('立即更新'), findsNothing);
      expect(find.text('User-Agent'), findsNothing);
      expect(find.text('删除'), findsOneWidget);

      // 控制器修正：Mux 开关放在 remote-only 门（_isRemoteProfile && subInfo != null）
      // 之外，本地导入配置也应能看到并切换；User-Agent 保持仅远程订阅可见（已在上面断言
      // findsNothing）。
      expect(find.text('选项'), findsOneWidget);
      expect(find.text('Mux 多路复用'), findsOneWidget);
      final muxSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(muxSwitch.value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('自动更新间隔打开输入弹层', (tester) async {
      await tester.pumpWidget(
        await _host(profile: _remoteProfile, debugOpenUpdateInterval: true),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('自动更新间隔（小时）'), findsWidgets);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('禁用'), findsOneWidget);
    });

    testWidgets('选项区显示已有的 User-Agent 与已开启的 Mux', (tester) async {
      await tester.pumpWidget(await _host(profile: _remoteProfileWithAdvanced));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('User-Agent'), findsOneWidget);
      expect(find.text('ClashMiaoTest/1.0'), findsOneWidget);
      expect(find.text('Mux 多路复用'), findsOneWidget);
      final muxSwitch = tester.widget<Switch>(find.byType(Switch));
      expect(muxSwitch.value, isTrue);
    });

    testWidgets('未设置 User-Agent 显示占位文案，可编辑 UA 与切换 Mux', (tester) async {
      // 选项区新增 UA + Mux 两个 tile 后单页内容变高，默认 800x600 测试视口放不下
      // Switch 与弹层里的 OK 按钮，会导致 tap() 因目标不在可视区域内而 hit-test 失败；
      // 保持默认宽度、大幅加高视口，让整页 + 底部弹层都完整落在可视区域内。
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _host(profile: _remoteProfile));
      await tester.pump(const Duration(milliseconds: 250));

      // _remoteProfile 没有 customUserAgent / advancedConfig，应显示占位与默认关
      expect(find.text('未设置'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // 切换 Mux
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // 编辑 User-Agent：tap 打开 SettingsInputDialog<String>，输入新值，确认
      await tester.tap(find.text('User-Agent'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextFormField), 'NewUA/2.0');
      // 底部弹层的滑入过渡与键盘 viewInsets 变化混在一起，OK 按钮的命中点在动画
      // 结算前会被计算偏出可视区域；tap 本身仍然生效（下面的断言可验证），这里显式
      // 关闭 warnIfMissed 只是为了不在测试输出里留一条误导性的"未命中"警告。
      await tester.tap(find.text('OK'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('NewUA/2.0'), findsOneWidget);
    });
  });
}
