import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/utils/config_parser.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/config/runtime_config_builder.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============ Profile Providers ============

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final profileRepositoryProvider = FutureProvider<ProfileRepository>((
  ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final appDir = await getApplicationDocumentsDirectory();

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  // 跳过系统代理直连，避免正在运行的 sing-box 代理干扰订阅下载。
  // TLS 证书仍使用系统默认校验；生产环境不能接受任意证书。
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      return client;
    },
  );

  final boxService = ref.watch(boxServiceProvider);

  return ProfileRepository(
    dio: dio,
    configDir: Directory(appDir.path),
    prefs: prefs,
    boxService: boxService,
  );
});

/// 所有订阅列表
final profileListProvider = FutureProvider<List<ProfileEntity>>((ref) async {
  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getAll();
});

/// 当前激活订阅
final activeProfileProvider = FutureProvider<ProfileEntity?>((ref) async {
  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getActive();
});

// ============ 离线代理解析 ============

/// 从配置文件解析代理组（不依赖核心库）
final offlineProxyGroupsProvider = FutureProvider<List<OutboundGroup>>((
  ref,
) async {
  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return [];

  final repo = await ref.read(profileRepositoryProvider.future);
  final configPath = repo.configFilePath(profile.id);
  final file = File(configPath);
  if (!await file.exists()) return [];
  return ConfigParser.parseFile(configPath);
});

// ============ Connection Controller ============

class ConnectionController extends StateNotifier<AsyncValue<BoxStatus>> {
  ConnectionController(this._ref) : super(const AsyncData(BoxStopped())) {
    // 监听核心层的实时状态推送
    final service = _ref.read(boxServiceProvider);
    if (service is! StubBoxService) {
      _statusSub = service.watchStatus().listen(
        (status) {
          if (!mounted) return;
          // 过渡动画期间允许 final state（BoxStarted / BoxStopped）穿透，
          // 但忽略中间态（BoxStarting / BoxStopping），避免抖动 UI。
          // 之前的 `if (_transitioning) return` 把真实 BoxStarted 也拦了，
          // 导致 connect() 1.5s 后手动写 BoxStarted —— 但 native sing-box
          // 实际可能还没起来，状态就成了"假已连接"。
          if (_transitioning &&
              (status is BoxStarting || status is BoxStopping)) {
            return;
          }
          state = AsyncData(status);
          _syncStartedAt(status);
        },
        onError: (e) {
          debugPrint('watchStatus 错误: $e');
        },
      );

      // sing-box 启动 / 创建 service 失败时核心会推 alert，
      // 但 watchStatus 在 _transitioning 期间被忽略 → state 还停留在
      // delayed BoxStarted，UI 显示"已连接"但其实没在跑。
      // 收到这类启动失败 alert 时强制回到 BoxStopped + 解锁 transition。
      _alertSub = service.watchAlerts().listen((alert) {
        if (!mounted) return;
        final isFatal =
            alert.type == BoxAlertType.startService ||
            alert.type == BoxAlertType.createService ||
            alert.type == BoxAlertType.emptyConfiguration;
        if (!isFatal) return;
        const dsn = String.fromEnvironment('SENTRY_DSN');
        if (dsn.isNotEmpty) {
          unawaited(
            Sentry.captureMessage(
              'BoxAlert fatal: ${alert.type.name}',
              level: SentryLevel.error,
            ),
          );
        }
        _transitioning = false;
        state = const AsyncData(BoxStopped());
        _ref.read(connectionErrorProvider.notifier).state =
            alert.message ?? alert.type.name;
      });

      _networkSub = service.watchNetworkChanged().listen((_) {
        if (!mounted) return;
        if (state.valueOrNull is BoxStarted) {
          unawaited(_autoReconnect());
        }
      });
    }
    // 内部 state setter 也走 _syncStartedAt（addListener 监听本 notifier）
    addListener((value) {
      final s = value.valueOrNull;
      if (s != null) _syncStartedAt(s);
    });
  }

