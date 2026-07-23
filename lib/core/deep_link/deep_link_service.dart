import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:clashmiao/core/deep_link/deep_link_parser.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 深链导入结果，供 UI 层（`ShellPage`）用 `ref.listen` 订阅后弹 toast。
///
/// 建模成"一次性事件"：consumer 处理完（弹完 toast）后应把
/// [deepLinkImportResultProvider] 的 state 重置回 `null`，避免同一条结果在
/// 页面重建时被重复消费。见 `shell_page.dart` 的实际消费方写法。
sealed class DeepLinkImportResult {
  const DeepLinkImportResult();
}

/// 导入成功，[profileName] 是最终落地的订阅显示名（供 toast 文案使用）。
final class DeepLinkImportSuccess extends DeepLinkImportResult {
  const DeepLinkImportSuccess(this.profileName);
  final String profileName;

  @override
  String toString() => 'DeepLinkImportSuccess($profileName)';
}

/// 导入失败（缺参数 / 网络失败 / 解析失败等），[message] 是给用户看的原因。
final class DeepLinkImportFailure extends DeepLinkImportResult {
  const DeepLinkImportFailure(this.message);
  final String message;

  @override
  String toString() => 'DeepLinkImportFailure($message)';
}

/// 最近一次深链导入的结果；`null` 表示"没有待展示的结果"。
final deepLinkImportResultProvider = StateProvider<DeepLinkImportResult?>(
  (ref) => null,
);

/// 深链导入的薄封装：监听 AppLinks → [parseDeepLink] 解析 → 调
/// [ProfileRepository] 对应方法导入 → 把结果写进
/// [deepLinkImportResultProvider]。
///
/// 背景：`AndroidManifest.xml` 已经注册好 intent-filter，点击
/// sing-box:// / clash:// / clashmeta:// / clashmiao:// 链接能拉起 App，
/// 但 Dart 侧此前完全没有消费这个 URI 的逻辑——本类是唯一的消费方。
///
/// 只订阅一次 [AppLinks.uriLinkStream]：按 app_links 官方 README 的说明，
/// 这一个 stream 本身就同时覆盖"冷启动时通过链接拉起"和"App 已在运行时
/// 收到新链接"两种场景，不需要（也不应该）再额外调用一次单独的"取初始
/// 链接"方法叠加订阅——app_links 6.x 已经把 `getInitialLink()`
/// 相关的一次性查询方法和 `uriLinkStream` 的职责梳理清楚，同时用两者反而
/// 可能重复处理同一条冷启动链接。
class DeepLinkService {
  DeepLinkService(this._ref, {AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final Ref _ref;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  /// 应用启动早期调用一次；重复调用是安全的 no-op。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _subscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(handleDeepLink(uri, _ref)),
        onError: (Object e) {
          debugPrint('DeepLinkService: 链接流出错，已忽略: $e');
        },
      );
    } catch (e) {
      // 平台没有实现该 channel（例如部分测试/桌面环境没有做原生侧 scheme
      // 注册）时静默忽略——深链是锦上添花的功能，绝不能拖垮 App 启动主流程。
      debugPrint('DeepLinkService: 订阅链接流失败，已忽略: $e');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}

/// 解析 + 分发 + 落地导入结果的核心逻辑，抽成顶层函数方便测试直接驱动：
/// 传入一个 [Uri] 和一个绑定了测试用 [ProviderContainer]（覆盖了
/// `profileRepositoryProvider`）的 [Ref]，就能验证"解析 → 调用
/// addByUrl/addByContent → 写入 deepLinkImportResultProvider"整条链路，
/// 完全不需要经过真实 AppLinks 平台通道。
@visibleForTesting
Future<void> handleDeepLink(Uri uri, Ref ref) async {
  final intent = parseDeepLink(uri);

  switch (intent) {
    case DeepLinkFetchUrl(:final url, :final customName):
      await _importAndReport(
        ref,
        (repo) => repo.addByUrl(url, customName: customName),
      );
    case DeepLinkImportContent(:final content, :final customName):
      await _importAndReport(
        ref,
        (repo) => repo.addByContent(content, name: customName ?? '深链导入'),
      );
    case DeepLinkMissingPayload():
      ref.read(deepLinkImportResultProvider.notifier).state =
          const DeepLinkImportFailure('深链缺少订阅地址参数');
    case DeepLinkUnrecognized():
      // 正常情况下 Android 不会把不认识的 scheme/host 路由到本 App；
      // 防御性兜底，静默忽略即可。
      break;
  }
}

Future<void> _importAndReport(
  Ref ref,
  Future<ProfileEntity> Function(ProfileRepository repo) importCall,
) async {
  final resultNotifier = ref.read(deepLinkImportResultProvider.notifier);
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    final profile = await importCall(repo);
    // 跟 profile_form_dialog.dart `_doAdd` / main.dart `_devAutoBoot`
    // 一致：新增订阅后让依赖 profileRepositoryProvider 的派生 provider 重新
    // 计算，UI 才能看到新订阅。
    ref.invalidate(profileListProvider);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(offlineProxyGroupsProvider);
    resultNotifier.state = DeepLinkImportSuccess(profile.name);
  } catch (e) {
    resultNotifier.state = DeepLinkImportFailure('$e');
  }
}

/// [DeepLinkService] 单例 provider。创建时立即（不 await）开始监听——冷启动
/// 链接的处理和后续 `addByUrl` 网络请求不该阻塞 provider 自身的创建；
/// `main.dart` 只需要 `read` 一次触发创建即可。
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  unawaited(service.start());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
