import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
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
  // 忽略自签名证书 + 跳过系统代理直连（避免 sing-box 代理干扰）
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
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
          // 过渡动画期间不允许核心直接覆盖状态
          if (_transitioning) return;
          state = AsyncData(status);
        },
        onError: (e) {
          debugPrint('watchStatus 错误: $e');
        },
      );
    }
  }

  final Ref _ref;
  StreamSubscription? _statusSub;
  bool _transitioning = false;

  BoxService get _boxService => _ref.read(boxServiceProvider);
  bool get _isStub => _boxService is StubBoxService;

  @override
  void dispose() {
    _statusSub?.cancel();
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
        jsonEncode(getDefaultConfigOptions(
          executeConfigAsIs: isGlobal,
          settings: _ref.read(networkSettingsProvider),
        )),
      );

      // 现场组装 runtime-config.json（注入 / 剥离 rule-set），native 加载这个。
      final workingDir = await getApplicationDocumentsDirectory();
      final runtimeConfig = await RuntimeConfigBuilder().build(
        baseProfile: configFile,
        isSmart: !isGlobal,
        workingDir: workingDir,
      );

      await _boxService.start(runtimeConfig.path, name: active.name);
      // 至少展示 1.5秒 连接中动画
      await Future.delayed(const Duration(milliseconds: 1500));
      state = const AsyncData(BoxStarted());
    } catch (e) {
      final errMsg = e.toString();
      if (errMsg.contains('instance not stopped')) {
        try {
          await _boxService.stop();
          await Future.delayed(const Duration(milliseconds: 500));
          // 重试也用 runtime-config（避免 fallback 到 profile 原文丢失分流配置）
          final modeIndex = _ref.read(proxyModeProvider);
          final workingDir = await getApplicationDocumentsDirectory();
          final runtimeConfig = await RuntimeConfigBuilder().build(
            baseProfile: configFile,
            isSmart: modeIndex != 0,
            workingDir: workingDir,
          );
          await _boxService.start(runtimeConfig.path, name: active.name);
          await Future.delayed(const Duration(milliseconds: 1500));
          state = const AsyncData(BoxStarted());
          return;
        } catch (retryErr) {
          _ref.read(connectionErrorProvider.notifier).state =
              retryErr.toString();
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
        jsonEncode(getDefaultConfigOptions(
          executeConfigAsIs: isGlobal,
          settings: _ref.read(networkSettingsProvider),
        )),
      );
      final workingDir = await getApplicationDocumentsDirectory();
      final runtimeConfig = await RuntimeConfigBuilder().build(
        baseProfile: configFile,
        isSmart: !isGlobal,
        workingDir: workingDir,
      );
      debugPrint('重连: restart ${runtimeConfig.path}');
      await _boxService.restart(runtimeConfig.path, name: active.name);
      debugPrint('restart 完成');
      await Future.delayed(const Duration(seconds: 2));
      if (state.valueOrNull is BoxStarting) {
        state = const AsyncData(BoxStarted());
      }
    } catch (e) {
      debugPrint('重连失败: $e');
      state = const AsyncData(BoxStopped());
    }
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, AsyncValue<BoxStatus>>((ref) {
      return ConnectionController(ref);
    });

/// 最近一次 connect/reconnect 失败的错误信息（人类可读 string）。
///
/// 用 string 而不是 Exception 是为了能从 `valueOrNull == null` 区分"没失败过"
/// 和"刚失败"两种状态。UI 通过 listen 拿到变化弹 toast 之后应该
/// `.state = null` 把它清空。
final connectionErrorProvider = StateProvider<String?>((_) => null);

/// sing-box 实时日志流（从 $appDocs/box.log 每 1.5s tail 一次）。
///
/// 桌面端 sing-box 把日志直接写到 box.log；移动端 fork 也可以走同样路径。
/// 这里用 Stream + Timer 主动 poll 而不是 inotify，跨平台代价最小，
/// 1-2s 延迟对 UI 显示足够。
final boxLogStreamProvider = StreamProvider<List<String>>((ref) async* {
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
