import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/data/profile_parser.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:clashmiao/features/profile/widget/profile_qr_dialog.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:dio/dio.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 可控行为的假 BoxService，只重写 generateWarpConfig，其余沿用
/// StubBoxService 的安全空实现。native 不支持的失败路径直接用真实的
/// StubBoxService（它的 generateWarpConfig 本来就抛 UnsupportedError），
/// 这里只需要覆盖成功路径。
class _FakeWarpBoxService extends StubBoxService {
  _FakeWarpBoxService({required this.response});

  final String response;

  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => response;
}

/// toastification 的 toast 自带一个真实 Timer 做自动关闭——跟
/// test/app/app_toast_test.dart 的 `_drainToasts` 用法一致，测试结束前把
/// 它排干，否则框架会断言"还有 pending timer"。
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(StubBoxService()),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const ProfilesPage(),
      ),
    ),
  );
}

Future<void> _pumpProfileAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('ProfilesPage smoke', () {
    testWidgets('空仓库下渲染 + 显示空态文案', (tester) async {
      await tester.pumpWidget(await _host());
      // 等 future provider 解析
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // 顶部页标题（zhCn 翻译）
      expect(find.text('配置文件'), findsOneWidget);
    });

    testWidgets('新增配置入口显示按钮面板', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showProfileFormDialog(context, ref),
                        child: const Text('open-add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('open-add'));
      await _pumpProfileAnimations(tester);

      expect(find.text('新的配置文件'), findsOneWidget);
      expect(find.text('从剪贴板添加'), findsOneWidget);
      expect(find.text('手动输入'), findsOneWidget);
      expect(find.text('添加 WARP'), findsOneWidget);
      expect(find.text('使用 Cloudflare WARP 免费加速'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add_from_clipboard_button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('add_warp_button')), findsOneWidget);
    });

    testWidgets('新增配置里的 WARP 入口打开许可弹窗', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showProfileFormDialog(context, ref),
                        child: const Text('open-add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('open-add'));
      await _pumpProfileAnimations(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();

      expect(find.text('Cloudflare WARP 许可条款'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('同意'), findsOneWidget);
    });

    testWidgets('同意 WARP 条款后真的调用 generateWarpConfig 并写入账号信息（不再是假 toast）', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final fake = _FakeWarpBoxService(
        response: jsonEncode({
          'account-id': 'acc-from-add-warp',
          'access-token': 'token-from-add-warp',
          'config': {'private_key': 'pk'},
        }),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(fake),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showProfileFormDialog(context, ref),
                        child: const Text('open-add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('open-add'));
      await _pumpProfileAnimations(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();

      // 成功后：写入三个凭证字段 + 自动打开 warp 开关 + 成功 toast + 弹窗关闭。
      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, 'acc-from-add-warp');
      expect(settings.warpAccessToken, 'token-from-add-warp');
      expect(jsonDecode(settings.warpWireguardConfig), {'private_key': 'pk'});
      expect(settings.enableWarp, isTrue);
      expect(find.textContaining('WARP 配置生成成功'), findsOneWidget);
      expect(find.text('新的配置文件'), findsNothing);

      await _drainToasts(tester);
    });

    testWidgets('同意 WARP 条款后 native 不支持时优雅报错而不是崩溃（桌面无核心库场景）', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          // StubBoxService.generateWarpConfig 抛 UnsupportedError——模拟桌面
          // 端加载核心库失败回退到桩实现的场景。
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => showProfileFormDialog(context, ref),
                        child: const Text('open-add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('open-add'));
      await _pumpProfileAnimations(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_warp_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();

      expect(find.textContaining('WARP 配置生成失败'), findsOneWidget);
      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, '');
      expect(settings.enableWarp, isFalse);
      // 弹窗还开着，用户可以重试（不像成功路径那样自动关闭）。
      expect(find.text('新的配置文件'), findsOneWidget);

      await _drainToasts(tester);
    });

    testWidgets('手动新增配置显示详情页表单', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () =>
                            showProfileManualFormDialog(context, ref),
                        child: const Text('open-manual'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('open-manual'));
      await _pumpProfileAnimations(tester);

      expect(find.text('配置文件'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('网址'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.clipboard_paste_24_regular),
        findsOneWidget,
      );
    });

    testWidgets('嵌入配置列表的排序按钮打开排序面板', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('排序'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('排序方式'), findsOneWidget);
      expect(find.text('最近更新'), findsOneWidget);
      expect(find.text('按字母顺序'), findsOneWidget);
    });

    testWidgets('嵌入配置列表为空时保持空列表 + 底部操作结构', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value(const [])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('添加'), findsOneWidget);
      expect(find.text('更新全部'), findsOneWidget);
      expect(find.text('排序'), findsOneWidget);
      expect(find.text('暂无配置文件'), findsNothing);
      expect(find.byIcon(FluentIcons.document_add_24_regular), findsNothing);
    });

    testWidgets('长按配置卡打开操作面板', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'test-profile',
        name: '测试配置',
        url: 'https://example.com/sub',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('测试配置'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('分享链接'), findsOneWidget);
      expect(find.text('编辑配置'), findsOneWidget);
      expect(find.text('更新订阅'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ModalBarrier && widget.color == Colors.black54,
        ),
        findsOneWidget,
      );
    });

    testWidgets('本地配置卡和操作面板不显示更新订阅入口', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'local-profile',
        name: '本地导入',
        url: 'content://ss-local',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('本地导入'), findsOneWidget);
      expect(find.byIcon(FluentIcons.shield_24_regular), findsOneWidget);

      await tester.longPress(find.text('本地导入'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('分享链接'), findsOneWidget);
      expect(find.text('编辑配置'), findsOneWidget);
      expect(find.text('更新订阅'), findsNothing);
      expect(find.text('删除'), findsOneWidget);
    });

    test('本地配置分享内容读取配置文件而不是本地 URL', () async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = await Directory.systemTemp.createTemp(
        'profile_share_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      const profile = ProfileEntity(
        id: 'local-profile',
        name: '本地导入',
        url: 'content://ss-local',
        active: true,
      );
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: tempDir,
        prefs: prefs,
        boxService: StubBoxService(),
      );
      final file = File(repo.configFilePath(profile.id));
      await file.parent.create(recursive: true);
      await file.writeAsString('{"outbounds":[]}');

      final content = await profileShareClipboardText(
        profile,
        configFilePath: repo.configFilePath,
      );

      expect(content, '{"outbounds":[]}');
    });

    test('profileShareUrl 给远程订阅 URL 附加 #name fragment（URL-encoded）', () {
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '我的订阅 123',
        url: 'https://example.com/sub?token=abc',
      );

      final shared = profileShareUrl(profile);

      expect(
        shared,
        'https://example.com/sub?token=abc#${Uri.encodeComponent('我的订阅 123')}',
      );
    });

    test('profileShareUrl 本地导入 profile 原样返回 url（不附加 fragment）', () {
      const profile = ProfileEntity(
        id: 'local-profile',
        name: '本地导入',
        url: 'content://ss-local',
      );

      expect(profileShareUrl(profile), 'content://ss-local');
    });

    test('profileShareUrl 名称为空白时不附加 fragment', () {
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '   ',
        url: 'https://example.com/sub',
      );

      expect(profileShareUrl(profile), 'https://example.com/sub');
    });

    test('分享→导入闭环：分享生成的 URL 经 ProfileParser 解析能拿到同一个订阅名', () {
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '我的订阅 123',
        url: 'https://example.com/sub',
      );

      final shared = profileShareUrl(profile);
      final parsed = ProfileParser.parse(shared, {});

      expect(parsed.name, '我的订阅 123');
    });

    testWidgets('长按远程配置卡点击分享链接把带名称 fragment 的 URL 写入剪贴板', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '我的订阅',
        url: 'https://example.com/sub',
        active: true,
      );
      // 分享远程订阅走不到 configFilePath（_isRemoteProfile 分支直接返回
      // profileShareUrl），这里只是为了让 profileRepositoryProvider 能在
      // widget test 里瞬间 resolve，不走真实的
      // getApplicationDocumentsDirectory()（没有 mock 平台通道会一直挂起）。
      // 用一个不存在也不会被访问的路径构造 Directory——注意不能用
      // `Directory.systemTemp.createTemp(...)`：那是真实 dart:io 异步 I/O，
      // testWidgets 的测试体默认跑在 FakeAsync zone 里（tester.pump 靠它
      // 快进动画/Timer），真实 IO 的完成回调在这个 zone 里等不到会一直
      // 挂起（除非用 tester.runAsync 逃出去，见
      // profile_details_page_save_test.dart 的 `_withRealNetwork` 注释）。
      // `Directory(path)` 构造函数本身是纯同步的，不会遇到这个问题。
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: Directory('/tmp/unused-profile-share-link-test'),
        prefs: prefs,
        boxService: StubBoxService(),
      );

      // Clipboard.setData/getData 走 SystemChannels.platform，flutter_test
      // 默认不 mock 这条通道（跟 test/core/haptic/haptic_service_test.dart
      // 里 HapticFeedback 需要手动 mock 是同一个原因）——不注册的话
      // Clipboard 调用会一直挂起、测试永远跑不完。这里用一个内存变量模拟
      // 真实剪贴板的读写行为。
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardText = (call.arguments as Map)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                return {'text': clipboardText};
              default:
                return null;
            }
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
          profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('我的订阅'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('分享链接'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(
        clipboard?.text,
        'https://example.com/sub#${Uri.encodeComponent('我的订阅')}',
      );
      expect(find.text('订阅链接已复制'), findsOneWidget);

      await _drainToasts(tester);
    });

    testWidgets('长按远程配置卡点击分享二维码弹出二维码弹窗且内容是带名称 fragment 的订阅 URL', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '我的订阅',
        url: 'https://example.com/sub',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('我的订阅'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('订阅链接二维码'), findsOneWidget);

      await tester.tap(find.text('订阅链接二维码'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProfileQrDialog), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final qrDialog = tester.widget<ProfileQrDialog>(
        find.byType(ProfileQrDialog),
      );
      expect(
        qrDialog.data,
        'https://example.com/sub#${Uri.encodeComponent('我的订阅')}',
      );
      expect(qrDialog.profileName, '我的订阅');
    });

    testWidgets('本地配置操作面板不显示分享二维码入口', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'local-profile',
        name: '本地导入',
        url: 'content://ss-local',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('本地导入'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('分享链接'), findsOneWidget);
      expect(find.text('订阅链接二维码'), findsNothing);
    });

    testWidgets('配置卡编辑按钮打开详情页', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '远程订阅',
        url: 'https://example.com/sub',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const Scaffold(body: ProfilesPage(embedInSheet: true)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(FluentIcons.edit_20_regular));
      await _pumpProfileAnimations(tester);

      expect(find.byType(ProfileDetailsPage), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('详情页远程订阅显示基础信息、订阅状态和选项', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final profile = ProfileEntity(
        id: 'remote-profile',
        name: '远程订阅',
        url: 'https://example.com/sub',
        active: true,
        subInfo: SubscriptionInfo(
          upload: 1024 * 1024 * 1024,
          download: 3 * 1024 * 1024 * 1024,
          total: 10 * 1024 * 1024 * 1024,
          expire: DateTime(2026, 12, 31),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ProfileDetailsPage('remote-profile'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('配置文件'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('订阅状态'), findsOneWidget);
      expect(find.text('选项'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.byIcon(FluentIcons.tag_24_regular), findsNothing);
      expect(find.byIcon(FluentIcons.link_24_regular), findsNothing);
    });

    testWidgets('详情页远程配置无订阅状态时隐藏订阅状态和选项', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'remote-profile',
        name: '远程订阅',
        url: 'https://example.com/sub',
        active: true,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ProfileDetailsPage('remote-profile'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('配置文件'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('订阅状态'), findsNothing);
      // 选项区标题不再随 subInfo 隐藏：Mux 开关对本地/远程配置一视同仁（控制器修正，
      // 见 Task 12.2），即使远程配置还没有 subInfo 也要能看到并切换 Mux。
      expect(find.text('选项'), findsOneWidget);
      expect(find.text('立即更新'), findsNothing);
      expect(find.text('Mux 多路复用'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });

    testWidgets('详情页自动更新打开输入弹窗', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final profile = ProfileEntity(
        id: 'remote-profile',
        name: '远程订阅',
        url: 'https://example.com/sub',
        active: true,
        updateInterval: const Duration(hours: 6),
        subInfo: SubscriptionInfo(
          upload: 1024,
          download: 2048,
          total: 4096,
          expire: DateTime(2026, 12, 31),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
          profileListProvider.overrideWith((_) => Future.value([profile])),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ProfileDetailsPage('remote-profile'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('自动更新'));
      await _pumpProfileAnimations(tester);

      await tester.tap(find.text('自动更新'));
      await _pumpProfileAnimations(tester);

      expect(find.text('自动更新间隔（小时）'), findsWidgets);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('禁用'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });
  });
}
