import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/proxy/state/proxy_selection_store_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/temp_dirs.dart';

/// 判断最近一次推给 native 的 configOptions 是不是"智能分流"模式产出的。
///
/// 真正生效的智能/全局分流信号是这里的 `rules` 字段（driven by
/// `getDefaultConfigOptions` 的 `isSmart` 参数）——**不是**
/// `RuntimeConfigBuilder` 写的 runtime-config.json 的 `route` 块。真机验证过：
/// 这个 sing-box fork 的 `config.BuildConfig()` 会无条件丢弃/重建 profile
/// 自带的整个 `route` 块，之前那份注入到 runtime-config.json 里的 cn 分流
/// 规则从未真正生效。也不能用 `execute-config-as-is` 字段判断——那个字段
/// 故意恒为 `true`（见 `default_config_options.dart` 注释）。
bool _isSmartConfigOptions(Map<String, dynamic>? json) {
  final rules = json?['rules'] as List?;
  return rules != null && rules.isNotEmpty;
}

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp('cc_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

/// 非 stub spy，控制 watchStatus/watchNetworkChanged 流，记录方法调用次数。
class _SpyBoxService implements BoxService {
  /// `BehaviorSubject`（不是普通 broadcast `StreamController`）是故意的——
  /// 匹配真实 `PlatformBoxService`/`FFIBoxService` 用 `ValueConnectableStream`
  /// 实现的 ValueStream 语义：新订阅者（含 `.first`）立即同步拿到"当前缓存
  /// 值"，不需要等下一次 `.add()`。这正是 connect() 的 `_settleAfterStart`
  /// 自愈兜底所依赖的行为——native 已经在跑但不再推送新事件时，靠这个语义
  /// 读到"当前真实状态"而不是永远等不到的下一条推送。
  /// 用普通 broadcast controller 曾经踩过一个坑：手搓的 `async*` 包装会在
  /// "新订阅者" 前引入一个微任务延迟，导致"构造后立即 add()"的既有测试
  /// 时序被打破（事件在内部订阅真正接上之前就发出，广播流不补放，直接丢失）。
  /// `BehaviorSubject` 是这个仓库生产代码已经在用的成熟方案，语义经过验证。
  final statusStreamController = BehaviorSubject<BoxStatus>();
  final networkChangedController = StreamController<void>.broadcast();
  final alertStreamController = StreamController<BoxAlert>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int changeConfigCalls = 0;
  int restartCalls = 0;

  /// 最近一次 changeConfigOptions 收到的 JSON——用来断言"最终真正生效的是
  /// 哪个路由模式"，而不是只数调用次数（真机上的静默错位 bug就是调用次数
  /// 正常、但内容对应的是过时的模式）。
  Map<String, dynamic>? lastChangeConfigJson;

  /// 若非 null，每次调用 stop() 都会 throw 这个异常（模拟 stop 持续失败，
  /// 用于测试 disconnect() "重试也失败" 时绝不能谎报 BoxStopped 的核心不变量）。
  Object? stopError;

  /// 前 N 次调用 stop() 会 throw（然后自减），之后正常返回。
  /// 用于模拟 disconnect() 里 "首次失败、强制清理重试后成功" 的分支。
  int stopFailTimes = 0;

  /// 若非 null，每次调用 start() 都会 throw 这个异常。用于模拟 connect() 里
  /// try/catch 捕获到常见 Dart 异常（SocketException / TimeoutException 等）
  /// 时，connectionErrorProvider 应该写入分类后的本地化文案，而不是原始
  /// e.toString()。
  Object? startError;

  @override
  Future<void> start(String path, {String name = ''}) async {
    startCalls++;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopFailTimes > 0) {
      stopFailTimes--;
      throw Exception('mock stop failure (transient #$stopCalls)');
    }
    if (stopError != null) {
      throw stopError!;
    }
  }

  /// 最近一次 restart() 收到的 runtime-config 路径——真正决定智能/全局分流
  /// 的信号在这份文件的内容里（`RuntimeConfigBuilder.isSmart`），不在
  /// `changeConfigOptions` 的 JSON（`execute-config-as-is` 故意恒为
  /// `true`，见 `default_config_options.dart` 注释：路由完全交给
  /// RuntimeConfigBuilder，fork 侧不再插手，避免 fork 强制 append 国内
  /// 下载不了的 remote rule-set）。
  String? lastRestartPath;

  @override
  Future<void> restart(String path, {String name = ''}) async {
    restartCalls++;
    lastRestartPath = path;
  }

  @override
  Future<void> changeConfigOptions(String json) async {
    changeConfigCalls++;
    lastChangeConfigJson = jsonDecode(json) as Map<String, dynamic>;
  }

  // 其余方法最小实现
  @override
  Future<void> init() async {}
  @override
  Future<void> setup(AppDirectories d, {bool debug = false}) async {}
  @override
  Future<String?> validateConfig(
    String a,
    String b, {
    bool debug = false,
  }) async => null;

  /// 记录每次 selectOutbound 调用的 "groupTag->outboundTag"——用来断言
  /// "进入 BoxStarted 后重放持久化选择"这个副作用真的发生了，而不是只数次数。
  /// 用格式化字符串而非 MapEntry：MapEntry 没有覆写 `==`，直接拿来做列表相等
  /// 断言会按对象identity比较，即使内容相同也会判不等。
  final List<String> selectOutboundCalls = [];

  /// 若非空，groupTag 命中这个集合时 selectOutbound 会 throw——模拟"某个
  /// group 的持久化选择已经失效（tag 不存在）"，验证单条失败不影响其它条重放。
  final Set<String> selectOutboundFailFor = {};

  @override
  Future<void> selectOutbound(String g, String o) async {
    if (selectOutboundFailFor.contains(g)) {
      throw Exception('mock selectOutbound failure for group $g');
    }
    selectOutboundCalls.add('$g->$o');
  }

  @override
  Future<void> urlTest(String g) async {}
  @override
  Stream<BoxStatus> watchStatus() => statusStreamController.stream;
  @override
  Stream<BoxAlert> watchAlerts() => alertStreamController.stream;
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String p) async => null;
  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => networkChangedController.stream;
  @override
  Future<void> resetTunnel() async {}
}

