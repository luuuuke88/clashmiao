import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/warp/warp_config_service.dart';
import 'package:clashmiao/features/assets/widget/assets_page.dart';
import 'package:clashmiao/features/logs/widget/logs_page.dart';
import 'package:clashmiao/features/settings/logic/backup_service.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:clashmiao/shared/components/settings_input_dialog.dart';
import 'package:clashmiao/shared/components/settings_selection_modal.dart';
import 'package:clashmiao/shared/components/tip_card.dart';
import 'package:clashmiao/shared/components/warp_license_agreement_modal.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _ServiceMode { proxy, systemProxy, tun }

const _logLevelChoices = ['trace', 'debug', 'info', 'warn'];
const _regionChoices = ['ir', 'cn', 'ru', 'af', 'id', 'other'];
const _ipv6ModeChoices = [
  'ipv4_only',
  'prefer_ipv4',
  'prefer_ipv6',
  'ipv6_only',
];
const _domainStrategyChoices = [
  '',
  'prefer_ipv6',
  'prefer_ipv4',
  'ipv4_only',
  'ipv6_only',
];
const _tunImplementationChoices = ['mixed', 'system', 'gvisor'];
const _warpDetourModeChoices = ['proxyOverWarp', 'warpOverProxy'];

class ConfigOptionsPage extends ConsumerStatefulWidget {
  const ConfigOptionsPage({
    super.key,
    this.debugOpenActions = false,
    this.debugOpenMixedPortInput = false,
    this.debugOpenUrlTestIntervalSlider = false,
    this.debugOpenWarpConsent = false,
    this.debugInitialScrollOffset = 0,
  });

  final bool debugOpenActions;
  final bool debugOpenMixedPortInput;
  final bool debugOpenUrlTestIntervalSlider;
  final bool debugOpenWarpConsent;
  final int debugInitialScrollOffset;

  @override
  ConsumerState<ConfigOptionsPage> createState() => _ConfigOptionsPageState();
}

class _ConfigOptionsPageState extends ConsumerState<ConfigOptionsPage> {
  late final ScrollController _scrollController = ScrollController();
  bool _debugActionsOpened = false;
  bool _debugInitialScrollApplied = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final settings = ref.watch(networkSettingsProvider);

