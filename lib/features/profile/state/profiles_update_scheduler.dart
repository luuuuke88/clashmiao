import 'dart:async';

import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:flutter/widgets.dart';

/// 判断某条订阅此刻是否"到期需要自动刷新"。
///
/// 到期条件（三者都要满足）：
/// - 是远程订阅（`url` 是 http(s):// 开头；`content://` 本地导入没有可 fetch
///   的地址，永远不参与自动更新）
/// - 用户没有关闭自动更新（`updateInterval > Duration.zero`；详情页
///   "自动更新间隔" 弹层里的"禁用"选项会把它设成 `Duration.zero`）
/// - 距离上次更新的时间 ≥ `updateInterval`（`lastUpdate` 为 null 视为从未
///   更新过，本身就已经过期）
@visibleForTesting
bool isProfileDue(ProfileEntity profile, DateTime now) {
  final uri = Uri.tryParse(profile.url.trim());
  final isRemote =
      uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (!isRemote) return false;
  if (profile.updateInterval <= Duration.zero) return false;
  final last = profile.lastUpdate;
  if (last == null) return true;
  return now.difference(last) >= profile.updateInterval;
}

/// 订阅自动更新调度器。
///
/// 背景：详情页可以给每条订阅设置 `updateInterval`（"每 N 小时更新"），但
/// 在这个调度器之前没有任何后台任务真正读它——设置了完全没有效果。这个类
/// 只做一件事：定期（[checkInterval] 一次的 `Timer.periodic`，外加每次 App
/// 从后台恢复到前台时）扫一遍所有订阅，把到期的那些用已有的
/// [ProfileRepository.update]（跟详情页"立即更新"按钮同一条刷新逻辑）
/// 静默刷新一次，单条失败不影响其他（跟 [ProfileRepository.updateAll] 同
/// 一个容错策略）。
///
/// 故意不做的事：不引入 WorkManager / BGTaskScheduler 之类的原生后台任务
/// 框架——这只是个"App 在前台运行时顺手刷新"的轻量方案，不承诺 App 被系统
/// 杀死或完全没打开时也能触发。
class ProfileUpdateScheduler with WidgetsBindingObserver {
  ProfileUpdateScheduler({
    required Future<ProfileRepository> Function() repositoryProvider,
    this.checkInterval = const Duration(minutes: 20),
    DateTime Function()? now,
    void Function(List<ProfileEntity> updated)? onChecked,
  }) : _repositoryProvider = repositoryProvider,
       _now = now ?? DateTime.now,
       _onChecked = onChecked;

  final Future<ProfileRepository> Function() _repositoryProvider;

  /// `Timer.periodic` 检查间隔。不是每条订阅各自的 `updateInterval`——那是
  /// 每条订阅自己的刷新周期；这个是调度器"多久扫一遍全部订阅、看看有没有
  /// 谁到期"的轮询粒度，默认 20 分钟，足够覆盖最短 1 小时的 updateInterval
  /// 选项，不需要卡得很准。
  final Duration checkInterval;
  final DateTime Function() _now;
  final void Function(List<ProfileEntity> updated)? _onChecked;

  Timer? _timer;
  bool _checking = false;
  bool _started = false;

  /// 注册 App 生命周期监听 + 起 `Timer.periodic`。重复调用是幂等的。
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      checkInterval,
      (_) => unawaited(checkAndRefreshDue()),
    );
  }

  /// 反注册监听 + 取消 Timer。
  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkAndRefreshDue());
    }
  }

  /// 扫描全部订阅，刷新到期的那些，返回被成功刷新的订阅列表。
  ///
  /// 并发调用会被 [_checking] 闸门去重——避免 Timer 触发时上一次检查还没
  /// 跑完（网络慢）又叠加一次。
  Future<List<ProfileEntity>> checkAndRefreshDue() async {
    if (_checking) return const [];
    _checking = true;
    try {
      final repo = await _repositoryProvider();
      final now = _now();
      final due = repo.getAll().where((p) => isProfileDue(p, now)).toList();
      final refreshed = <ProfileEntity>[];
      for (final profile in due) {
        try {
          refreshed.add(await repo.update(profile.id));
        } catch (_) {
          // 单条刷新失败不影响其它，跟 ProfileRepository.updateAll() 一致：
          // 静默更新失败不该打断其它订阅、也不该弹出用户看不懂的后台错误。
        }
      }
      if (refreshed.isNotEmpty) _onChecked?.call(refreshed);
      return refreshed;
    } finally {
      _checking = false;
    }
  }
}