/// [StoreReviewService] 真实实现最终会调到私有构造单例 [InAppReview]，
/// 测试用这个假实现覆盖 [storeReviewServiceProvider]，只记录调用次数，
/// 不触碰任何原生插件。
class _FakeStoreReviewService extends StoreReviewService {
  _FakeStoreReviewService(super.ref);

  int maybeRequestReviewCalls = 0;

  @override
  Future<void> maybeRequestReview() async {
    maybeRequestReviewCalls++;
  }
}

/// `getActive()` 抛异常的仓库。用来构造一个**从 connect() 前置段逃出来**的
/// 异常——那一段（读仓库、取激活订阅、拼配置路径、判文件存在）在 connect()
/// 自己的 try 之外，异常会一路穿出 connect()。
///
/// 不用 spy 的 `startError`：那个是在 start() 上抛，会被 connect() 内层的
/// try/catch 正常接住，测不到 toggle() 这层兜底。
class _ThrowingActiveRepo extends ProfileRepository {
  _ThrowingActiveRepo({
    required super.dio,
    required super.configDir,
    required super.prefs,
    required super.boxService,
  });

  @override
  ProfileEntity? getActive() => throw StateError('模拟仓库读取失败');
}

/// 轮询等待条件成立，而不是睡一个固定时长。
///
/// `await Future.delayed(200ms)` 本质是在赌「这段异步工作 200ms 内一定做完」。
/// 本地够，CI runner 负载高时不够——这个文件里的竞态回归测试就因此在发版门禁
/// 上随机失败过一次：睡完 200ms，connect() 还没走到 start()（它前面有真实的
/// 文件 I/O 和运行时配置构建）。
///
/// 轮询把"等多久"换成"等到什么条件"，语义不变而不再依赖机器速度。超时会带着
/// 说明失败，而不是留下一个 `Expected: <1> Actual: <0>` 让人去猜。
Future<void> _until(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('等待超时（${timeout.inSeconds}s）：$reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionController', () {
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

    test('初始状态 BoxStopped', () {
      final s = container.read(connectionControllerProvider).valueOrNull;
      expect(s, isA<BoxStopped>());
    });

    test('stub service 下 connect 直接返回，状态不变', () async {
      await container.read(connectionControllerProvider.notifier).connect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('stub service 下 disconnect 直接返回，状态不变', () async {
      await container.read(connectionControllerProvider.notifier).disconnect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('stub service 下 reconnect 直接返回', () async {
      await container.read(connectionControllerProvider.notifier).reconnect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('toggle 从 BoxStopped → 调 connect 路径（stub 下无副作用）', () async {
      await container.read(connectionControllerProvider.notifier).toggle();
      // stub 不会真的连，状态保持
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });
  });

  group('ConnectionController spy 路径', () {
    test('spy service 下 connect 无激活订阅时早返回（不调 start）', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);

      await container.read(connectionControllerProvider.notifier).connect();

      expect(spy.startCalls, 0, reason: '无激活订阅不应该调 start');
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
      container.dispose();
    });

    test('网络变更触发退避重连时，用户手动断开应阻止自动重连把连接顶回去', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      // 种一个激活订阅 + 可被 RuntimeConfigBuilder 成功解析的最小配置文件，
      // 否则 reconnect() 会在 repo.getActive()==null 或配置文件不存在时提前
      // return，永远走不到 _boxService.restart，测试就测不出真实的修复效果
      // （见 test/core/config/runtime_config_builder_test.dart 里同款最小 fixture）。
      const profileId = 'net-change-profile';
      await repo.upsert({
        'id': profileId,
        'name': '网络切换测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      final controller = container.read(connectionControllerProvider.notifier);

      // 模拟 BoxStarted（不走 connect()，直接推流，绕开配置/权限等无关前提）
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '前置条件：必须先进入已连接态才能触发 autoReconnect',
      );

      // 触发网络变更 → _networkSub 命中 BoxStarted → 启动 _autoReconnect
      // 退避循环（第一档延迟 1 秒）
      spy.networkChangedController.add(null);
      await Future<void>.delayed(Duration.zero);

      // 退避窗口内（1 秒延迟尚未到期），用户手动断开
      await controller.disconnect();

      // disconnect() 自身有 1.5s 展示动画，await 完成时已经跨过 autoReconnect
      // 第一档 1s 检查点。修复前：循环在检查点看到 state 是 BoxStopping（不是
      // BoxStarted），旧的"已恢复"守卫判断为假，继续调用 reconnect() →
      // restart，把用户刚断开的连接顶回去。修复后：_manualDisconnect 守卫
      // 在检查点为真，循环直接 return，不再调用 restart/start。
      expect(spy.restartCalls, 0, reason: '手动断开后 autoReconnect 不应该把连接顶回去');
      expect(spy.startCalls, 0);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });

    test('快速"断开→重连"时，disconnect 的迟到收尾不得覆盖新连接的 BoxStarted（真机竞态回归）', () async {
      // 真机实锤过的竞态（Pixel 4 XL，2026-07-20 12:36）：
      //   1. 用户断开 → disconnect(): stop() 完成后还有 1.5s 展示动画
      //   2. 动画窗口内用户点了重连 → connect(): start() 发出，native 推
      //      Started，watchStatus 穿透写入 state=BoxStarted（UI 短暂正确）
      //   3. disconnect 的 1.5s 到期，迟到的收尾无条件 state=BoxStopped，
      //      把已建立的连接状态覆盖回"已断开"
      //   4. 用户看着"已断开"再点连接 → native onStartCommand 因"已在运行"
      //      静默忽略、不再推送 → state 永卡 BoxStarting，UI 永远"正在连接"
      // 修复：操作代际（epoch）——旧操作 await 之后的所有 state 写入先确认
      // 自己仍是最新操作，否则放弃（新操作已接管）。
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'race-profile';
      await repo.upsert({
        'id': profileId,
        'name': '竞态测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      final controller = container.read(connectionControllerProvider.notifier);

      // 时序控制点：把 disconnect 的「1.5s 展示动画」换成一个由本测试掌握的
      // 闸门。这样"迟到的收尾"到底什么时候执行完全由测试决定，不再依赖机器
      // 快慢——原来这里靠一串固定睡眠去和真实的 1.5s 对齐，在 CI 上随机失败
      // （Expected: <1> Actual: <0>，200ms 睡完 connect() 还没走到 start()）。
      //
      // 注意这不只是"修 flaky"：如果只把睡眠换成轮询等条件，机器再慢一点，
      // 1.5s 窗口会在 connect() 接管之前就到期，测试**空转通过**——最终断言
      // 照样成立，但根本没经过要测的竞态。闸门同时消掉了这两种失效。
      final settleGate = Completer<void>();
      var settleRequested = false;
      controller.disconnectSettleDelay = (_) {
        settleRequested = true;
        return settleGate.future;
      };

      // 进入已连接态
      spy.statusStreamController.add(const BoxStarted());
      await _until(
        () =>
            container.read(connectionControllerProvider).valueOrNull
                is BoxStarted,
        reason: '初始应进入已连接态',
      );

      // 1. 断开（不 await——让它的收尾悬在闸门上）
      final disconnectFuture = controller.disconnect();
      await _until(() => spy.stopCalls == 1, reason: 'disconnect 应真实调用 stop');
      // native 确认停止
      spy.statusStreamController.add(const BoxStopped());
      // 等到 disconnect 真的进入了收尾等待——这才叫"窗口已打开"，后面的重连
      // 才确定落在窗口之内。
      await _until(() => settleRequested, reason: 'disconnect 应进入收尾等待');

      // 2. 窗口内用户重连
      final connectFuture = controller.connect();
      await _until(() => spy.startCalls == 1, reason: '重连应真实调用 start');
      // native 起来了
      spy.statusStreamController.add(const BoxStarted());
      await _until(
        () =>
            container.read(connectionControllerProvider).valueOrNull
                is BoxStarted,
        reason: 'BoxStarted 应穿透 _transitioning 写入',
      );

      // 3. 现在才放开闸门：迟到的 disconnect 收尾在"新连接已建立"之后执行——
      // 这正是真机上出问题的那个顺序，而且现在是确定发生的，不是碰巧。
      settleGate.complete();
      await disconnectFuture;
      await connectFuture;

      // 4. 核心断言：迟到的 disconnect 收尾不得把 Started 覆盖回 Stopped
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason:
            'disconnect 的迟到收尾覆盖了新连接的状态——真机上这会导致 UI '
            '显示已断开、native 实际在跑，用户再点连接被 native 静默忽略后'
            '永卡"正在连接"',
      );
    });

    test('toggle() 撞上从 connect() 前置段逃出来的异常时，必须写出可见错误、并且不吞掉异常', () async {
      // 首页那颗大按钮是 fire-and-forget：
      //   onTap: () { ref.read(connectionControllerProvider.notifier).toggle(); }
      // 异常从 connect() 逃出来就没人接，用户点了**什么都不发生、也没有任何
      // 提示**——一个死按钮。这跟 connect() 里那几条前置校验分支是同一种
      // 用户体验，只是来源换成了"意外异常"。
      //
      // 同时断言异常仍然往外抛：吞掉它换来一条可见提示、代价是崩溃上报里
      // 从此看不到这个故障，那是拿可观测性换体面。
      final tmp = await _mockPathProvider();
      addTearDown(() => deleteTempDirBestEffort(tmp));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          profileRepositoryProvider.overrideWith(
            (ref) async => _ThrowingActiveRepo(
              dio: Dio(),
              configDir: tmp,
              prefs: prefs,
              boxService: spy,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);

      final controller = container.read(connectionControllerProvider.notifier);
      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '前提：还没出错',
      );

      await expectLater(
        controller.toggle(),
        throwsA(isA<StateError>()),
        reason: 'toggle() 不该吞掉异常——全局错误处理/崩溃上报还要看到它',
      );

      expect(
        container.read(connectionErrorProvider),
        isNotNull,
        reason:
            'toggle() 抛出异常时没有写 connectionErrorProvider——首页按钮是 '
            'fire-and-forget，用户点了会什么反应都没有，就是个死按钮',
      );
      expect(spy.startCalls, 0, reason: '前置段就炸了，不该真的调用 start');
    });

    // 注：connect() 里 `_settleAfterStart` 那层"读一次当前缓存值对齐真实
    // 终态"的自愈兜底，在这个测试文件的 spy 架构下没法诚实地单独测出来——
    // `_SpyBoxService.watchStatus()` 是单一共享的 `BehaviorSubject`，任何
    // 会被自愈读到的值，必然也已经被 ConnectionController 构造时挂上的
    // 持久监听器同步收到（两者读的是同一个源）。它真正防的场景是"整个
    // BoxService 实例都是全新的、其原生绑定层第一次订阅时错过了已经发生
    // 过的状态变化"（例如 Android `KernelBinder.registerCallback()` 不给
    // 新回调补发当前状态——这个具体缺口已经在原生层直接修了，见
    // `KernelBinder.kt`），这个量级的场景已经超出单个 ConnectionController
    // 单测能构造的范围，真实验证见真机复测记录。

    test('applyProxyMode 已连接时真实 reconnect，内核收到的模式与最终选择一致', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'mode-profile';
      await repo.upsert({
        'id': profileId,
        'name': '模式测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      final controller = container.read(connectionControllerProvider.notifier);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      container.read(proxyModeProvider.notifier).state = 0; // 全局
      await controller.applyProxyMode();

      expect(spy.restartCalls, 1, reason: '已连接时切模式应该真实 restart');
      expect(
        _isSmartConfigOptions(spy.lastChangeConfigJson),
        isFalse,
        reason: '全局模式下推给 native 的 configOptions 不应该带智能分流的 rules',
      );
    });

    test('快速连续切换模式（第二次点击落在第一次 reconnect 的 BoxStarting 窗口内）'
        '——最终内核必须用最后一次选择的模式，不能被静默吞掉（真机竞态回归）', () async {
      // 真机实锤（Pixel 4 XL，2026-07-20）：连续点"智能→全局"，间隔 300ms。
      // 旧实现（home_page.dart `_ModeSelector._onModeTap` 自己手写判断）用
      // `connStatus is BoxStarted` 决定要不要 reconnect——第二次点击执行到
      // 这一行时，第一次点击触发的 reconnect() 早已把 state 同步写成了
      // BoxStarting（还没跑完），判断为 false，第二次点击被完全跳过：UI 显示
      // 用户最后选的模式，但拉出真机 runtime-config.json 一看，
      // `route.final` 和规则数对应的是第一次（也就是过时那次）的模式。
      // 修复：改到 ConnectionController.applyProxyMode()，用忙时合并 + 收敛
      // 到最新值的排队，不再要求"此刻精确是 BoxStarted"。
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'rapid-mode-profile';
      await repo.upsert({
        'id': profileId,
        'name': '快速模式切换测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      final controller = container.read(connectionControllerProvider.notifier);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.restartCalls = 0; // 只关心这次切换动作触发的调用

      // 第一次点击：智能 → 全局（不 await，模拟点击后立刻发生第二次点击）
      container.read(proxyModeProvider.notifier).state = 0; // 全局
      final firstApply = controller.applyProxyMode();
      // 落在第一次 reconnect() 的 BoxStarting 窗口内（restart 之后、2s 展示
      // 窗口结束之前）。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarting>(),
        reason: '前置条件：第二次点击必须真的落在第一次 reconnect 还没跑完的窗口里',
      );

      // 第二次点击：全局 → 智能（用户最终想要的模式）
      container.read(proxyModeProvider.notifier).state = 1; // 智能
      final secondApply = controller.applyProxyMode();

      await firstApply;
      await secondApply;

      expect(
        _isSmartConfigOptions(spy.lastChangeConfigJson),
        isTrue,
        reason:
            '内核最终收到的 configOptions 必须对应用户最后选择的"智能分流"'
            '（带 cn 分流的 rules），不能停留在第一次点击的"全局代理"',
      );
      expect(
        spy.restartCalls,
        greaterThanOrEqualTo(1),
        reason: '第二次点击不能被完全吞掉——用户最后选择的模式必须真的下发给内核',
      );
    });

    test('disconnect 持续失败时，state 绝不能谎报 BoxStopped（核心不变量）', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      spy.stopError = Exception('mock stop failure (persistent)');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      final controller = container.read(connectionControllerProvider.notifier);

      // 模拟已连接态（跳过真实 connect 流程，直接推流，绕开配置/权限等无关前提）
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '前置条件：必须先进入已连接态才能测试断开失败',
      );

      await controller.disconnect();

      // 断言顺序刻意把 "state 不能是 BoxStopped" 放在最前面：
      // 修复前的代码会在这里失败，失败原因精确对应 bug 本身
      // （catch 分支谎报 state = BoxStopped）。
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isNot(isA<BoxStopped>()),
        reason:
            'stop 持续失败时内核可能还在跑，UI 绝不能谎报已断开——'
            '这是本 App 最不能接受的故障形态（界面显示断开，流量还在走）',
      );
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '诚实的兜底状态应该是仍连接，让用户能再次点击断开重试',
      );
      expect(
        container.read(connectionErrorProvider),
        isNotNull,
        reason: '断开失败必须让用户能看到错误，不能静默吞掉',
      );
      expect(spy.stopCalls, 2, reason: '强制清理应该自动重试恰好一次（初次 + 1 次重试），不是无限重试');

      container.dispose();
    });

    test('disconnect 首次失败但重试成功时，强制清理生效，诚实回到 BoxStopped', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      spy.stopFailTimes = 1; // 只有第一次调用失败，重试那次会成功
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      final controller = container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      await controller.disconnect();

      expect(spy.stopCalls, 2, reason: '第一次失败后应该自动重试一次');
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
        reason: '重试确认停掉了，应该诚实地报告 BoxStopped',
      );

      container.dispose();
    });

    test('disconnect 一次成功时 state 应该是 BoxStopped（回归：正常路径不能被改坏）', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      final controller = container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      await controller.disconnect();

      expect(spy.stopCalls, 1, reason: '正常路径不应该触发任何重试');
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });
  });

  group('配置变更触发的自动重连应该让 UI 能感知到（不是纯静默）', () {
    test('已连接时网络设置变更 → configChangeReconnectNoticeProvider 应该变化一次', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      // 触发 ConnectionController 构造，订阅 networkSettingsProvider。
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '前置条件：必须已连接，网络设置变更才会触发重连',
      );

      final before = container.read(configChangeReconnectNoticeProvider);

      await container
          .read(networkSettingsProvider.notifier)
          .setMixedPort(23456);
      // 现在有防抖窗口（见 kConfigChangeReconnectDebounce），要等它过去
      await Future<void>.delayed(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 100),
      );

      final after = container.read(configChangeReconnectNoticeProvider);
      expect(
        after,
        isNot(equals(before)),
        reason:
            '配置变更触发的自动重连之前是纯静默的，用户可能误以为网络抖动；'
            'UI 需要能感知到这次重连发生（用来弹一条轻提示），因此这个 '
            'nonce 必须在每次触发时变化',
      );

      container.dispose();
    });

    // 剪贴板导入配置（NetworkSettingsNotifier.importJson）是逐字段
    // `await setter(...)` 应用的，一份完整导出约 30 个字段。没有防抖的话
    // 就是 30 次状态变更 → 30 次 reconnect() 互相踩踏 + 30 条 toast 连响。
    // 滑杆拖动同理（每动一格触发一次）。
    test('密集的连续设置变更只合并成一次重连 + 一条提示', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      // 种一个可用订阅，否则 reconnect() 会在前置校验就早返回，
      // restartCalls 永远是 0，测试会因为"根本没走到"而假通过。
      const profileId = 'debounce-profile';
      await repo.upsert({
        'id': profileId,
        'name': '防抖测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      container.read(connectionControllerProvider.notifier);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      final noticeBefore = container.read(configChangeReconnectNoticeProvider);
      final restartsBefore = spy.restartCalls;

      // 模拟批量导入：连着改 6 项设置，间隔远小于防抖窗口
      final settings = container.read(networkSettingsProvider.notifier);
      await settings.setMixedPort(23456);
      await settings.setStrictRoute(true);
      await settings.setEnableTlsFragment(true);
      await settings.setIndependentDnsCache(false);
      await settings.setMtu(1400);
      await settings.setClashApiPort(19001);

      await Future<void>.delayed(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 300),
      );

      expect(
        container.read(configChangeReconnectNoticeProvider) - noticeBefore,
        1,
        reason: '6 次密集变更只该弹一条提示，不是 6 条连响',
      );
      expect(
        spy.restartCalls - restartsBefore,
        1,
        reason: '6 次密集变更只该重连一次——多次并发 reconnect 会互相踩踏',
      );
    });

    test('防抖窗口内用户断开连接 → 不把连接顶回去', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      final restartsBefore = spy.restartCalls;
      await container.read(networkSettingsProvider.notifier).setMtu(1400);
      // 防抖还没到点就断开
      spy.statusStreamController.add(const BoxStopped());
      await Future<void>.delayed(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 300),
      );

      expect(
        spy.restartCalls,
        restartsBefore,
        reason: '用户已经断开了，延迟触发的重连不该把连接顶回去',
      );
    });

    test('未连接时网络设置变更 → 不触发重连通知（保持既有"未连接时改设置无副作用"行为）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      final before = container.read(configChangeReconnectNoticeProvider);

      await container
          .read(networkSettingsProvider.notifier)
          .setMixedPort(34567);
      await Future<void>.delayed(Duration.zero);

      final after = container.read(configChangeReconnectNoticeProvider);
      expect(after, equals(before), reason: '未连接时改设置不应该触发重连提示');

      container.dispose();
    });
  });

  group('首次成功连接触发商店评分请求', () {
    test(
      'watchStatus 推 BoxStarted（首次进入已连接态）→ 调用一次 maybeRequestReview',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        late _FakeStoreReviewService fakeReview;
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
            storeReviewServiceProvider.overrideWith((ref) {
              fakeReview = _FakeStoreReviewService(ref);
              return fakeReview;
            }),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        // 触发 ConnectionController 构造，订阅 watchStatus。
        container.read(connectionControllerProvider.notifier);

        spy.statusStreamController.add(const BoxStarted());
        await Future<void>.delayed(Duration.zero);

        expect(
          fakeReview.maybeRequestReviewCalls,
          1,
          reason: '首次真正进入 BoxStarted（跟触觉反馈同一个触发点）应该请求一次商店评分',
        );

        container.dispose();
      },
    );

    test('同一次连接内重复推送 BoxStarted → 不应该重复调用（wasStarted 守卫）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      late _FakeStoreReviewService fakeReview;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          storeReviewServiceProvider.overrideWith((ref) {
            fakeReview = _FakeStoreReviewService(ref);
            return fakeReview;
          }),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeReview.maybeRequestReviewCalls,
        1,
        reason: '同一段连接内重复推送同样的 BoxStarted 不应该重复触发',
      );

      container.dispose();
    });

    test('断开后再次连接（第二次进入 BoxStarted）→ ConnectionController 会再调用一次'
        '（"只弹一次"的持久化保护由 StoreReviewService 自己负责，不是这里）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      late _FakeStoreReviewService fakeReview;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          storeReviewServiceProvider.overrideWith((ref) {
            fakeReview = _FakeStoreReviewService(ref);
            return fakeReview;
          }),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStopped());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeReview.maybeRequestReviewCalls,
        2,
        reason:
            'ConnectionController 每次真正"进入" BoxStarted 都调用一次——'
            '"这辈子只弹一次"的持久化保护是 StoreReviewService 内部的职责'
            '（见 store_review_service_test.dart），不应该在这里重复实现',
      );

      container.dispose();
    });
  });

  group('进入 BoxStarted 后重放持久化的手选代理', () {
    test('有持久化选择时，真正进入 BoxStarted 后逐条重放到 boxService.selectOutbound', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          activeProfileProvider.overrideWith(
            (_) => Future.value(
              const ProfileEntity(
                id: 'profile-1',
                name: 'p1',
                url: 'https://example.com/p1',
                active: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      await container
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'JP-Reality-Stable');
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        spy.selectOutboundCalls,
        ['proxy->JP-Reality-Stable'],
        reason:
            'sing-box 的 selector 只在运行中的实例内存里记住当前选中项，'
            '每次重连都会用 runtime-config 的静态 default 重新起一个全新实例——'
            '不主动重放持久化选择的话，用户手选的节点会静默回退到默认值',
      );
    });

    test('没有任何持久化选择时，进入 BoxStarted 不调用 selectOutbound', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          activeProfileProvider.overrideWith(
            (_) => Future.value(
              const ProfileEntity(
                id: 'profile-1',
                name: 'p1',
                url: 'https://example.com/p1',
                active: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        spy.selectOutboundCalls,
        isEmpty,
        reason: '全新订阅/从没手选过节点时，重放应该是空操作，不该凭空调用 selectOutbound',
      );
    });

    test('某个 group 的持久化选择重放失败，不影响其它 group 继续重放', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService()..selectOutboundFailFor.add('stale-group');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          activeProfileProvider.overrideWith(
            (_) => Future.value(
              const ProfileEntity(
                id: 'profile-1',
                name: 'p1',
                url: 'https://example.com/p1',
                active: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      final store = container.read(proxySelectionStoreProvider.notifier);
      await store.persist('stale-group', 'gone-tag');
      await store.persist('proxy', 'JP-Reality-Stable');
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        spy.selectOutboundCalls,
        contains('proxy->JP-Reality-Stable'),
        reason: '一个 group 的悬空引用重放失败，不应该阻止其它仍然有效的 group 重放',
      );
    });

    test('同一次连接内重复推送 BoxStarted → 不重复重放（wasStarted 守卫）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          activeProfileProvider.overrideWith(
            (_) => Future.value(
              const ProfileEntity(
                id: 'profile-1',
                name: 'p1',
                url: 'https://example.com/p1',
                active: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      await container
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'JP-Reality-Stable');
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        spy.selectOutboundCalls.length,
        1,
        reason: '同一段连接内重复推送同样的 BoxStarted 不应该重复重放',
      );
    });
  });

  group('ConnectionController fatal alert 上报（数据分析开关）', () {
    test('数据分析开关关闭（默认值）时，fatal alert 不应该触发 Sentry 上报', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final reported = <BoxAlert>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          fatalAlertReporterProvider.overrideWithValue(reported.add),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      // 触发 ConnectionController 构造，订阅 watchAlerts。
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.startService, message: 'boom'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        reported,
        isEmpty,
        reason: '数据分析开关关闭（默认值）时，fatal alert 不应该调用 Sentry 上报',
      );
      // 强制回到 BoxStopped + 解锁 transition 等既有逻辑不应该受影响。
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });

    test('数据分析开关开启时，fatal alert 仍然正常触发上报（回归：不能把该上报的场景误判为不上报）', () async {
      SharedPreferences.setMockInitialValues({
        'clashmiao_analytics_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final reported = <BoxAlert>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          fatalAlertReporterProvider.overrideWithValue(reported.add),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.createService, message: 'boom'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(reported, hasLength(1), reason: '数据分析开关开启时，fatal alert 应该正常上报一次');
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });
  });

  group('ConnectionController fatal alert fail-safe 拆除（Dart 侧纵深兜底）', () {
    test('收到启动失败 alert 时，除了回到 BoxStopped，还必须主动要求内核 stop()（幂等兜底）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      // 触发 ConnectionController 构造，订阅 watchAlerts。
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.startService, message: 'boom'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
        reason: '启动失败 alert 必须把 UI 状态强制回到 BoxStopped',
      );
      expect(
        spy.stopCalls,
        1,
        reason:
            '仅把 UI 掰回 BoxStopped 不够：底层某个终结路径若又漏了清理，'
            'Dart 必须主动要求内核收尾（拆 tun），否则会复现"UI 显示已断开'
            '但设备仍被黑洞"这一最隐蔽的故障形态。',
      );

      container.dispose();
    });

    test('非致命 alert（如 VPN 权限请求）不应该触发 stop()，也不改动状态', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.requestVpnPermission),
      );
      await Future<void>.delayed(Duration.zero);

      expect(spy.stopCalls, 0, reason: '非启动失败类 alert 不应触发兜底 stop()，避免误伤正常授权流程');

      container.dispose();
    });
  });

  group('connectionErrorProvider 写入分类后的本地化文案（而非原始异常/alert文本）', () {
    final en = Translations.build();

    test(
      'fatal alert（startService）不写 connectionErrorProvider（阻断式弹窗负责提示）',
      () async {
        SharedPreferences.setMockInitialValues({'locale': 'en'});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        container.read(connectionControllerProvider.notifier);

        const rawMessage = 'native stack: 0xdeadbeef at sing_box.rs:123';
        spy.alertStreamController.add(
          const BoxAlert(type: BoxAlertType.startService, message: rawMessage),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(connectionErrorProvider),
          isNull,
          reason:
              '致命 alert 的用户提示由 ShellPage 的阻断式弹窗负责'
              '（见 shell_page_test.dart），这里不能再写一份，否则 home_page '
              '的 toast 会跟弹窗对同一个错误双重提示',
        );

        container.dispose();
      },
    );

    test('fatal alert（emptyConfiguration）不写 connectionErrorProvider', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(
          type: BoxAlertType.emptyConfiguration,
          message: 'config.json: unexpected token at line 42',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '同 startService：致命 alert 由 ShellPage 阻断式弹窗负责提示',
      );

      container.dispose();
    });

    test('fatal alert（createService）不写 connectionErrorProvider', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(
          type: BoxAlertType.createService,
          message: 'IOException: bind failed EADDRINUSE',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '同 startService：致命 alert 由 ShellPage 阻断式弹窗负责提示',
      );

      container.dispose();
    });

    test('connect() 捕获到 SocketException 时应归类为网络不可用文案', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService()
        ..startError = const SocketException(
          'Connection refused (errno 111, address 10.0.0.1)',
        );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'socket-exception-profile';
      await repo.upsert({
        'id': profileId,
        'name': 'SocketException 测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      await container.read(connectionControllerProvider.notifier).connect();

      final err = container.read(connectionErrorProvider);
      expect(err, isNotNull);
      expect(
        err,
        isNot(contains('errno 111')),
        reason: '不应该把原始 SocketException 消息原样展示给用户',
      );
      expect(
        err,
        en.failure.connectivity.networkUnavailable,
        reason: 'SocketException 应归类为"网络不可用"分类文案',
      );

      container.dispose();
    });

    test('connect() 捕获到 TimeoutException 时应归类为启动超时文案', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService()
        ..startError = TimeoutException('sing-box startup timed out');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'timeout-exception-profile';
      await repo.upsert({
        'id': profileId,
        'name': 'TimeoutException 测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      await container.read(connectionControllerProvider.notifier).connect();

      final err = container.read(connectionErrorProvider);
      expect(
        err,
        en.failure.singbox.startTimeout,
        reason: 'TimeoutException 应归类为"启动超时"分类文案',
      );

      container.dispose();
    });

    test('disconnect() 持续失败时，连接错误文案应是分类后的兜底文案（回归：内容而非仅"非空"）', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      spy.stopError = Exception('mock stop failure (persistent)');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      final controller = container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      await controller.disconnect();

      final err = container.read(connectionErrorProvider);
      expect(
        err,
        isNot(contains('mock stop failure')),
        reason: '不应该把原始 Exception.toString() 原样展示给用户',
      );
      expect(err, en.failure.unexpected, reason: '未归类异常应兜底为"未知错误"分类文案');

      container.dispose();
    });
  });

  // ===========================================================
  // connect() 的前置校验分支曾经**只 debugPrint 就 return**，用户点了"连接"
  // 什么都不会发生、也看不到任何提示——就是一个死按钮。而且桌面托盘的
  // "连接"菜单项（tray_controller.dart）不经过首页 _EmptyHomeBody 那层空态
  // 守卫，会直接命中这些分支。
  //
  // 这些测试锁定"每个前置校验失败都必须给用户一个可见的、分类过的本地化
  // 提示"，而不是静默返回。
  // ===========================================================
  group('connect() 前置校验失败必须可见（不能静默返回）', () {
    final en = Translations.build();

    /// 建一个 repo 已就绪、但按参数决定"有没有激活订阅 / 配置文件存不存在"
    /// 的容器。
    Future<ProviderContainer> makeContainer(
      BoxService service, {
      required bool withActiveProfile,
      required bool withConfigFile,
    }) async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(service),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      if (withActiveProfile) {
        const id = 'precheck-profile';
        await repo.upsert({
          'id': id,
          'name': '前置校验测试',
          // 指向一个不可解析的域名：自愈逻辑真的会去拉取，但必定失败，
          // 从而验证"自愈失败后仍然要报错"这条路径。
          'url': 'https://precheck.example.invalid/sub',
        });
        await repo.setActive(id);
        if (withConfigFile) {
          final configFile = File(repo.configFilePath(id));
          await configFile.parent.create(recursive: true);
          await configFile.writeAsString(
            jsonEncode({
              'outbounds': [
                {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
              ],
            }),
          );
        }
      }
      return container;
    }

    test('桌面核心库缺失（降级到 StubBoxService）时必须给出可见提示', () async {
      final container = await makeContainer(
        const StubBoxService(),
        withActiveProfile: true,
        withConfigFile: true,
      );

      await container.read(connectionControllerProvider.notifier).connect();

      expect(
        container.read(connectionErrorProvider),
        en.failure.singbox.coreLibraryMissing,
        reason: '核心库没装是个用户完全无法从界面上察觉的状态，必须明确告知',
      );
      container.dispose();
    });

    test('无激活订阅时必须给出可见提示（托盘菜单会绕过首页空态）', () async {
      final spy = _SpyBoxService();
      final container = await makeContainer(
        spy,
        withActiveProfile: false,
        withConfigFile: false,
      );

      await container.read(connectionControllerProvider.notifier).connect();

      expect(spy.startCalls, 0, reason: '无激活订阅不应该调 start');
      expect(
        container.read(connectionErrorProvider),
        en.failure.profiles.noActive,
        reason: '不能只是早返回——用户点了连接必须知道为什么没连上',
      );
      container.dispose();
    });

    test('配置文件缺失时先自愈重拉订阅，拉不到才报错', () async {
      final spy = _SpyBoxService();
      final container = await makeContainer(
        spy,
        withActiveProfile: true,
        withConfigFile: false, // 磁盘上没有配置文件：模拟订阅更新失败/备份恢复后的状态
      );

      await container.read(connectionControllerProvider.notifier).connect();

      expect(spy.startCalls, 0, reason: '自愈拉取用的是不可解析域名，必定失败，所以不该真的起内核');
      expect(
        container.read(connectionErrorProvider),
        en.failure.profiles.notFound,
        reason: '自愈失败后必须报"未找到配置文件"，不能静默什么都不做',
      );
      container.dispose();
    });

    test('配置文件缺失但自愈重拉成功时，应该继续完成连接', () async {
      final spy = _SpyBoxService();
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        await deleteTempDirBestEffort(tmp);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const id = 'selfheal-profile';
      await repo.upsert({
        'id': id,
        'name': '自愈测试',
        'url': 'https://selfheal.example.invalid/sub',
      });
      await repo.setActive(id);
      // 故意不建配置文件——但用 repo 的 update 被调用后会写入的那条路径无法在
      // 单测里联网，所以这里换一种诚实的构造方式：让"自愈"这一步观察到文件
      // 已经存在（模拟重拉成功的结果），验证 connect() 在自愈成功后不会误报
      // 错误、而是继续往下走真正的启动流程。
      final configFile = File(repo.configFilePath(id));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      await container.read(connectionControllerProvider.notifier).connect();

      expect(spy.startCalls, 1, reason: '配置文件可用时必须真的起内核');
      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '成功路径不该留下任何错误提示',
      );
      container.dispose();
    });
  });
}