    if (widget.debugOpenMixedPortInput && !_debugActionsOpened) {
      _debugActionsOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPortEditor(context, ref, t);
      });
    }

    if (widget.debugOpenUrlTestIntervalSlider && !_debugActionsOpened) {
      _debugActionsOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showUrlTestIntervalEditor(context, ref, t);
      });
    }

    if (widget.debugOpenWarpConsent && !_debugActionsOpened) {
      _debugActionsOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<bool>(
          context: context,
          builder: (context) => const WarpLicenseAgreementModal(),
        );
      });
    }

    if (widget.debugOpenActions && !_debugActionsOpened) {
      _debugActionsOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAiUiModal<void>(
          context: context,
          builder: (_) => const _ConfigOptionsActionsModal(),
        );
      });
    }

    if (widget.debugInitialScrollOffset > 0 && !_debugInitialScrollApplied) {
      _debugInitialScrollApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        final offset = widget.debugInitialScrollOffset.clamp(0, max).toDouble();
        _scrollController.jumpTo(offset);
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.config.pageTitle,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  _HeaderControlPill(
                    onMore: () => showAiUiModal<void>(
                      context: context,
                      builder: (_) => const _ConfigOptionsActionsModal(),
                    ),
                    onClose: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      TipCard(message: t.settings.experimentalMsg)
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 16),
                      _ConfigGroup(
                            title: t.config.section.route,
                            icon: FluentIcons.router_24_regular,
                            iconColor: Colors.blue,
                            children: [
                              _ChoiceTile<String>(
                                title: t.config.logLevel,
                                subtitle: settings.logLevel.toUpperCase(),
                                icon: FluentIcons.document_text_24_regular,
                                selected: settings.logLevel,
                                choices: _logLevelChoices,
                                itemLabel: (value) => value.toUpperCase(),
                                itemIcon: (value) => switch (value) {
                                  'trace' =>
                                    FluentIcons.text_bullet_list_24_regular,
                                  'debug' => FluentIcons.bug_24_regular,
                                  'info' => FluentIcons.info_24_regular,
                                  _ => FluentIcons.warning_24_regular,
                                },
                                onSelected: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setLogLevel(value),
                              ),
                              _ChoiceTile<String>(
                                title: t.settings.general.region,
                                subtitle: _regionLabel(t, settings.region),
                                icon: FluentIcons.globe_24_regular,
                                selected: settings.region,
                                choices: _regionChoices,
                                itemLabel: (value) => _regionLabel(t, value),
                                itemIcon: (_) => FluentIcons.globe_24_regular,
                                onSelected: (value) => _setRegion(ref, value),
                              ),
                              _ConfigSwitchTile(
                                title: _experimental(t, t.config.blockAds),
                                value: settings.blockAds,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setBlockAds(value),
                                icon: FluentIcons.shield_dismiss_24_regular,
                              ),
                              _ConfigSwitchTile(
                                title: _experimental(t, t.config.bypassLan),
                                value: settings.bypassLan,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setBypassLan(value),
                                icon: FluentIcons.cloud_off_24_regular,
                              ),
                              _ConfigSwitchTile(
                                title: t.config.resolveDestination,
                                value: settings.resolveDestination,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setResolveDestination(value),
                                icon: FluentIcons.search_24_regular,
                              ),
                              _ChoiceTile<String>(
                                title: t.config.ipv6Mode,
                                subtitle: _ipv6ModeLabel(t, settings.ipv6Mode),
                                icon: FluentIcons.data_usage_24_regular,
                                selected: settings.ipv6Mode,
                                choices: _ipv6ModeChoices,
                                itemLabel: (value) => _ipv6ModeLabel(t, value),
                                itemIcon: (_) =>
                                    FluentIcons.data_usage_24_regular,
                                onSelected: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setIpv6Mode(value),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 100.ms)
                          .slideY(begin: 0.1, end: 0),
                      _ConfigGroup(
                            title: t.config.section.dns,
                            icon: FluentIcons.earth_24_regular,
                            iconColor: Colors.teal,
                            children: [
                              _ValueTile(
                                title: t.config.remoteDnsAddress,
                                subtitle: settings.remoteDnsAddress,
                                icon: FluentIcons.cloud_link_24_regular,
                                onTap: () => _showDnsEditor(context, ref, t),
                              ),
                              _ChoiceTile<String>(
                                title: t.config.remoteDnsDomainStrategy,
                                subtitle: _domainStrategyLabel(
                                  settings.remoteDnsDomainStrategy,
                                ),
                                icon: FluentIcons.branch_24_regular,
                                selected: settings.remoteDnsDomainStrategy,
                                choices: _domainStrategyChoices,
                                itemLabel: _domainStrategyLabel,
                                itemIcon: (_) => FluentIcons.branch_24_regular,
                                onSelected: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setRemoteDnsDomainStrategy(value),
                              ),
                              _ValueTile(
                                title: t.config.directDnsAddress,
                                subtitle: settings.directDnsAddress,
                                icon: FluentIcons.link_24_regular,
                                onTap: () =>
                                    _showDirectDnsEditor(context, ref, t),
                              ),
                              _ChoiceTile<String>(
                                title: t.config.directDnsDomainStrategy,
                                subtitle: _domainStrategyLabel(
                                  settings.directDnsDomainStrategy,
                                ),
                                icon: FluentIcons.branch_24_regular,
                                selected: settings.directDnsDomainStrategy,
                                choices: _domainStrategyChoices,
                                itemLabel: _domainStrategyLabel,
                                itemIcon: (_) => FluentIcons.branch_24_regular,
                                onSelected: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setDirectDnsDomainStrategy(value),
                              ),
                              _ConfigSwitchTile(
                                title: t.config.enableDnsRouting,
                                value: settings.enableDnsRouting,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setEnableDnsRouting(value),
                                icon: FluentIcons.directions_24_regular,
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 200.ms)
                          .slideY(begin: 0.1, end: 0),
                      _ConfigGroup(
                            title: t.config.section.inbound,
                            icon: FluentIcons.box_arrow_left_24_regular,
                            iconColor: Colors.orange,
                            children: [
                              _ChoiceTile<_ServiceMode>(
                                title: t.config.serviceMode,
                                subtitle: _presentServiceMode(t, settings),
                                icon: FluentIcons.settings_24_regular,
                                selected: _serviceModeOf(settings),
                                choices: _serviceModeChoices,
                                itemLabel: (value) =>
                                    _serviceModeLabel(t, value),
                                itemIcon: (value) => switch (value) {
                                  _ServiceMode.proxy =>
                                    FluentIcons.plug_disconnected_24_regular,
                                  _ServiceMode.systemProxy =>
                                    FluentIcons.globe_search_24_regular,
                                  _ServiceMode.tun =>
                                    FluentIcons.arrow_routing_24_regular,
                                },
                                onSelected: (value) =>
                                    _setServiceMode(ref, context, t, value),
                              ),
                              // 桌面端只做到"系统代理级接管"，不遵循系统代理
                              // 的程序会直连、暴露真实 IP。这是当前架构的边界，
                              // 作为 VPN 产品必须让用户知道，不能藏着。
                              if (!Platform.isAndroid && !Platform.isIOS)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: TipCard(
                                    message: t.config.desktopProxyScopeNotice,
                                  ),
                                ),
                              _ConfigSwitchTile(
                                title: t.config.strictRoute,
                                value: settings.strictRoute,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setStrictRoute(value),
                                icon: FluentIcons.prohibited_24_regular,
                              ),
                              _ChoiceTile<String>(
                                title: t.config.tunImplementation,
                                subtitle: settings.tunImplementation,
                                icon: FluentIcons.keyboard_24_regular,
                                selected: settings.tunImplementation,
                                choices: _tunImplementationChoices,
                                itemLabel: (value) => value,
                                itemIcon: (_) =>
                                    FluentIcons.keyboard_24_regular,
                                onSelected: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setTunImplementation(value),
                              ),
                              _ValueTile(
                                title: t.config.mixedPort,
                                subtitle: '${settings.mixedPort}',
                                icon: FluentIcons.connector_24_regular,
                                onTap: () => _showPortEditor(context, ref, t),
                              ),
                              _ConfigSwitchTile(
                                title: _experimental(
                                  t,
                                  t.config.allowConnectionFromLan,
                                ),
                                value: settings.allowConnectionFromLan,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setAllowLan(value),
                                icon: FluentIcons.wifi_1_24_regular,
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 300.ms)
                          .slideY(begin: 0.1, end: 0),
                      _ConfigGroup(
                            title: _experimental(t, t.config.section.tlsTricks),
                            icon: FluentIcons.lock_shield_24_regular,
                            iconColor: Colors.purple,
                            children: [
                              _ConfigSwitchTile(
                                title: t.config.enableTlsFragment,
                                value: settings.enableTlsFragment,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setEnableTlsFragment(value),
                                icon: FluentIcons.puzzle_piece_24_regular,
                              ),
                              _ValueTile(
                                title: t.config.tlsFragmentSize,
                                subtitle: settings.tlsFragmentSize,
                                icon: FluentIcons.resize_24_regular,
                                onTap: () =>
                                    _showTlsFragmentSizeEditor(context, ref, t),
                              ),
                              _ConfigSwitchTile(
                                title: t.config.enableTlsPadding,
                                value: settings.enableTlsPadding,
                                onChanged: (value) => ref
                                    .read(networkSettingsProvider.notifier)
                                    .setEnableTlsPadding(value),
                                icon: FluentIcons.shield_keyhole_24_regular,
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 400.ms)
                          .slideY(begin: 0.1, end: 0),
                      _ConfigGroup(
                            title: _experimental(t, t.config.section.warp),
                            icon: FluentIcons.shield_keyhole_24_regular,
                            iconColor: Colors.indigo,
                            children: const [_WarpOptionsTiles()],
                          )
                          .animate()
                          .fadeIn(delay: 500.ms)
                          .slideY(begin: 0.1, end: 0),
                      _ConfigGroup(
                            title: t.config.section.misc,
                            icon: FluentIcons.app_folder_24_regular,
                            iconColor: Colors.grey,
                            children: [
                              _ValueTile(
                                title: t.config.connectionTestUrl,
                                subtitle: settings.connectionTestUrl,
                                icon: FluentIcons.globe_24_regular,
                                onTap: () => _showConnectionTestUrlEditor(
                                  context,
                                  ref,
                                  t,
                                ),
                              ),
                              _ValueTile(
                                title: t.config.urlTestInterval,
                                subtitle: _formatInterval(
                                  settings.urlTestIntervalSeconds,
                                ),
                                icon: FluentIcons.timer_24_regular,
                                onTap: () =>
                                    _showUrlTestIntervalEditor(context, ref, t),
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(delay: 600.ms)
                          .slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端**没有** TUN 档：仓库里不带 wintun 驱动，macOS 的 entitlements 也只有
/// `network.client/server`，既没有网络扩展权限、也没有特权 helper。选了 TUN
/// 只会让内核起 tun 设备失败——给用户一个必定失败的选项，比不给这个选项糟糕。
///
/// 桌面因此只做到"系统代理级接管"，泄漏面（不遵循系统代理的程序会直连）
/// 由 `t.config.desktopProxyScopeNotice` 明确告知，不藏着。
List<_ServiceMode> get _serviceModeChoices {
  if (Platform.isIOS || Platform.isAndroid) {
    return const [_ServiceMode.proxy, _ServiceMode.tun];
  }
  return const [_ServiceMode.proxy, _ServiceMode.systemProxy];
}

_ServiceMode _serviceModeOf(NetworkSettings settings) {
  if (settings.enableTun) return _ServiceMode.tun;
  if (settings.setSystemProxy) return _ServiceMode.systemProxy;
  return _ServiceMode.proxy;
}

String _presentServiceMode(TranslationsEn t, NetworkSettings settings) {
  return _serviceModeLabel(t, _serviceModeOf(settings));
}

String _serviceModeLabel(TranslationsEn t, _ServiceMode mode) {
  return switch (mode) {
    _ServiceMode.proxy => t.config.serviceModes.proxy,
    _ServiceMode.systemProxy => t.config.serviceModes.systemProxy,
    _ServiceMode.tun => t.config.serviceModes.tun,
  };
}

String _experimental(TranslationsEn t, String text) {
  return '$text (${t.settings.experimental})';
}

String _regionLabel(TranslationsEn t, String region) {
  return switch (region) {
    'ir' => t.settings.general.regions.ir,
    'cn' => t.settings.general.regions.cn,
    'ru' => t.settings.general.regions.ru,
    'af' => t.settings.general.regions.af,
    'id' => t.settings.general.regions.id,
    _ => t.settings.general.regions.other,
  };
}

String _ipv6ModeLabel(TranslationsEn t, String mode) {
  return switch (mode) {
    'prefer_ipv4' => t.config.ipv6Modes.enable,
    'prefer_ipv6' => t.config.ipv6Modes.prefer,
    'ipv6_only' => t.config.ipv6Modes.only,
    _ => t.config.ipv6Modes.disable,
  };
}

String _domainStrategyLabel(String value) {
  return value.isEmpty ? 'auto' : value;
}

Future<void> _setRegion(WidgetRef ref, String value) async {
  final notifier = ref.read(networkSettingsProvider.notifier);
  await notifier.setRegion(value);
  await notifier.setDirectDnsAddress(value == 'cn' ? '223.5.5.5' : '1.1.1.1');
}

Future<void> _setServiceMode(
  WidgetRef ref,
  BuildContext context,
  TranslationsEn t,
  _ServiceMode mode,
) async {
  final notifier = ref.read(networkSettingsProvider.notifier);
  switch (mode) {
    case _ServiceMode.proxy:
      await notifier.setEnableTun(false);
      await notifier.setSystemProxy(false);
    case _ServiceMode.systemProxy:
      await notifier.setEnableTun(false);
      await notifier.setSystemProxy(true);
    case _ServiceMode.tun:
      if (!Platform.isAndroid && !Platform.isIOS) {
        AppToast.info(context, t.settings.adminPrivilegesRequired);
      }
      await notifier.setSystemProxy(false);
      await notifier.setEnableTun(true);
  }
}

void _showPortEditor(BuildContext context, WidgetRef ref, TranslationsEn t) {
  final current = ref.read(networkSettingsProvider).mixedPort;
  final controller = TextEditingController(text: '$current');
  _showInputModal(
    context: context,
    title: t.config.mixedPort,
    controller: controller,
    icon: FluentIcons.connector_24_regular,
    keyboardType: TextInputType.number,
    hintText: '1024-65535',
    onConfirm: () async {
      final raw = controller.text.trim();
      final port = int.tryParse(raw);
      if (port == null || port < 1024 || port > 65535) {
        AppToast.error(context, '端口范围 1024-65535');
        return false;
      }
      await ref.read(networkSettingsProvider.notifier).setMixedPort(port);
      if (context.mounted) AppToast.info(context, t.settings.portChangeNotice);
      return true;
    },
  );
}

void _showDnsEditor(BuildContext context, WidgetRef ref, TranslationsEn t) {
  final current = ref.read(networkSettingsProvider).remoteDnsAddress;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.remoteDnsAddress,
    controller: controller,
    icon: FluentIcons.cloud_link_24_regular,
    hintText: 'https://1.1.1.1/dns-query',
    onConfirm: () async {
      final address = controller.text.trim();
      if (address.isEmpty) {
        AppToast.error(context, 'DNS 地址不能为空');
        return false;
      }
      await ref
          .read(networkSettingsProvider.notifier)
          .setRemoteDnsAddress(address);
      if (context.mounted) AppToast.info(context, t.settings.portChangeNotice);
      return true;
    },
  );
}

void _showDirectDnsEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).directDnsAddress;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.directDnsAddress,
    controller: controller,
    icon: FluentIcons.link_24_regular,
    hintText: '1.1.1.1',
    onConfirm: () async {
      final address = controller.text.trim();
      if (address.isEmpty) {
        AppToast.error(context, 'DNS 地址不能为空');
        return false;
      }
      await ref
          .read(networkSettingsProvider.notifier)
          .setDirectDnsAddress(address);
      return true;
    },
  );
}

void _showTlsFragmentSizeEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).tlsFragmentSize;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.tlsFragmentSize,
    controller: controller,
    icon: FluentIcons.resize_24_regular,
    hintText: '10-30',
    onConfirm: () async {
      final range = controller.text.trim();
      if (!_isOptionalRange(range)) {
        AppToast.error(context, '请输入数字或范围，例如 10-30');
        return false;
      }
      await ref
          .read(networkSettingsProvider.notifier)
          .setTlsFragmentSize(range);
      return true;
    },
  );
}

bool _isOptionalRange(String value) {
  return RegExp(r'^\d+(-\d+)?$').hasMatch(value);
}

void _showConnectionTestUrlEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).connectionTestUrl;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.connectionTestUrl,
    controller: controller,
    icon: FluentIcons.globe_24_regular,
    hintText: 'http://connectivitycheck.gstatic.com/generate_204',
    onConfirm: () async {
      final url = controller.text.trim();
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        AppToast.error(context, 'URL 必须以 http:// 或 https:// 开头');
        return false;
      }
      await ref
          .read(networkSettingsProvider.notifier)
          .setConnectionTestUrl(url);
      return true;
    },
  );
}

