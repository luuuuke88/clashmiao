import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/connection_error_classifier.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/utils/config_parser.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/config/runtime_config_builder.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';

import 'package:flutter/foundation.dart';
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

  // 核心 bug 修复：此前这里硬编码 `findProxy = (_) => 'DIRECT'`，订阅刷新
  // 永远直连、绝不经过本地隧道。如果订阅源本身是那种必须经隧道才能访问的
  // 服务器（比如被墙的域名，只有连上 VPN 后才能访问），订阅刷新会在隧道
  // 明明健康可用的情况下必定失败。改成 `preferTunnel: true`：优先尝试
  // 通过本地 sing-box 的 mixed 代理端口发出请求，连接失败（sing-box 未启动 /
  // mixed 端口未监听）时自动降级直连——两种场景都能覆盖，不再是"永远直连"
  // 这一种。TLS 证书仍使用系统默认校验；生产环境不能接受任意证书。
  final mixedPort = ref.read(networkSettingsProvider).mixedPort;
  final dio = createAppHttpClient(preferTunnel: true, mixedPort: mixedPort);

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
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_EMPTY_PROFILES')) {
    return const [];
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROFILE_LIST')) {
    return _debugProfileList;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_NO_ACTIVE_PROFILE')) {
    return _debugNoActiveProfileList;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_PROFILE')) {
    return [_debugHomeProfile];
  }

  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getAll();
});

/// 当前激活订阅
final activeProfileProvider = FutureProvider<ProfileEntity?>((ref) async {
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_EMPTY_PROFILES')) {
    return null;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROFILE_LIST')) {
    return _debugProfileList.first;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_NO_ACTIVE_PROFILE')) {
    return null;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_PROFILE')) {
    return _debugHomeProfile;
  }

  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getActive();
});

final _debugHomeProfile = ProfileEntity(
  id: 'debug-home-profile',
  name: 'ClashMiao Pro',
  url: 'https://example.com/debug-sub',
  active: true,
  subInfo: SubscriptionInfo(
    upload: 2 * 1024 * 1024 * 1024,
    download: 28 * 1024 * 1024 * 1024,
    total: 120 * 1024 * 1024 * 1024,
    expire: DateTime(2026, 12, 31),
  ),
);

final _debugProfileList = [
  _debugHomeProfile,
  ProfileEntity(
    id: 'debug-profile-no-subinfo',
    name: '无订阅信息',
    url: 'https://example.com/no-sub',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 10),
  ),
  ProfileEntity(
    id: 'debug-local-profile',
    name: '本地导入',
    url: 'content://local-debug-config',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 20),
  ),
];

final _debugNoActiveProfileList = [
  ProfileEntity(
    id: 'debug-no-active-remote',
    name: 'ClashMiao Pro',
    url: 'https://example.com/debug-sub',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 20),
  ),
  ProfileEntity(
    id: 'debug-no-active-local',
    name: '本地导入',
    url: 'content://local-debug-config',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 30),
  ),
];

// ============ 离线代理解析 ============

/// 从配置文件解析代理组（不依赖核心库）
final offlineProxyGroupsProvider = FutureProvider<List<OutboundGroup>>((
  ref,
) async {
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROXY_FIXTURE')) {
    return const [
      OutboundGroup(
        tag: 'proxy',
        type: 'selector',
        selected: '香港 01 | SS',
        items: [
          OutboundProxy(tag: 'Auto', type: 'urltest', delay: 86),
          OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks', delay: 128),
          OutboundProxy(tag: '日本 Tokyo 02', type: 'vmess', delay: 241),
          OutboundProxy(tag: 'US Los Angeles 03', type: 'vless', delay: 618),
          OutboundProxy(tag: 'Singapore 04', type: 'trojan'),
        ],
      ),
    ];
  }

  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return [];

  final repo = await ref.read(profileRepositoryProvider.future);
  final configPath = repo.configFilePath(profile.id);
  final file = File(configPath);
  if (!await file.exists()) return [];
  return ConfigParser.parseFile(configPath);
});

// ============ Fatal Alert 上报 ============