  /// 跟 connectionStartedAtProvider 同步：进入 Started 时记录时间，离开时清零。
  void _syncStartedAt(BoxStatus status) {
    final prov = _ref.read(connectionStartedAtProvider.notifier);
    if (status is BoxStarted) {
      // 已有时间戳就不覆盖（避免重复 listener 重置）
      if (prov.state == null) {
        prov.state = DateTime.now();
      }
    } else if (status is BoxStopped) {
      if (prov.state != null) prov.state = null;
    }
  }

  final Ref _ref;
  StreamSubscription? _statusSub;
  StreamSubscription? _alertSub;
  StreamSubscription<void>? _networkSub;
  bool _transitioning = false;

  bool get isStarted => state.valueOrNull is BoxStarted;

  BoxService get _boxService => _ref.read(boxServiceProvider);
  bool get _isStub => _boxService is StubBoxService;

  @override
  void dispose() {
    _statusSub?.cancel();
    _alertSub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }

  /// 切换连接状态
  Future<void> toggle() async {
    final currentStatus = state.valueOrNull;
    debugPrint('toggle 当前状态: $currentStatus');

    if (currentStatus is BoxStarting || currentStatus is BoxStopping) {
      debugPrint('正在切换中，忽略');
      return;
    }

    if (currentStatus is BoxStarted) {
      await disconnect();
    } else {
      await connect();
    }
  }

  /// 连接
  Future<void> connect() async {
    if (_isStub) {
      debugPrint('核心库未安装，无法连接');
      return;
    }

    // 获取 ProfileRepository
    final repoAsync = _ref.read(profileRepositoryProvider);
    if (!repoAsync.hasValue) {
      debugPrint('ProfileRepository 未就绪');
      return;
    }
    final repo = repoAsync.requireValue;

    // 获取激活订阅
    final active = repo.getActive();
    if (active == null) {
      debugPrint('无激活订阅，请先添加订阅');
      return;
    }

    // 检查配置文件存在
    final configPath = repo.configFilePath(active.id);
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      debugPrint('配置文件不存在: $configPath');
      return;
    }

    _transitioning = true;
    state = const AsyncData(BoxStarting());
    try {
      // 读用户当前选的 mode（0=全局，1=智能），决定要不要走分流
      final modeIndex = _ref.read(proxyModeProvider);
      final isGlobal = modeIndex == 0;

      // 连接前推送 fork-side options（关键：region='other' 已经在 default 写死，
      // 这里 executeConfigAsIs 跟用户选择对齐，留给后续可能扩展使用）。
      await _boxService.changeConfigOptions(
        jsonEncode(
          getDefaultConfigOptions(
            executeConfigAsIs: isGlobal,
            settings: _ref.read(networkSettingsProvider),
            advancedConfig: active.advancedConfig,
          ),
        ),
      );

      // 现场组装 runtime-config.json（注入 / 剥离 rule-set），native 加载这个。
      final workingDir = await getApplicationDocumentsDirectory();
      final settings = _ref.read(networkSettingsProvider);
      final runtimeConfig = await RuntimeConfigBuilder().build(
        baseProfile: configFile,
        isSmart: !isGlobal,
        workingDir: workingDir,
        remoteDnsAddress: settings.remoteDnsAddress,
        advancedConfig: active.advancedConfig,
      );

      await _boxService.start(runtimeConfig.path, name: active.name);
      // 让 BoxStarting 动画至少展示 1.5s，期间锁住 _transitioning。
      // 之后**不**手动写 BoxStarted —— 真实 BoxStarted 由 watchStatus
      // 在 native sing-box 实际起来（VpnService 接管流量、TUN 建好）后推送。
      // 这之前如果 user 没点 VPN dialog / sing-box 启动失败，会停在 BoxStarting，
      // 由 watchAlerts 的 fatal alert 强制回到 BoxStopped。
      await Future.delayed(const Duration(milliseconds: 1500));
    } catch (e) {
      final errMsg = e.toString();
      if (errMsg.contains('instance not stopped')) {
        try {
          await _boxService.stop();
          await Future.delayed(const Duration(milliseconds: 500));
          // 重试也用 runtime-config（避免 fallback 到 profile 原文丢失分流配置）
          final modeIndex = _ref.read(proxyModeProvider);
          final workingDir = await getApplicationDocumentsDirectory();
          final settings = _ref.read(networkSettingsProvider);
          final runtimeConfig = await RuntimeConfigBuilder().build(
            baseProfile: configFile,
            isSmart: modeIndex != 0,
            workingDir: workingDir,
            remoteDnsAddress: settings.remoteDnsAddress,
            advancedConfig: active.advancedConfig,
          );
          await _boxService.start(runtimeConfig.path, name: active.name);
          await Future.delayed(const Duration(milliseconds: 1500));
          // 同上：不手动写 BoxStarted，让 watchStatus 推真实状态。
          return;
        } catch (retryErr) {
          _ref.read(connectionErrorProvider.notifier).state = retryErr
              .toString();
        }
      } else {
        _ref.read(connectionErrorProvider.notifier).state = e.toString();
      }
      state = const AsyncData(BoxStopped());
    } finally {
      _transitioning = false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_isStub) return;