void _showUrlTestIntervalEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).urlTestIntervalSeconds;
  SettingsSliderDialog(
    title: t.config.urlTestInterval,
    initialValue: (current / 60).clamp(1, 60).toDouble(),
    min: 1,
    max: 60,
    divisions: 60,
    labelGen: (value) => _formatInterval(value.round() * 60),
  ).show(context).then((value) async {
    if (value == null) return;
    await ref
        .read(networkSettingsProvider.notifier)
        .setUrlTestIntervalSeconds(value.round() * 60);
  });
}

String _formatInterval(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : 1)} h';
}

void _showInputModal({
  required BuildContext context,
  required String title,
  required TextEditingController controller,
  required IconData icon,
  TextInputType? keyboardType,
  String? hintText,
  required Future<bool> Function() onConfirm,
}) {
  SettingsInputDialog<String>(
    title: title,
    initialValue: controller.text,
    icon: icon,
    keyboardType: keyboardType,
    hint: hintText,
    digitsOnly: keyboardType == TextInputType.number,
    onConfirm: (value) async {
      controller.text = value;
      return onConfirm();
    },
  ).show(context).whenComplete(controller.dispose);
}

String _warpDetourModeLabel(TranslationsEn t, String mode) {
  return switch (mode) {
    'warpOverProxy' => t.config.warpDetourModes.warpOverProxy,
    _ => t.config.warpDetourModes.proxyOverWarp,
  };
}