/// Fatal [BoxAlert] 的上报回调类型。抽成可覆盖的 provider 是为了在纯 Dart
/// 测试环境里能注入一个记录调用次数的 fake，绕开"直接 mock 静态方法
/// `Sentry.captureMessage`"在这套测试框架里不可行的限制。
typedef FatalAlertReporter = void Function(BoxAlert alert);

/// 默认实现：真的调用 Sentry。是否发送仍然只由编译期 `SENTRY_DSN` 决定
/// （SDK 是否存在是启动期一次性决定，见 main.dart 里 `_sentryDsn` 的判断，
/// 这里不重复决定"要不要 init"，只决定"SDK 存在时这一条要不要发"）。
/// 运行时"数据分析"开关的判断在调用方
/// [ConnectionController._shouldReportAnalytics] 完成，这里不重复读取。
final fatalAlertReporterProvider = Provider<FatalAlertReporter>((ref) {
  return (alert) {
    const dsn = String.fromEnvironment('SENTRY_DSN');
    if (dsn.isEmpty) return;
    unawaited(
      Sentry.captureMessage(
        'BoxAlert fatal: ${alert.type.name}',
        level: SentryLevel.error,
      ),
    );
  };
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
          // connect() 出于同样的原因故意不手动写 BoxStarted（见上方注释），
          // 真正的"连接成功"只会从这里、拿到 native 确认的状态时发生，
          // 所以触觉反馈也只能挂在这个点，且只在真正"进入" Started 时触发一次
          // （wasStarted 守卫），避免同一状态重复推送时反复震动。
          final wasStarted = state.valueOrNull is BoxStarted;
          state = AsyncData(status);
          _syncStartedAt(status);
          if (!wasStarted && status is BoxStarted) {
            unawaited(_ref.read(hapticServiceProvider).heavyImpact());
            // 首次成功连接后请求一次商店评分弹窗。"这辈子只弹一次"的持久化
            // 保护在 StoreReviewService 内部完成，这里跟触觉反馈一样，每次
            // 真正"进入" BoxStarted 都调用，不在这一层重复判断。
            unawaited(_ref.read(storeReviewServiceProvider).maybeRequestReview());
          }
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
        if (!alert.type.isFatal) return;
        // 设置页"数据分析"开关关闭时（默认即关闭）不应该真的上报，
        // 哪怕 Sentry SDK 已经编译进来（SENTRY_DSN 非空）。
        if (_shouldReportAnalytics()) {
          _ref.read(fatalAlertReporterProvider)(alert);
        }
        _transitioning = false;
        state = const AsyncData(BoxStopped());
        // 幂等纵深兜底：既然报了 BoxStopped，就必须真的要求内核收尾，而不只是
        // 掰 UI。即便原生某个终结路径又漏了清理（拆 tun / stopSelf），Dart 也
        // 主动发一次 stop()，避免复现"UI 显示已断开、设备仍被黑洞"。若原生已
        // 清理干净，这一次 stop() 是幂等空操作。与 disconnect() 里"绝不谎报
        // BoxStopped"的既有原则一致。
        unawaited(_boxService.stop());
        // 故意不写 connectionErrorProvider：致命 alert 的用户提示由
        // ShellPage 的 boxAlertsProvider 监听器负责（阻断式弹窗，见
        // shell_page.dart）。这里如果再写一份，home_page 的 toast 监听会
        // 跟弹窗同时冒出来，同一个错误双重提示。connectionErrorProvider
        // 保留给 connect()/disconnect() 的异常路径——那些没有 alert 流经过，
        // toast 是唯一出口。
      });

      _networkSub = service.watchNetworkChanged().listen((_) {
        if (!mounted) return;
        if (_manualDisconnect) return; // 用户已手动断开，网络恢复不该触发自动重连
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

  /// 运行时读取设置页"数据分析"开关（onboarding 页写入同一个 key），
  /// 决定 fatal alert 是否真的上报给 Sentry。默认值需要和
  /// settings_page.dart 里 `_BoolPreferenceTile(prefKey:
  /// 'clashmiao_analytics_enabled', defaultValue: false)` 保持一致
  /// （onboarding_page.dart 的 `_BoolPreferenceNotifier` 默认值同为
  /// false，两处一致，都是默认不上报）。
  ///
  /// [sharedPreferencesProvider] 是 FutureProvider，这里是 watchAlerts
  /// 回调的同步上下文，只能读已经 resolve 的值（`valueOrNull`）；prefs
  /// 还没就绪时保守起见按"不上报"处理，不等待 / 不阻塞。
  bool _shouldReportAnalytics() {
    final prefs = _ref.read(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return false;
    return prefs.getBool('clashmiao_analytics_enabled') ?? false;
  }

  final Ref _ref;
  StreamSubscription? _statusSub;
  StreamSubscription? _alertSub;
  StreamSubscription<void>? _networkSub;
  bool _transitioning = false;

  /// 用户主动断开的意图标志。disconnect() 置 true，connect() 置 false。
  /// 用于阻止 _autoReconnect 退避循环在网络切换重连窗口期内把用户刚断开的
  /// 连接顶回去——网络恢复和用户没断开是两件独立的事，不能只用
  /// state is BoxStarted 一个谓词表达。
  bool _manualDisconnect = false;

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
    _manualDisconnect = false; // 用户发起连接，清除手动断开意图

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
      // iOS 上必须落在 App Group 共享容器，见
      // resolveSingBoxWorkingDirectory 文档（main.dart 首次 provision
      // rule-set 用的是同一个函数，两处目录必须一致，否则这里嵌进
      // runtime-config.json 的 rule_set 绝对路径会指向不存在的文件）。
      final workingDir = await resolveSingBoxWorkingDirectory();
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
          final workingDir = await resolveSingBoxWorkingDirectory();
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
          _ref.read(connectionErrorProvider.notifier).state =
              classifyExceptionMessage(
                retryErr,
                _ref.read(translationsProvider),
              );
        }
      } else {
        _ref.read(connectionErrorProvider.notifier).state =
            classifyExceptionMessage(e, _ref.read(translationsProvider));
      }
      state = const AsyncData(BoxStopped());
    } finally {
      _transitioning = false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_isStub) return;

    _manualDisconnect = true; // 用户主动断开：阻止 autoReconnect 把连接顶回去
    _transitioning = true;
    state = const AsyncData(BoxStopping());
    try {
      await _boxService.stop();
      // 至少展示 1.5秒 断开中动画
      await Future.delayed(const Duration(milliseconds: 1500));
      state = const AsyncData(BoxStopped());
      unawaited(_ref.read(hapticServiceProvider).mediumImpact());
    } catch (e) {
      // stop 失败时内核可能还在跑：绝不能谎报 BoxStopped——那是本 App 最不能
      // 接受的故障形态（界面显示已断开，流量还在走）。错误必须可见（之前静默
      // 吞掉导致这类问题无法排查），同时做一次"强制清理"重试：disconnect()
      // 会在退出流程里被调用（见 tray_controller.dart quit 分支），那个调用点
      // 已经 try/catch 吞掉异常直接销毁窗口/退出，用户没有"再点一次断开"的
      // 机会，所以不能只依赖用户手动重试，这里自己再兜底试一次 stop()。
      debugPrint('disconnect 失败: $e');
      _ref.read(connectionErrorProvider.notifier).state = classifyExceptionMessage(
        e,
        _ref.read(translationsProvider),
      );
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        await _boxService.stop();
        // 重试确认停掉了，这时候设 BoxStopped 才是诚实的。
        state = const AsyncData(BoxStopped());
        unawaited(_ref.read(hapticServiceProvider).mediumImpact());
      } catch (retryErr) {
        debugPrint('disconnect 重试仍失败: $retryErr');
        _ref.read(connectionErrorProvider.notifier).state =
            classifyExceptionMessage(
              retryErr,
              _ref.read(translationsProvider),
            );
        // 重试也失败：仍然不能报 BoxStopped。诚实地倾向认为还连着，UI 会显示
        // "仍连接 + 错误"，用户可以再点一次断开重试（disconnect 本身可重入，
        // toggle() 里 currentStatus is BoxStarted 会再次走 disconnect 分支）。
        // 如果 native 其实已经停了，watchStatus 之后会推真实的 BoxStopped
        // 自动纠正（_transitioning 在 finally 解锁后，终态可以穿透
        // _statusSub 对中间态的过滤）。
        state = const AsyncData(BoxStarted());
      }
    } finally {
      _transitioning = false;
    }
  }

  /// 重连（用 restart 原子操作，避免 stop+start 竞态）
  ///
  /// 必须用 RuntimeConfigBuilder 现场拼好的 runtime-config.json，
  /// 否则切换"全局/智能"时分流配置不生效（restart 直接拿原始 profile
  /// 等于退回到 profile 自带的 rule-set 引用，可能 fetch 远端 GFW-blocked
  /// 资源、或者全局模式下没剥离旧配置里的兜底 default，效果不可预期）。
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
      final workingDir = await resolveSingBoxWorkingDirectory();
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
        if (_manualDisconnect) return; // 退避窗口内用户已手动断开，停止重试
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
          // 静默重连之前完全没有提示，用户容易把这次自动重连误当成网络抖动。
          // 递增这个 nonce 让 UI（HomePage）能感知到"这次重连是配置变更触发
          // 的"，从而弹一条轻提示，而不是阻断式弹窗。
          ref.read(configChangeReconnectNoticeProvider.notifier).state++;
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

