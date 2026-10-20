// 与 lib/app/tray/tray_controller.dart 一样，暂时停在 tray_manager 的 legacy
// 接口上（见那里的说明）。
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/app/tray/tray_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/legacy.dart';

/// 回归测试几个点：
///
/// 1. 托盘菜单文案曾经硬编码中文（tray_controller.dart:76-83），未走 i18n。
///    [buildTrayMenuLabels] 是抽出来的纯函数：状态 + Translations -> 文案，
///    改成读 `translations.g.dart` 里已有的 `tray.*` key（`tray.open` /
///    `tray.hide`（新增）/ `tray.quit` / `tray.status.*`）。
/// 2. `trayManager.setIcon` 失败（tray_on/off/pending.png 缺失导致）此前在
///    状态变化的监听回调里是 `.catchError((_) {})`——完全静默吞掉，连
///    debugPrint 都没有。[setTrayIconWithLogging] 保证失败至少有日志，跟
///    setup() 里最初那次 setIcon 的日志行为保持一致。
/// 3. 托盘菜单此前只有"切换连接/显示/隐藏/退出"，缺"跳转到具体页面"和"切换
///    服务模式（智能/全局）"两个子菜单——用户想切页面/切模式必须先把窗口显示
///    出来再手动点。[buildTrayMenu] 是抽出来的纯函数（状态 + Translations +
///    当前 proxyMode -> 完整 [Menu] 结构），[performOpenPage] /
///    [performProxyModeSwitch] 是子菜单点击后实际动作的纯函数（依赖全部以回调
///    注入），三者都不碰真实的 ProviderContainer / 平台 channel，可以直接在
///    纯 Dart 测试里验证结构和调用序列。
void main() {
  group('buildTrayMenuLabels', () {
    test('英文：各阶段下 toggle 文案 + 固定的 show/hide/quit', () {
      final t = AppLocale.en.buildSync();

      expect(
        buildTrayMenuLabels(ConnectionPhase.disconnected, t).toggle,
        'Connect',
      );
      expect(
        buildTrayMenuLabels(ConnectionPhase.connecting, t).toggle,
        'Connecting',
      );
      expect(
        buildTrayMenuLabels(ConnectionPhase.connected, t).toggle,
        'Disconnect',
      );
      expect(
        buildTrayMenuLabels(ConnectionPhase.disconnecting, t).toggle,
        'Disconnecting',
      );

      final labels = buildTrayMenuLabels(ConnectionPhase.disconnected, t);
      expect(labels.show, 'Open');
      expect(labels.hide, 'Hide to Tray');
      expect(labels.quit, 'Quit');
    });

    test('简体中文：各阶段下 toggle 文案 + 固定的 show/hide/quit', () {
      final t = AppLocale.zhCn.buildSync();

      expect(buildTrayMenuLabels(ConnectionPhase.disconnected, t).toggle, '连接');
      expect(buildTrayMenuLabels(ConnectionPhase.connecting, t).toggle, '正在连接');
      expect(buildTrayMenuLabels(ConnectionPhase.connected, t).toggle, '断开连接');
      expect(
        buildTrayMenuLabels(ConnectionPhase.disconnecting, t).toggle,
        '正在断开连接',
      );

      final labels = buildTrayMenuLabels(ConnectionPhase.disconnected, t);
      expect(labels.show, '打开');
      expect(labels.hide, '隐藏到托盘');
      expect(labels.quit, '退出');
    });

    test('其它语言的 hide 已经是真翻译，不再兜底显示英文', () {
      // 这条断言以前锁的是"tray.hide 只翻了 en/zh-CN，其它语言靠
      // fallback_strategy: base_locale 兜底英文"——那是把翻译缺口当成预期行为
      // 记了下来。现在 10 个语言的 UI key 已全部补齐（见
      // translations_completeness_test.dart 的门禁），兜底路径不再被触发。
      final t = AppLocale.ar.buildSync();
      final hide = buildTrayMenuLabels(ConnectionPhase.disconnected, t).hide;
      expect(hide, isNotEmpty);
      expect(
        hide,
        isNot('Hide to Tray'),
        reason: '还等于英文原文说明 ar 的 tray.hide 又缺了，翻译门禁应该已经先报警',
      );
    });
  });

  group('performQuitSequence', () {
    late DebugPrintCallback originalDebugPrint;
    final logs = <String>[];

    setUp(() {
      logs.clear();
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      // 失败走应用日志（app.log）；这里接住记录，不写盘。
      debugAppFailureSink = (record) => logs.add(record.line);
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      debugAppFailureSink = null;
      resetAppFailureDedupForTesting();
    });

    test('按顺序执行：先断开连接，再清理托盘，最后销毁窗口', () async {
      final calls = <String>[];
      await performQuitSequence(
        disconnect: () async {
          calls.add('disconnect');
          return const RequestSucceeded();
        },
        disposeTray: () async => calls.add('disposeTray'),
        destroyWindow: () async => calls.add('destroyWindow'),
      );
      expect(calls, ['disconnect', 'disposeTray', 'destroyWindow']);
    });

    test(
      'disconnect 抛异常时不影响后续托盘清理和窗口销毁（跟原有 disconnect try/catch 行为一致）',
      () async {
        final calls = <String>[];
        await performQuitSequence(
          disconnect: () async => throw Exception('disconnect failed'),
          disposeTray: () async => calls.add('disposeTray'),
          destroyWindow: () async => calls.add('destroyWindow'),
        );
        expect(calls, ['disposeTray', 'destroyWindow']);
      },
    );

    test('disposeTray 抛异常（托盘图标已经不存在等）时记录日志，但仍然继续销毁窗口退出，而不是卡住/中止退出流程', () async {
      final calls = <String>[];
      await performQuitSequence(
        disconnect: () async => const RequestSucceeded(),
        disposeTray: () async => throw Exception('tray dispose failed'),
        destroyWindow: () async => calls.add('destroyWindow'),
      );
      expect(calls, ['destroyWindow']);
      expect(
        logs,
        anyElement(contains('[ERROR] quit.disposeTray')),
        reason: '托盘清理失败不该被静默吞掉，退出前的失败也要留日志，跟 setIcon 失败的日志约定一致',
      );
    });
  });

  group('trayIconSpec', () {
    test('macOS 使用系统模板托盘图标', () {
      final spec = trayIconSpec(isMacOS: true);

      expect(spec.path, 'assets/images/tray_icon_macos.png');
      expect(spec.isTemplate, isTrue);
    });

    test('Windows 和 Linux 使用彩色托盘图标', () {
      final spec = trayIconSpec(isMacOS: false);

      expect(spec.path, 'assets/images/tray_icon.png');
      expect(spec.isTemplate, isFalse);
    });
  });

  group('setTrayIconWithLogging', () {
    late DebugPrintCallback originalDebugPrint;
    final logs = <String>[];

    setUp(() {
      logs.clear();
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      // 失败走应用日志（app.log）；这里接住记录，不写盘。
      debugAppFailureSink = (record) => logs.add(record.line);
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      debugAppFailureSink = null;
      resetAppFailureDedupForTesting();
    });

    test('setIcon 成功时不产生任何日志', () async {
      await setTrayIconWithLogging(
        (_, {isTemplate = false}) async {},
        'assets/images/tray_on.png',
      );
      expect(logs, isEmpty);
    });

    test('setIcon 失败（图标文件缺失等）时记录日志，而不是静默吞掉', () async {
      await setTrayIconWithLogging(
        (_, {isTemplate = false}) async => throw Exception('asset not found'),
        'assets/images/tray_on.png',
      );
      expect(
        logs,
        anyElement(contains('[ERROR] tray.setIcon')),
        reason:
            '此前 tray_controller.dart 里状态变化时的 setIcon 调用是 '
            '.catchError((_) {})，图标文件缺失时的失败被完全静默吞掉，'
            '连排障用的日志都没有',
      );
    });

    test('把 macOS template 模式透传给 setIcon', () async {
      bool? receivedTemplate;

      await setTrayIconWithLogging(
        (_, {isTemplate = false}) async {
          receivedTemplate = isTemplate;
        },
        'assets/images/tray_icon_macos.png',
        isTemplate: true,
      );

      expect(receivedTemplate, isTrue);
    });
  });

  group('buildTrayMenu', () {
    test('英文：顶层结构不变——toggle/分隔线/show/hide/分隔线/打开子菜单/模式子菜单/分隔线/quit', () {
      final t = AppLocale.en.buildSync();
      final menu = buildTrayMenu(
        phase: ConnectionPhase.disconnected,
        t: t,
        proxyMode: 1,
      );

      expect(menu.items, hasLength(9));
      final keys = menu.items!.map((e) => e.key).toList();
      expect(keys, [
        'toggle',
        null, // separator
        'show',
        'hide',
        null, // separator
        'open_page',
        'proxy_mode',
        null, // separator
        'quit',
      ]);
    });

    test('toggle/show/hide/quit 文案跟 buildTrayMenuLabels 保持一致（不破坏既有回归）', () {
      final t = AppLocale.zhCn.buildSync();
      final labels = buildTrayMenuLabels(ConnectionPhase.connected, t);
      final menu = buildTrayMenu(
        phase: ConnectionPhase.connected,
        t: t,
        proxyMode: 1,
      );

      expect(menu.getMenuItem('toggle')!.label, labels.toggle);
      expect(menu.getMenuItem('show')!.label, labels.show);
      expect(menu.getMenuItem('hide')!.label, labels.hide);
      expect(menu.getMenuItem('quit')!.label, labels.quit);
    });

    test('过渡期 toggle 也可点（spec §10.9：连接中点 = 取消，断开中点 = 重新连接）', () {
      final t = AppLocale.en.buildSync();
      for (final phase in ConnectionPhase.values) {
        final menu = buildTrayMenu(phase: phase, t: t, proxyMode: 1);
        expect(
          menu.getMenuItem('toggle')!.disabled,
          isNot(isTrue),
          reason: '$phase',
        );
      }
    });

    test('"打开..."子菜单：至少包含首页/线路(订阅列表对应的持久化页面)/设置三个跳转项', () {
      final t = AppLocale.en.buildSync();
      final menu = buildTrayMenu(
        phase: ConnectionPhase.disconnected,
        t: t,
        proxyMode: 1,
      );

      final openPage = menu.getMenuItem('open_page')!;
      expect(openPage.type, 'submenu');
      expect(openPage.label, t.tray.dashboard);

      final subItems = openPage.submenu!.items!;
      expect(subItems, hasLength(3));
      expect(subItems.map((e) => e.key).toList(), [
        'open_home',
        'open_proxies',
        'open_settings',
      ]);
      expect(subItems[0].label, t.home.pageTitle);
      expect(subItems[1].label, t.proxies.pageTitle);
      expect(subItems[2].label, t.settings.pageTitle);
    });

    test('"服务模式"子菜单：列出智能/全局两个模式，且当前生效的模式带勾选', () {
      final t = AppLocale.en.buildSync();
      final menuGlobal = buildTrayMenu(
        phase: ConnectionPhase.disconnected,
        t: t,
        proxyMode: 0, // 0 = Global
      );
      final proxyModeItem = menuGlobal.getMenuItem('proxy_mode')!;
      expect(proxyModeItem.type, 'submenu');

      final subItems = proxyModeItem.submenu!.items!;
      expect(subItems, hasLength(2));
      expect(subItems.map((e) => e.key).toList(), [
        'mode_global',
        'mode_smart',
      ]);
      expect(subItems[0].label, t.home.routingMode.global);
      expect(subItems[1].label, t.home.routingMode.smart);
      expect(subItems[0].type, 'checkbox');
      expect(subItems[1].type, 'checkbox');
      expect(subItems[0].checked, isTrue, reason: '当前模式是 Global，对应项要打勾');
      expect(subItems[1].checked, isFalse);

      final menuSmart = buildTrayMenu(
        phase: ConnectionPhase.disconnected,
        t: t,
        proxyMode: 1, // 1 = Smart
      );
      final proxyModeItem2 = menuSmart.getMenuItem('proxy_mode')!;
      final subItems2 = proxyModeItem2.submenu!.items!;
      expect(subItems2[0].checked, isFalse);
      expect(subItems2[1].checked, isTrue, reason: '当前模式是 Smart，对应项要打勾');
    });

    test('简体中文：子菜单标题和子项文案都过 i18n，不是硬编码中文', () {
      final t = AppLocale.zhCn.buildSync();
      final menu = buildTrayMenu(
        phase: ConnectionPhase.disconnected,
        t: t,
        proxyMode: 1,
      );

      final openPage = menu.getMenuItem('open_page')!;
      expect(openPage.label, '仪表板'); // t.tray.dashboard
      final subItems = openPage.submenu!.items!;
      expect(subItems[0].label, '主页');
      expect(subItems[1].label, '线路');
      expect(subItems[2].label, '设置');

      final proxyModeItem = menu.getMenuItem('proxy_mode')!;
      final modeItems = proxyModeItem.submenu!.items!;
      expect(modeItems[0].label, '全局代理');
      expect(modeItems[1].label, '智能分流');
    });
  });

  group('performOpenPage', () {
    test('跳转到指定页面：先切 selectedTab，再 show + focus 窗口', () async {
      final calls = <String>[];
      await performOpenPage(
        tabIndex: 2,
        setSelectedTab: (i) => calls.add('setSelectedTab($i)'),
        showWindow: () async => calls.add('show'),
        focusWindow: () async => calls.add('focus'),
      );
      expect(calls, ['setSelectedTab(2)', 'show', 'focus']);
    });
  });

  group('performShutdownCleanup 按断开请求的 RequestOutcome 处理', () {
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('succeeded：断开一次，然后清理托盘', () async {
      final calls = <String>[];
      await performShutdownCleanup(
        disconnect: () async {
          calls.add('disconnect');
          return const RequestSucceeded();
        },
        disposeTray: () async => calls.add('disposeTray'),
      );
      expect(calls, ['disconnect', 'disposeTray']);
    });

    test('superseded：断开被更新的请求取代时继续等最新的断开，直到有结论', () async {
      final calls = <String>[];
      final outcomes = <RequestOutcome>[
        const RequestSuperseded(),
        const RequestSuperseded(),
        const RequestSucceeded(),
      ];
      await performShutdownCleanup(
        disconnect: () async {
          calls.add('disconnect');
          return outcomes.removeAt(0);
        },
        disposeTray: () async => calls.add('disposeTray'),
      );
      expect(calls, ['disconnect', 'disconnect', 'disconnect', 'disposeTray']);
    });

    // 以下用 fake_async 精确控制时间：总期限 5 s（kQuitCleanupDeadline），其中
    // 停内核最多用到 4.5 s（预留 500 ms 给托盘），托盘用到 5 s 为止。
    const reserveStart = Duration(milliseconds: 4500);
    const total = Duration(seconds: 5);

    /// 在 fake_async 里启动一次退出清理；返回完成时刻（未完成为 null）的查询。
    Duration? Function() startQuit(
      FakeAsync fa, {
      required Future<RequestOutcome> Function() disconnect,
      required Future<void> Function() disposeTray,
    }) {
      Duration? doneAt;
      performShutdownCleanup(
        disconnect: disconnect,
        disposeTray: disposeTray,
      ).then((_) => doneAt = fa.elapsed);
      fa.flushMicrotasks();
      return () => doneAt;
    }

    test('superseded 超过三次也继续等最新的断开：第 5 次才成功，不能在第 3 次就带着可能在跑的内核退出', () {
      fakeAsync((fa) {
        var n = 0;
        final calls = <String>[];
        final doneAt = startQuit(
          fa,
          disconnect: () async {
            n++;
            return n < 5 ? const RequestSuperseded() : const RequestSucceeded();
          },
          disposeTray: () async => calls.add('disposeTray'),
        );
        fa.elapse(const Duration(seconds: 1));
        expect(n, 5);
        expect(calls, ['disposeTray']);
        expect(doneAt(), isNotNull);
        expect(doneAt()! < const Duration(seconds: 1), isTrue);
      });
    });

    test('一直 superseded：持续重发到停内核预算（4.5 s）用尽；之后不再提交任何请求，托盘照常清理', () {
      fakeAsync((fa) {
        var n = 0;
        final calls = <String>[];
        final doneAt = startQuit(
          fa,
          disconnect: () async {
            n++;
            return const RequestSuperseded();
          },
          disposeTray: () async => calls.add('disposeTray'),
        );

        fa.elapse(reserveStart - const Duration(milliseconds: 1));
        expect(doneAt(), isNull, reason: '预算用尽之前仍在重发');
        expect(n, greaterThan(100), reason: '期限内持续重发（每轮间隔 20 ms），不是三轮封顶');

        fa.elapse(const Duration(milliseconds: 1));
        expect(doneAt(), reserveStart, reason: '预算用尽的那一刻放弃并清托盘');
        expect(calls, ['disposeTray']);

        final submitted = n;
        fa.elapse(const Duration(seconds: 30));
        expect(n, submitted, reason: '期限之后不再提交任何断开请求');
      });
    });

    test('断开与清托盘都悬停：整个流程恰在总期限 5 s 结束，托盘只拿到剩下的预算', () {
      fakeAsync((fa) {
        final disconnectGate = Completer<RequestOutcome>();
        final trayGate = Completer<void>();
        Duration? trayStartedAt;
        var disconnects = 0;
        final doneAt = startQuit(
          fa,
          disconnect: () {
            disconnects++;
            return disconnectGate.future;
          },
          disposeTray: () {
            trayStartedAt = fa.elapsed;
            return trayGate.future;
          },
        );

        fa.elapse(reserveStart - const Duration(milliseconds: 1));
        expect(trayStartedAt, isNull);
        fa.elapse(const Duration(milliseconds: 1));
        expect(trayStartedAt, reserveStart, reason: '停内核预算用尽，托盘开始');

        fa.elapse(const Duration(milliseconds: 499));
        expect(doneAt(), isNull, reason: '4.999 s 还没到总期限');
        fa.elapse(const Duration(milliseconds: 1));
        expect(doneAt(), total, reason: '总期限到点即结束，没有额外宽限');

        // 放弃之后迟到的 superseded 不再触发新一轮断开。
        disconnectGate.complete(const RequestSuperseded());
        fa.elapse(const Duration(seconds: 10));
        expect(disconnects, 1);
      });
    });

    test('停内核提前完成、清托盘悬停：托盘用满剩余预算，仍恰在 5 s 结束', () {
      fakeAsync((fa) {
        final trayGate = Completer<void>();
        final doneAt = startQuit(
          fa,
          disconnect: () async => const RequestSucceeded(),
          disposeTray: () => trayGate.future,
        );
        fa.elapse(const Duration(milliseconds: 4999));
        expect(doneAt(), isNull);
        fa.elapse(const Duration(milliseconds: 1));
        expect(doneAt(), total);
      });
    });

    test('failed / interrupted：不重试（也不清标记——标记归控制器管），照常清理托盘退出', () async {
      for (final outcome in <RequestOutcome>[
        const RequestFailed(KernelUnresponsive()),
        const RequestInterrupted(),
      ]) {
        var n = 0;
        final calls = <String>[];
        await performShutdownCleanup(
          disconnect: () async {
            n++;
            return outcome;
          },
          disposeTray: () async => calls.add('disposeTray'),
        );
        expect(n, 1, reason: '$outcome');
        expect(calls, ['disposeTray'], reason: '$outcome');
      }
    });
  });

  group('performProxyModeSwitch', () {
    test('目标模式跟当前模式相同：什么都不做（不重复推送/不重新应用）', () async {
      final calls = <String>[];
      await performProxyModeSwitch(
        targetMode: 1,
        currentMode: () => 1,
        updateMode: (v) async => calls.add('updateMode($v)'),
        isConnected: () => true,
        applyConfig: () async => calls.add('applyConfig'),
      );
      expect(calls, isEmpty);
    });

    test('切换模式且当前未连接：只更新模式，不重新应用配置', () async {
      final calls = <String>[];
      await performProxyModeSwitch(
        targetMode: 0,
        currentMode: () => 1,
        updateMode: (v) async => calls.add('updateMode($v)'),
        isConnected: () => false,
        applyConfig: () async => calls.add('applyConfig'),
      );
      expect(calls, ['updateMode(0)']);
    });

    test('切换模式且当前已连接：更新模式后要重新应用配置让新模式立刻生效', () async {
      final calls = <String>[];
      await performProxyModeSwitch(
        targetMode: 0,
        currentMode: () => 1,
        updateMode: (v) async => calls.add('updateMode($v)'),
        isConnected: () => true,
        applyConfig: () async => calls.add('applyConfig'),
      );
      expect(calls, ['updateMode(0)', 'applyConfig']);
    });
  });
}