String _notSet(TranslationsEn t, String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? t.general.notSet : trimmed;
}

void _showWarpLicenseKeyEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).warpLicenseKey;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.warpLicenseKey,
    controller: controller,
    icon: FluentIcons.key_24_regular,
    onConfirm: () async {
      await ref
          .read(networkSettingsProvider.notifier)
          .setWarpLicenseKey(controller.text);
      return true;
    },
  );
}

void _showWarpCleanIpEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).warpCleanIp;
  final controller = TextEditingController(text: current);
  _showInputModal(
    context: context,
    title: t.config.warpCleanIp,
    controller: controller,
    icon: FluentIcons.location_24_regular,
    hintText: '162.159.192.1',
    onConfirm: () async {
      await ref
          .read(networkSettingsProvider.notifier)
          .setWarpCleanIp(controller.text);
      return true;
    },
  );
}

void _showWarpPortEditor(
  BuildContext context,
  WidgetRef ref,
  TranslationsEn t,
) {
  final current = ref.read(networkSettingsProvider).warpPort;
  final controller = TextEditingController(text: '$current');
  _showInputModal(
    context: context,
    title: t.config.warpPort,
    controller: controller,
    icon: FluentIcons.connector_24_regular,
    keyboardType: TextInputType.number,
    hintText: '1024-65535',
    onConfirm: () async {
      final port = int.tryParse(controller.text.trim());
      if (port == null || port < 1024 || port > 65535) {
        AppToast.error(context, '端口范围 1024-65535');
        return false;
      }
      await ref.read(networkSettingsProvider.notifier).setWarpPort(port);
      return true;
    },
  );
}