/// 配置（网络设置）变更触发自动重连的通知 nonce。
///
/// [connectionControllerProvider] 监听 [networkSettingsProvider] 变化，已连接
/// 时会静默调用 [ConnectionController.reconnect]——用户如果毫无提示，可能会把
/// 这次重连误当成网络抖动故障。这里用单调递增的 int 而不是 bool/文本，是因为
/// UI（[HomePage]）要用 `ref.listen` 监听变化去弹一条轻量 toast；如果用不变
/// 的 bool/字符串，连续两次配置变更之间取值相同，Riverpod 不会重新触发
/// listen 回调，第二次提示就会被吃掉。
final configChangeReconnectNoticeProvider = StateProvider<int>((_) => 0);

/// 进入 BoxStarted 时记录的时间戳（用来算"已连接 N 分钟"）。
/// 由 ConnectionController 在 state 变 Started 时设置，断开时清零。
final connectionStartedAtProvider = StateProvider<DateTime?>((_) => null);

/// sing-box 实时日志流。
///
/// 移动端使用原生 service.logs EventChannel；桌面端参照 sing-box 的日志
/// 文件轮询实现，保留 box.log 文件轮询。
///
/// autoDispose：日志页关闭、没有任何 watcher 时应该停止轮询——否则桌面端
/// 这个 while(true) 文件轮询循环会常驻内存持续消耗 CPU 和文件 IO，即使
/// 用户再也不会打开日志页。
final boxLogStreamProvider = StreamProvider.autoDispose<List<String>>((
  ref,
) async* {
  if (kDebugMode && const bool.fromEnvironment('CLASHMIAO_DEBUG_LOG_FIXTURE')) {
    yield const [
      '2026-06-12 23:58:01 INFO service started',
      '2026-06-12 23:58:02 DEBUG route rule matched proxy',
      '2026-06-12 23:58:03 WARN dns fallback used',
      '2026-06-12 23:58:04 ERROR outbound dial failed: timeout',
    ];
    return;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    yield* ref.watch(boxServiceProvider).watchLogs('');
    return;
  }

  final docsDir = await getApplicationDocumentsDirectory();
  final logFile = File('${docsDir.path}/box.log');
  // provider 被 dispose 时（离开日志页），停掉这个循环。文件内容不变的
  // tick 里循环体走不到任何 yield，光靠"stream 订阅被取消时在下一个
  // yield 处停止"这套 async* 内建机制救不了这种情况，必须显式检查。
  var disposed = false;
  ref.onDispose(() => disposed = true);
  // 第一帧立即 yield 当前内容（若有），之后每 1.5s 重读
  String? prev;
  while (true) {
    if (disposed) return;
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