    _transitioning = true;
    state = const AsyncData(BoxStopping());
    try {
      await _boxService.stop();
      // 至少展示 1.5秒 断开中动画
      await Future.delayed(const Duration(milliseconds: 1500));
      state = const AsyncData(BoxStopped());
    } catch (e) {
      // stop 失败时内核可能还在跑：UI 回 Stopped 让用户能重试，
      // 但错误必须可见（之前静默吞掉导致"显示已断开、流量还在走"无法排查）。
      debugPrint('disconnect 失败: $e');
      _ref.read(connectionErrorProvider.notifier).state = e.toString();
      state = const AsyncData(BoxStopped());
    } finally {
      _transitioning = false;
    }
  }

  /// 重连（用 restart 原子操作，避免 stop+start 竞态）
  ///
  /// 必须用 RuntimeConfigBuilder 现场拼好的 runtime-config.json，
  /// 否则切换"全局/智能"时分流配置不生效（restart 直接拿原始 profile
  /// 等于退回到 profile 自带的 rule-set 引用，可能 fetch 远端 GFW-blocked
  /// 资源、或者全局模式下没剥离 hiddify-fork 的兜底 default，效果不可预期）。
  Future<void> reconnect() async {
    if (_isStub) return;
    _ref.read(connectionErrorProvider.notifier).state = null;
    final repoAsync = _ref.read(profileRepositoryProvider);
    if (!repoAsync.hasValue) return;
    final repo = repoAsync.requireValue;
    final active = repo.getActive();
    if (active == null) return;

    final configFile = File(repo.configFilePath(active.id));
    if (!await configFile.exists()) {
      debugPrint('重连: 配置文件不存在 ${configFile.path}');
      return;
    }

    state = const AsyncData(BoxStarting());
    try {
      final modeIndex = _ref.read(proxyModeProvider);
      final isGlobal = modeIndex == 0;
      // mode 可能在两次 connect 之间变了；先把 options 重推一遍
      await _boxService.changeConfigOptions(
        jsonEncode(
          getDefaultConfigOptions(
            executeConfigAsIs: isGlobal,
            settings: _ref.read(networkSettingsProvider),
            advancedConfig: active.advancedConfig,
          ),
        ),
      );
      final workingDir = await getApplicationDocumentsDirectory();
      final settings = _ref.read(networkSettingsProvider);
      final runtimeConfig = await RuntimeConfigBuilder().build(
        baseProfile: configFile,
        isSmart: !isGlobal,
        workingDir: workingDir,
        remoteDnsAddress: settings.remoteDnsAddress,
        advancedConfig: active.advancedConfig,
      );
      debugPrint('重连: restart ${runtimeConfig.path}');
      await _boxService.restart(runtimeConfig.path, name: active.name);
      debugPrint('restart 完成');
      // 不手动写 BoxStarted（跟 connect 同一原则）：restart 调用返回只代表
      // 命令送达，native sing-box 是否真起来由 watchStatus 推送决定。之前
      // "2s 后仍 Starting 就标 Started" 会在启动实际失败时伪装成功，
      // 让 _autoReconnect 误判恢复而停止退避。这里等一个观察窗口即可，
      // 真实失败由 watchAlerts 的 fatal alert 拉回 BoxStopped。
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('重连失败: $e');
      state = const AsyncData(BoxStopped());
    }
  }

  bool _autoReconnecting = false;

  Future<void> _autoReconnect() async {
    // 网络抖动（WiFi↔蜂窝快速切换）会连发多个 network_changed 事件，
    // 不加闸门会并发跑多个退避循环、reconnect/restart 互相竞态。
    if (_autoReconnecting) return;
    _autoReconnecting = true;
    try {
      const delays = [1, 2, 4, 8];
      for (final d in delays) {
        await Future.delayed(Duration(seconds: d));
        if (!mounted) return;
        if (state.valueOrNull is BoxStarted) return; // already recovered
        try {
          await reconnect();
          if (state.valueOrNull is BoxStarted) return;
        } catch (e) {
          debugPrint('[AutoReconnect] attempt failed: $e');
        }
      }
      debugPrint('[AutoReconnect] exhausted all 4 attempts');
    } finally {
      _autoReconnecting = false;
    }
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, AsyncValue<BoxStatus>>((ref) {
      final controller = ConnectionController(ref);
      // 网络设置（端口 / TUN / LAN / DNS）变更后，正在跑的 sing-box 仍用旧值，
      // 必须 reconnect 才生效——之前要求用户手动断开重连，跟设置页
      // "改完即生效"的预期不符。listen 放 provider 体内（StateNotifier 内部
      // 拿不到 ref.listen），连接中才触发，未连接时改设置无副作用。
      ref.listen(networkSettingsProvider, (prev, next) {
        if (prev == null || identical(prev, next)) return;
        if (controller.isStarted) {
          unawaited(controller.reconnect());
        }
      });
      return controller;
    });

/// 最近一次 connect/reconnect 失败的错误信息（人类可读 string）。
///
/// 用 string 而不是 Exception 是为了能从 `valueOrNull == null` 区分"没失败过"
/// 和"刚失败"两种状态。UI 通过 listen 拿到变化弹 toast 之后应该
/// `.state = null` 把它清空。
final connectionErrorProvider = StateProvider<String?>((_) => null);

/// 进入 BoxStarted 时记录的时间戳（用来算"已连接 N 分钟"）。
/// 由 ConnectionController 在 state 变 Started 时设置，断开时清零。
final connectionStartedAtProvider = StateProvider<DateTime?>((_) => null);

/// sing-box 实时日志流。
///
/// 移动端使用原生 service.logs EventChannel；桌面端保留 box.log 文件轮询。
final boxLogStreamProvider = StreamProvider<List<String>>((ref) async* {
  if (Platform.isAndroid || Platform.isIOS) {
    yield* ref.watch(boxServiceProvider).watchLogs('');
    return;
  }

  final docsDir = await getApplicationDocumentsDirectory();
  final logFile = File('${docsDir.path}/box.log');
  // 第一帧立即 yield 当前内容（若有），之后每 1.5s 重读
  String? prev;
  while (true) {
    if (await logFile.exists()) {
      final content = await logFile.readAsString();
      if (content != prev) {
        prev = content;
        // 只保留最后 500 行，避免 UI 卡死
        final lines = const LineSplitter().convert(content);
        yield lines.length > 500 ? lines.sublist(lines.length - 500) : lines;
      }
    } else {
      yield const [];
    }
    await Future.delayed(const Duration(milliseconds: 1500));
  }
});