void _showWarpStringEditor({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required String value,
  required IconData icon,
  required Future<void> Function(String value) save,
}) {
  final controller = TextEditingController(text: value);
  _showInputModal(
    context: context,
    title: title,
    controller: controller,
    icon: icon,
    onConfirm: () async {
      await save(controller.text);
      return true;
    },
  );
}

class _WarpOptionsTiles extends ConsumerStatefulWidget {
  const _WarpOptionsTiles();

  @override
  ConsumerState<_WarpOptionsTiles> createState() => _WarpOptionsTilesState();
}

class _WarpOptionsTilesState extends ConsumerState<_WarpOptionsTiles> {
  bool _generating = false;

  Future<void> _generateWarpConfig(NetworkSettings settings) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      await ref
          .read(warpConfigServiceProvider)
          .generateAndStore(licenseKey: settings.warpLicenseKey);
      if (mounted) AppToast.success(context, 'WARP 配置生成成功');
    } catch (e) {
      if (mounted) AppToast.error(context, 'WARP 配置生成失败: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final settings = ref.watch(networkSettingsProvider);
    final notifier = ref.read(networkSettingsProvider.notifier);
    final canChangeOptions = settings.warpConsentGiven && settings.enableWarp;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(FluentIcons.flash_24_regular, size: 20),
          title: Text(
            t.config.enableWarp,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          value: settings.enableWarp,
          onChanged: (value) async {
            if (!settings.warpConsentGiven) {
              final agreed = await showDialog<bool>(
                context: context,
                builder: (context) => const WarpLicenseAgreementModal(),
              );
              if (agreed != true) return;
              await notifier.setWarpConsentGiven(true);
            }
            await notifier.setEnableWarp(value);
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          activeThumbColor: Theme.of(context).colorScheme.primary,
        ),
        ListTile(
          leading: const Icon(FluentIcons.document_save_24_regular, size: 20),
          title: Text(
            t.config.generateWarpConfig,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          enabled: canChangeOptions && !_generating,
          trailing: _generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(FluentIcons.chevron_right_16_regular, size: 16),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: (canChangeOptions && !_generating)
              ? () => _generateWarpConfig(settings)
              : null,
        ),
        _ChoiceTile<String>(
          title: t.config.warpDetourMode,
          subtitle: _warpDetourModeLabel(t, settings.warpDetourMode),
          icon: FluentIcons.arrow_routing_24_regular,
          enabled: canChangeOptions,
          selected: settings.warpDetourMode,
          choices: _warpDetourModeChoices,
          itemLabel: (value) => _warpDetourModeLabel(t, value),
          itemIcon: (_) => FluentIcons.arrow_routing_24_regular,
          onSelected: notifier.setWarpDetourMode,
        ),
        _ValueTile(
          title: t.config.warpLicenseKey,
          subtitle: _notSet(t, settings.warpLicenseKey),
          icon: FluentIcons.key_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpLicenseKeyEditor(context, ref, t),
        ),
        _ValueTile(
          title: t.config.warpCleanIp,
          subtitle: _notSet(t, settings.warpCleanIp),
          icon: FluentIcons.location_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpCleanIpEditor(context, ref, t),
        ),
        _ValueTile(
          title: t.config.warpPort,
          subtitle: '${settings.warpPort}',
          icon: FluentIcons.connector_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpPortEditor(context, ref, t),
        ),
        _ValueTile(
          title: t.config.warpNoise,
          subtitle: _notSet(t, settings.warpNoise),
          icon: FluentIcons.layer_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpStringEditor(
            context: context,
            ref: ref,
            title: t.config.warpNoise,
            value: settings.warpNoise,
            icon: FluentIcons.layer_24_regular,
            save: notifier.setWarpNoise,
          ),
        ),
        _ValueTile(
          title: t.config.warpNoiseMode,
          subtitle: _notSet(t, settings.warpNoiseMode),
          icon: FluentIcons.options_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpStringEditor(
            context: context,
            ref: ref,
            title: t.config.warpNoiseMode,
            value: settings.warpNoiseMode,
            icon: FluentIcons.options_24_regular,
            save: notifier.setWarpNoiseMode,
          ),
        ),
        _ValueTile(
          title: t.config.warpNoiseSize,
          subtitle: _notSet(t, settings.warpNoiseSize),
          icon: FluentIcons.resize_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpStringEditor(
            context: context,
            ref: ref,
            title: t.config.warpNoiseSize,
            value: settings.warpNoiseSize,
            icon: FluentIcons.resize_24_regular,
            save: notifier.setWarpNoiseSize,
          ),
        ),
        _ValueTile(
          title: t.config.warpNoiseDelay,
          subtitle: _notSet(t, settings.warpNoiseDelay),
          icon: FluentIcons.timer_24_regular,
          enabled: canChangeOptions,
          onTap: () => _showWarpStringEditor(
            context: context,
            ref: ref,
            title: t.config.warpNoiseDelay,
            value: settings.warpNoiseDelay,
            icon: FluentIcons.timer_24_regular,
            save: notifier.setWarpNoiseDelay,
          ),
        ),
      ],
    );
  }
}

