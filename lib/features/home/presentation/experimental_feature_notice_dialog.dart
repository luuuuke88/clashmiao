import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "不再提示"持久化开关的 SharedPreferences key。
const kExperimentalNoticeDismissedKey =
    'clashmiao_experimental_notice_dismissed';

/// 判断"当前生效配置"是否命中任意一个已知的实验性字段。
///
/// 字段列表覆盖两层配置来源：
/// - [settings]：全局网络设置（TLS fragment / TLS padding / WARP / 局域网访问），
///   来自 [networkSettingsProvider]。
/// - [advancedConfig]：当前激活订阅的 per-profile 高级配置（TLS fragment /
///   多路复用 mux），来自 [ProfileEntity.advancedConfig]。
///
/// 只做已知字段的真值检查，不是通用规则引擎——新增实验性开关时在这里加一行判断即可。
bool hasExperimentalFeatures({
  required NetworkSettings settings,
  AdvancedConfig? advancedConfig,
}) {
  // TUN 不在这里：移动端的 VPN 是正常的服务模式；桌面端没有 TUN 档，残留的
  // `enableTun` 也不会进启动配置（见 service_mode.dart 的 kernelEnableTun）。
  if (settings.enableTlsFragment) return true;
  if (advancedConfig?.fragmentEnabled ?? false) return true;
  if (settings.enableTlsPadding) return true;
  if (advancedConfig?.muxEnabled ?? false) return true;
  if (settings.enableWarp) return true;
  if (settings.bypassLan) return true;
  if (settings.allowConnectionFromLan) return true;

  return false;
}

/// 用户是否已经勾选过"不再提示"。
bool isExperimentalNoticeDismissed(WidgetRef ref) {
  final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
  return prefs?.getBool(kExperimentalNoticeDismissedKey) ?? false;
}

/// 连接前的门禁入口。
///
/// 读取当前生效配置（全局网络设置 + 当前激活订阅的高级配置），如果命中
/// 实验性字段且用户没有勾选"不再提示"，弹确认框等待用户选择；
/// 否则（未命中 / 已勾选不再提示）直接放行，不引入任何多余弹窗或延迟。
///
/// 返回 true 表示可以继续发起连接，false 表示用户取消。
Future<bool> maybeConfirmExperimentalFeatures({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final settings = ref.read(networkSettingsProvider);
  final advancedConfig = ref
      .read(activeProfileProvider)
      .valueOrNull
      ?.advancedConfig;

  if (!hasExperimentalFeatures(
    settings: settings,
    advancedConfig: advancedConfig,
  )) {
    return true;
  }
  if (isExperimentalNoticeDismissed(ref)) {
    return true;
  }
  if (!context.mounted) return false;

  return showExperimentalFeatureNoticeDialog(context);
}

/// 弹出实验性功能确认框，返回用户的选择（true = 仍然连接，false = 取消）。
Future<bool> showExperimentalFeatureNoticeDialog(BuildContext context) async {
  final result = await showAiUiModal<bool>(
    context: context,
    builder: (context) => const ExperimentalFeatureNoticeDialog(),
  );
  return result ?? false;
}

/// 实验性功能确认弹窗：说明当前配置启用了不稳定的高级选项，
/// 附带"不再提示"开关，用户确认后调用方才会真正发起连接。
class ExperimentalFeatureNoticeDialog extends ConsumerStatefulWidget {
  const ExperimentalFeatureNoticeDialog({super.key});

  @override
  ConsumerState<ExperimentalFeatureNoticeDialog> createState() =>
      _ExperimentalFeatureNoticeDialogState();
}

class _ExperimentalFeatureNoticeDialogState
    extends ConsumerState<ExperimentalFeatureNoticeDialog> {
  late bool _dontShowAgain;

  @override
  void initState() {
    super.initState();
    _dontShowAgain = isExperimentalNoticeDismissed(ref);
  }

  Future<void> _setDontShowAgain(bool value) async {
    setState(() => _dontShowAgain = value);
    final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
    await prefs?.setBool(kExperimentalNoticeDismissedKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;
    final t = ref.watch(translationsProvider);

    return AiUiModalWrapper(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.connection.experimentalNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.connection.experimentalNoticeMsg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: aiUi.secondaryTextColor),
            ),
            const SizedBox(height: 12),
            // 用一个紧凑的自定义行而不是 CheckboxListTile：后者内置的 Material
            // 最小点击目标高度（56dp 左右）会让这个弹窗的内容比
            // confirmation_dialogs.dart 的简单确认框明显更高，在窄屏 / 小视口下
            // 把下面的按钮行挤出可视区域。这里只是"复选框 + 文字"，不需要
            // ListTile 的完整功能。
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _setDontShowAgain(!_dontShowAgain),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _dontShowAgain,
                        onChanged: (value) => _setDontShowAgain(value ?? false),
                      ),
                      const SizedBox(width: 4),
                      Text(t.connection.disableExperimentalNotice),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.general.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(t.connection.connectAnyWay),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
