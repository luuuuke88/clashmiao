import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shortcuts_test_support.dart';

/// 全局桌面快捷键（`lib/core/shortcuts/desktop_shortcuts.dart`）的 TDD 覆盖：
/// - 焦点在文本输入框时按 Cmd/Ctrl+V 必须走正常文本粘贴，不能被全局快捷键
///   吞掉（这是回归测试的重点，见下面 group('文本输入框焦点区分')）。
/// - Cmd+W / Cmd+, / Ctrl+Q 的按键 → Intent → Action 映射，以及三者的平台
///   门控（宿主机是 macOS，所以用 [DesktopShortcutsWrapper] 的
///   `isMacOS`/`isLinux` 注入参数显式覆盖，两个方向都要测到）。
///
/// Cmd/Ctrl+V 快速粘贴导入本身（成功 / 剪贴板为空 / 导入失败三条反馈路径）
/// 拆到了同目录下 `desktop_shortcuts_paste_*_test.dart` 四个独立文件里，见
/// `desktop_shortcuts_test_support.dart` 头部文档说明原因（toastification
/// 包在同一 isolate 里连续 pumpWidget 多棵 ToastificationWrapper 树时的已知
/// 限制）。
void main() {
  group('文本输入框焦点区分（防止吞掉正常粘贴，最容易引入的回归）', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(const StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
    });

    tearDown(() => container.dispose());

    /// `flutter test` 默认把 `defaultTargetPlatform` 强制成 android（见
    /// Flutter 框架 `_platform_io.dart`：只要检测到 `FLUTTER_TEST` 环境变量
    /// 就固定成 android，跟宿主机真实操作系统无关）。而 Flutter 内置的
    /// `DefaultTextEditingShortcuts`（真正负责文本框内 Cmd/Ctrl+V 粘贴的那层）
    /// 是按 `defaultTargetPlatform`（不是 `dart:io` 的 `Platform.isMacOS`）
    /// 挑选 mac 版（meta+V）还是通用版（control+V）快捷键映射的。所以要
    /// 真实覆盖"macOS 上 Cmd+V 不冲突"这条场景，测试里必须显式把
    /// `debugDefaultTargetPlatformOverride` 设成对应平台，不能依赖默认值。
    Future<void> withTargetPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    }

    testWidgets('macOS + 焦点在 TextField 里按 Cmd+V：走正常文本粘贴，不触发全局导入', (
      tester,
    ) async {
      await withTargetPlatform(TargetPlatform.macOS, () async {
        mockClipboard(tester, text: '不应该被当成订阅导入的粘贴内容');
        var globalPasteCalls = 0;
        final controller = TextEditingController();

        await pumpShortcuts(
          tester,
          container: container,
          onPasteImport: (ref) async => globalPasteCalls++,
          home: Scaffold(
            body: TextField(
              key: const ValueKey('target_field'),
              controller: controller,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('target_field')));
        await tester.pump();

        await pressPaste(tester, meta: true);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          controller.text,
          '不应该被当成订阅导入的粘贴内容',
          reason: 'DefaultTextEditingShortcuts 应该已经把剪贴板内容粘贴进文本框',
        );
        expect(
          globalPasteCalls,
          0,
          reason: '焦点在文本框内时，全局粘贴导入快捷键不应该被触发——否则会跟用户正常编辑文本冲突',
        );
      });
    });

    testWidgets('Linux + 焦点在 TextField 里按 Ctrl+V：走正常文本粘贴，不触发全局导入', (
      tester,
    ) async {
      await withTargetPlatform(TargetPlatform.linux, () async {
        mockClipboard(tester, text: '不应该被当成订阅导入的粘贴内容');
        var globalPasteCalls = 0;
        final controller = TextEditingController();

        await pumpShortcuts(
          tester,
          container: container,
          onPasteImport: (ref) async => globalPasteCalls++,
          home: Scaffold(
            body: TextField(
              key: const ValueKey('target_field'),
              controller: controller,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('target_field')));
        await tester.pump();

        await pressPaste(tester, meta: false);
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          controller.text,
          '不应该被当成订阅导入的粘贴内容',
          reason: 'DefaultTextEditingShortcuts 应该已经把剪贴板内容粘贴进文本框',
        );
        expect(globalPasteCalls, 0);
      });
    });

    testWidgets('焦点不在任何输入框时按 Cmd+V：触发全局导入', (tester) async {
      mockClipboard(tester, text: 'https://example.com/sub');
      var globalPasteCalls = 0;

      await pumpShortcuts(
        tester,
        container: container,
        onPasteImport: (ref) async => globalPasteCalls++,
        home: const Scaffold(body: SizedBox.shrink()),
      );

      await pressPaste(tester, meta: true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(globalPasteCalls, 1);
    });
  });

  group('其它桌面快捷键（Cmd+W / Cmd+, / Ctrl+Q）+ 平台门控', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(const StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
    });

    tearDown(() => container.dispose());

    testWidgets('macOS：Cmd+W 触发关闭窗口回调', (tester) async {
      var closeCalls = 0;
      await pumpShortcuts(
        tester,
        container: container,
        isMacOS: true,
        isLinux: false,
        onCloseWindow: (ref) async => closeCalls++,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(closeCalls, 1);
    });

    testWidgets('macOS：Cmd+, 触发切到设置 tab', (tester) async {
      await pumpShortcuts(
        tester,
        container: container,
        isMacOS: true,
        isLinux: false,
      );

      expect(container.read(selectedTabProvider), isNot(AppTab.settings));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(container.read(selectedTabProvider), AppTab.settings);
    });

    testWidgets('非 macOS：Cmd+W / Cmd+, 不注册，按了没反应', (tester) async {
      var closeCalls = 0;
      await pumpShortcuts(
        tester,
        container: container,
        isMacOS: false,
        isLinux: false,
        onCloseWindow: (ref) async => closeCalls++,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(closeCalls, 0);
      expect(container.read(selectedTabProvider), isNot(AppTab.settings));
    });

    testWidgets('Linux：Ctrl+Q 触发退出回调', (tester) async {
      var quitCalls = 0;
      await pumpShortcuts(
        tester,
        container: container,
        isMacOS: false,
        isLinux: true,
        onQuitApp: (ref) async => quitCalls++,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(quitCalls, 1);
    });

    testWidgets('非 Linux：Ctrl+Q 不注册，按了没反应', (tester) async {
      var quitCalls = 0;
      await pumpShortcuts(
        tester,
        container: container,
        isMacOS: false,
        isLinux: false,
        onQuitApp: (ref) async => quitCalls++,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(quitCalls, 0);
    });
  });
}