class _HeaderControlPill extends StatelessWidget {
  const _HeaderControlPill({required this.onMore, required this.onClose});

  final VoidCallback onMore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).aiUi.glassColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).aiUi.borderColor),
        boxShadow: Theme.of(context).aiUi.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: resolveAdaptiveIcon(
              apple: FluentIcons.more_horizontal_24_regular,
              other: FluentIcons.more_vertical_24_regular,
            ),
            onTap: onMore,
          ),
          Container(
            width: 1,
            height: 20,
            color: Theme.of(context).aiUi.borderColor.withValues(alpha: 0.5),
          ),
          _PillButton(
            icon: FluentIcons.dismiss_24_regular,
            onTap: onClose,
            isDestructive: true,
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 52,
        height: 44,
        child: Icon(
          icon,
          size: 20,
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.8)
              : Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
    );
  }
}

class _ConfigGroup extends StatelessWidget {
  const _ConfigGroup({
    required this.title,
    required this.children,
    this.icon,
    this.iconColor,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).aiUi.glassColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).aiUi.borderColor.withValues(alpha: 0.05),
        ),
        boxShadow: Theme.of(context).aiUi.cardShadow,
      ),
      // 这个 Container 自己带背景色，而组内不少 children 是 ListTile /
      // SwitchListTile（例如 _ConfigSwitchTile、WARP 的启用开关 + 生成配置项）
      // ——它们的 ink splash 默认画在最近的 Material 祖先上，中间隔着一个有背景色
      // 的 DecoratedBox 又没有更近的 Material 时，effects 会被这层背景盖住（debug
      // 模式下 Flutter 会断言报错：ListTile background color or ink splashes
      // may be invisible）。这里在 Container 内部包一层透明 Material 提供更近的
      // 挂载点，对所有 children 一次性生效，纯粹修正渲染层级，不改变任何视觉效果
      // （MaterialType.transparency 本身不画任何东西）。
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: iconColor ?? Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace',
                      color: Theme.of(context).aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _BasePreferenceTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.choices,
    required this.itemLabel,
    required this.onSelected,
    this.itemIcon,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final T selected;
  final List<T> choices;
  final String Function(T) itemLabel;
  final ValueChanged<T> onSelected;
  final IconData Function(T)? itemIcon;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _BasePreferenceTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: enabled,
      onTap: () async {
        final selection = await showModalBottomSheet<T>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (context) => SettingsSelectionModal<T>(
            title: title,
            items: choices,
            selectedItem: selected,
            itemLabel: itemLabel,
            itemIcon: itemIcon,
            onSelected: (_) {},
          ),
        );
        if (selection != null) onSelected(selection);
      },
    );
  }
}

