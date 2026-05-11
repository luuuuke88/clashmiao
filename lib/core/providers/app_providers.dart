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

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  // 忽略自签名证书 + 跳过系统代理直连（避免 sing-box 代理干扰）
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      client.findProxy = (_) => 'DIRECT';
      return client;
    },
  );

  return ProfileRepository(
    dio: dio,
    configDir: Directory(appDir.path),
    prefs: prefs,
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
      // 连接前推送配置，确保系统代理等选项生效
      await _boxService.changeConfigOptions(
        jsonEncode(getDefaultConfigOptions()),
      );
      await _boxService.start(configPath, name: active.name);
      // 至少展示 1.5秒 连接中动画
      await Future.delayed(const Duration(milliseconds: 1500));
      state = const AsyncData(BoxStarted());
    } catch (e) {
      final errMsg = e.toString();
      if (errMsg.contains('instance not stopped')) {
        try {
          await _boxService.stop();
          await Future.delayed(const Duration(milliseconds: 500));
          await _boxService.start(configPath, name: active.name);
          await Future.delayed(const Duration(milliseconds: 1500));
          state = const AsyncData(BoxStarted());
          return;
        } catch (_) {}
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
  Future<void> reconnect() async {
    if (_isStub) return;
    final repoAsync = _ref.read(profileRepositoryProvider);
    if (!repoAsync.hasValue) return;
    final repo = repoAsync.requireValue;
    final active = repo.getActive();
    if (active == null) return;

    final configPath = repo.configFilePath(active.id);
    state = const AsyncData(BoxStarting());
    try {
      debugPrint('重连: restart $configPath');
      await _boxService.restart(configPath, name: active.name);
      debugPrint('restart 完成');
      // 等待状态通过 watchStatus 更新
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
