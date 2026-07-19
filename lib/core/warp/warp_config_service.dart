import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/warp_credential.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WARP 配置生成失败的统一错误类型。
///
/// 只包装"native 没抛异常但结果不可用"的两种情况——返回空值 / 返回的 JSON
/// 格式不对。native 自己抛出的异常（Android 的 `PlatformException`、桌面
/// `StubBoxService` 的 `UnsupportedError` 等）原样透传，不在这里包装，
/// 调用方可以按需要用 `is PlatformException` 之类的类型判断区分。
class WarpConfigException implements Exception {
  const WarpConfigException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

/// WARP 凭证生成的编排层。
///
/// 串联三件事：调 [BoxService.generateWarpConfig] → 解析 native 返回的
/// JSON → 写入 [NetworkSettings] 的 warpAccountId / warpAccessToken /
/// warpWireguardConfig 三个字段。UI 层（config_options_page.dart /
/// profile_form_dialog.dart）只需要调 [generateAndStore]，不用关心
/// native 调用 / 解析 / 持久化的细节。
class WarpConfigService {
  WarpConfigService(this._ref);

  final Ref _ref;

  BoxService get _boxService => _ref.read(boxServiceProvider);
  NetworkSettingsNotifier get _settingsNotifier =>
      _ref.read(networkSettingsProvider.notifier);

  /// 生成一份新的 WARP 凭证并持久化，返回解析后的 [WarpCredential]。
  ///
  /// 自动带上当前已存的 warpAccountId / warpAccessToken 作为
  /// previous-account-id / previous-access-token，让 native 尝试续用
  /// 现有账号而不是每次都重新注册一个。
  ///
  /// 失败时抛出异常：
  ///  - native 侧原生异常（`PlatformException` / `UnsupportedError` 等）
  ///    原样透传；
  ///  - native 成功返回但数据为空或者 JSON 格式不对，包装成
  ///    [WarpConfigException]。
  /// 两种情况下都不会写入任何字段（要么全部三个字段一起更新，要么完全
  /// 不动），调用方用一个 try/catch 处理即可。
  Future<WarpCredential> generateAndStore({required String licenseKey}) async {
    final current = _ref.read(networkSettingsProvider);

    final raw = await _boxService.generateWarpConfig(
      licenseKey: licenseKey,
      previousAccountId: current.warpAccountId,
      previousAccessToken: current.warpAccessToken,
    );

    if (raw == null || raw.trim().isEmpty) {
      throw const WarpConfigException('生成失败：native 未返回数据');
    }

    final WarpCredential credential;
    try {
      credential = WarpCredential.parse(raw);
    } on FormatException catch (e) {
      throw WarpConfigException('生成失败：响应格式无效', cause: e);
    }

    await _settingsNotifier.setWarpAccountId(credential.accountId);
    await _settingsNotifier.setWarpAccessToken(credential.accessToken);
    await _settingsNotifier.setWarpWireguardConfig(credential.wireguardConfig);

    return credential;
  }
}

final warpConfigServiceProvider = Provider<WarpConfigService>((ref) {
  return WarpConfigService(ref);
});