class _BasePreferenceTile extends StatelessWidget {
  const _BasePreferenceTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).aiUi.secondaryTextColor,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).aiUi.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: Theme.of(
                  context,
                ).aiUi.secondaryTextColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigSwitchTile extends StatelessWidget {
  const _ConfigSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: icon != null ? Icon(icon, size: 20) : null,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      activeThumbColor: Theme.of(context).colorScheme.primary,
    );
  }
}

class _ConfigOptionsActionsModal extends ConsumerWidget {
  const _ConfigOptionsActionsModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    return AiUiModalWrapper(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    '更多选项',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                _ActionTile(
                  icon: FluentIcons.share_24_regular,
                  label: t.settings.exportOptions,
                  onTap: () async {
                    Navigator.pop(context);
                    await Clipboard.setData(
                      ClipboardData(text: _networkSettingsJson(ref)),
                    );
                    if (context.mounted) {
                      AppToast.success(
                        context,
                        t.general.clipboardExportSuccessMsg,
                      );
                    }
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.share_android_24_regular,
                  label: t.settings.exportAllOptions,
                  onTap: () async {
                    Navigator.pop(context);
                    await Clipboard.setData(
                      ClipboardData(text: _networkSettingsJson(ref)),
                    );
                    if (context.mounted) {
                      AppToast.success(
                        context,
                        t.general.clipboardExportSuccessMsg,
                      );
                    }
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.document_save_24_regular,
                  label: t.settings.importOptions,
                  onTap: () async {
                    // 注意：跟其它 action tile 不同，这里*不*在最前面
                    // Navigator.pop(context) —— 导入需要再弹一个确认对话框，
                    // 如果先 pop 掉"更多选项"这张 bottom sheet，本方法自带的
                    // context 会立刻进入卸载流程，用同一个 context 再弹
                    // showConfirmationDialog 时机就不稳（有时能弹出，有时不能，
                    // 取决于上一次 pop 的动画/卸载时序）。所以先弹确认框，
                    // 拿到结果后再 pop 这张 bottom sheet，全程用同一个仍然
                    // mounted 的 context。
                    final shouldImport = await showConfirmationDialog(
                      context,
                      title: t.settings.importOptions,
                      message: t.settings.importOptionsMsg,
                    );
                    if (context.mounted) Navigator.pop(context);
                    if (!shouldImport) return;
                    if (!context.mounted) return;
                    await _importNetworkSettingsFromClipboard(context, ref);
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.arrow_upload_20_regular,
                  label: '导出备份',
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await BackupService.export(ref);
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.error(context, '导出失败: $e');
                      }
                    }
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.arrow_download_20_regular,
                  label: '导入备份',
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final msg = await BackupService.import(ref);
                      if (msg != null && context.mounted) {
                        AppToast.success(context, msg);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppToast.error(context, '导入失败: $e');
                      }
                    }
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.database_20_regular,
                  label: '规则库管理',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AssetsPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                _ActionTile(
                  icon: FluentIcons.document_text_24_regular,
                  label: t.logs.pageTitle,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const LogsPage()),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: FluentIcons.arrow_reset_24_regular,
                  label: t.config.resetBtn,
                  textColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(networkSettingsProvider.notifier).reset();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "从剪贴板导入选项"：读剪贴板文本，交给
/// [NetworkSettingsNotifier.importJson] 解析 + 逐字段写入，再把结果转成一条
/// toast。解析/校验逻辑都在 notifier 里（可独立单测），这里只管剪贴板 I/O
/// 和 UI 反馈，符合"仅新增导入入口，不重构现有 UI 结构"的范围。
Future<void> _importNetworkSettingsFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.trim().isEmpty) {
    if (context.mounted) AppToast.error(context, '剪贴板为空');
    return;
  }

  final result = await ref
      .read(networkSettingsProvider.notifier)
      .importJson(text);
  if (!context.mounted) return;

  if (result.hasParseError) {
    AppToast.error(context, result.parseError!);
    return;
  }
  if (result.appliedKeys.isEmpty) {
    AppToast.error(context, '未识别到可导入的配置项');
    return;
  }
  final message = result.skippedKeys.isEmpty
      ? '已导入 ${result.appliedKeys.length} 项配置'
      : '已导入 ${result.appliedKeys.length} 项配置，'
            '${result.skippedKeys.length} 项因格式无效被跳过';
  AppToast.success(context, message);
}

String _networkSettingsJson(WidgetRef ref) {
  final settings = ref.read(networkSettingsProvider);
  return const JsonEncoder.withIndent('  ').convert({
    'mixedPort': settings.mixedPort,
    'region': settings.region,
    'blockAds': settings.blockAds,
    'logLevel': settings.logLevel,
    'bypassLan': settings.bypassLan,
    'resolveDestination': settings.resolveDestination,
    'ipv6Mode': settings.ipv6Mode,
    'setSystemProxy': settings.setSystemProxy,
    'enableTun': settings.enableTun,
    'allowConnectionFromLan': settings.allowConnectionFromLan,
    'enableDnsRouting': settings.enableDnsRouting,
    'remoteDnsAddress': settings.remoteDnsAddress,
    'remoteDnsDomainStrategy': settings.remoteDnsDomainStrategy,
    'directDnsAddress': settings.directDnsAddress,
    'directDnsDomainStrategy': settings.directDnsDomainStrategy,
    'tunImplementation': settings.tunImplementation,
    'strictRoute': settings.strictRoute,
    'enableTlsFragment': settings.enableTlsFragment,
    'tlsFragmentSize': settings.tlsFragmentSize,
    'enableTlsPadding': settings.enableTlsPadding,
    'connectionTestUrl': settings.connectionTestUrl,
    'urlTestIntervalSeconds': settings.urlTestIntervalSeconds,
    // wave3：此前只在 default_config_options.dart 里硬编码、现在已经是
    // NetworkSettings 一等字段的高级配置项——导出/导入两侧字段集合保持对称，
    // 否则"导入配置选项 JSON"的入口对这批字段就是摆设。
    'mtu': settings.mtu,
    'clashApiPort': settings.clashApiPort,
    'tproxyPort': settings.tproxyPort,
    'localDnsPort': settings.localDnsPort,
    'enableFakeDns': settings.enableFakeDns,
    'independentDnsCache': settings.independentDnsCache,
    'tlsFragmentSleep': settings.tlsFragmentSleep,
    'enableTlsMixedSniCase': settings.enableTlsMixedSniCase,
    'tlsPaddingSize': settings.tlsPaddingSize,
    'muxPadding': settings.muxPadding,
    // WARP 用户可调设置——故意不含 warpAccountId/warpAccessToken/
    // warpWireguardConfig：这 3 个是 generateWarpConfig 生成写入的运行时凭证
    // （设备/注册绑定的状态，不是用户设置），跟着"配置选项"备份走一是没意义
    // （换设备/重装后大概率失效），二是会把半机密的生成态凭证摊平进剪贴板 JSON。
    'enableWarp': settings.enableWarp,
    'warpConsentGiven': settings.warpConsentGiven,
    'warpDetourMode': settings.warpDetourMode,
    'warpLicenseKey': settings.warpLicenseKey,
    'warpCleanIp': settings.warpCleanIp,
    'warpPort': settings.warpPort,
    'warpNoise': settings.warpNoise,
    'warpNoiseSize': settings.warpNoiseSize,
    'warpNoiseMode': settings.warpNoiseMode,
    'warpNoiseDelay': settings.warpNoiseDelay,
  });
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? theme.colorScheme.primary).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor ?? theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor ?? theme.colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              FluentIcons.chevron_right_24_regular,
              size: 16,
              color: theme.aiUi.secondaryTextColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
