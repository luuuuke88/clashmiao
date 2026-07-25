import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/app/router/app_router.dart';
import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

import '../../support/fake_box_service.dart';

/// `test/core/shortcuts/desktop_shortcuts_test.dart` 及其拆分出去的几个
/// `desktop_shortcuts_paste_*_test.dart` 共用的测试基础设施。
///
/// 涉及真实 toast 渲染断言（`find.textContaining(...)`）的几个用例被拆成了
/// 独立文件而不是放在同一个 `main()` 里：`flutter test` 对每个测试文件起
/// 独立 isolate，但同一个文件内多个 `testWidgets` 顺序执行、共享同一个
/// isolate；实测 toastification 包内部的全局 Overlay 状态
/// （`findToastificationOverlayState()`）在同一 isolate 里连续
/// `pumpWidget` 多棵独立的 `ToastificationWrapper` 树时，第二棵开始就找不到
/// 正确的 Overlay（这是 toastification 包自身的已知限制，不是被测代码的
/// 问题）——同一文件里第一个用到 toast 断言的测试总是通过，后面的全部因为
/// "找不到 toast 文案"失败，与具体测什么无关，纯粹是执行顺序。拆成独立文件
/// 让每个 toast 断言各自独享一个全新 isolate，规避这个限制。

/// 起一个一次性 HTTP server，模拟订阅响应。
Future<HttpServer> serveOnce(String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen((req) async {
    req.response.write(body);
    await req.response.close();
  });
  return server;
}

const validSingBoxJsonBody = '''
{
  "outbounds": [
    {"type": "selector", "tag": "p", "outbounds": []}
  ],
  "inbounds": [
    {"type": "mixed", "listen_port": 2080}
  ],
  "route": {"rules": []}
}
''';

/// 只重写 [validateConfig] 且**不**继承 [StubBoxService] 的假 BoxService——
/// `ProfileRepository._normalizeAndWrite` 对 `boxService is StubBoxService`
/// 有特判（跳过 native 校验直接写原文），如果这里继续 extends StubBoxService，
/// `is` 判断依然为真，测不出"native 校验失败"这条路径。用于验证"剪贴板内容
/// 不像有效订阅"时全局快捷键必须给出清晰的失败反馈，而不是静默成功。
class RejectingBoxService extends FakeBoxService {
  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async => '不是合法的订阅内容';
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String path) => const Stream.empty();
}

/// toastification 的 toast 自带真实 Timer 做自动关闭，测试结束前排干，
/// 否则框架会断言"还有 pending timer"（同 profiles_page_test.dart 写法）。
Future<void> drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Clipboard.getData/setData 走 SystemChannels.platform，flutter_test 默认
/// 不 mock，需要手动注册，否则调用会一直挂起。调用方需要自己的 `tester` 来自
/// 一个 `testWidgets` 回调，这里用 `addTearDown`（全局测试生命周期钩子）注册
/// 清理，不需要额外传参。
void mockClipboard(WidgetTester tester, {String? text}) {
  String? clipboardText = text;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardText = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return clipboardText == null ? null : {'text': clipboardText};
          default:
            return null;
        }
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}

/// 搭一个真实可用的 widget 树：`DesktopShortcutsWrapper` 包在
/// `MaterialApp(navigatorKey: appRouterNavigatorKey, ...)` **外面**，跟生产
/// 环境 `main.dart` 里 `DesktopShortcutsWrapper(child: ClashMiaoApp())` 的
/// 嵌套关系一致——这个嵌套顺序是"文本框焦点区分"能生效的关键（见
/// `desktop_shortcuts.dart` 顶部文档：`DefaultTextEditingShortcuts` 嵌在
/// `MaterialApp` 内部，必须比这里的全局 wrapper 更靠近文本框，顺序反了的话
/// 测试就测不出真实生产行为）。`appRouterNavigatorKey` 是
/// `defaultPasteImport` 拿 BuildContext 的唯一入口。
///
/// [home] 的内容外面包一层 `Focus(autofocus: true, ...)`：桌面按键事件走
/// Flutter 的 FocusNode 祖先链分发，如果整棵树完全没有任何节点持有焦点，
/// 按键无处可分发，测不出"焦点不在任何输入框时快捷键应该生效"这条场景；
/// autofocus 只在没人显式要焦点时兜底生效，[home] 里的 `TextField` 被
/// tap 之后会正常抢过焦点，两者不冲突。
Future<ProviderContainer> pumpShortcuts(
  WidgetTester tester, {
  required ProviderContainer container,
  Widget? home,
  Future<void> Function(WidgetRef ref)? onPasteImport,
  Future<void> Function(WidgetRef ref)? onCloseWindow,
  void Function(WidgetRef ref)? onOpenSettings,
  Future<void> Function(WidgetRef ref)? onQuitApp,
  bool? isMacOS,
  bool? isLinux,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: DesktopShortcutsWrapper(
        onPasteImport: onPasteImport,
        onCloseWindow: onCloseWindow,
        onOpenSettings: onOpenSettings,
        onQuitApp: onQuitApp,
        isMacOS: isMacOS,
        isLinux: isLinux,
        child: ToastificationWrapper(
          child: MaterialApp(
            navigatorKey: appRouterNavigatorKey,
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: Focus(
              autofocus: true,
              child: home ?? const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// 反复小步真实 pump，直到 [finder] 能找到东西或者到达超时。
///
/// 光 await 完 `defaultPasteImport` 的 Future 还不够——toastification 插入
/// Overlay entry 之后，实际把文案渲染进树里还要再等几帧（内部动画
/// controller 的初始化 + build 不是一次 `tester.pump()` 就能落地，实测两次
/// 固定 pump 不够、需要多轮），所以哪怕已经知道异步操作本身已经 resolve，
/// 还是要循环多 pump 几次，比一次性等一个固定 Duration 更稳。
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxIterations = 20,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pressPaste(WidgetTester tester, {required bool meta}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(modifier);
}
