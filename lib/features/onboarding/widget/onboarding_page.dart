import 'dart:async';

import 'package:clashmiao/core/config/build_config.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/onboarding/onboarding_state.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/region/region_detection_service.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:clashmiao/shared/components/settings_selection_modal.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final _analyticsPreferenceProvider =
    StateNotifierProvider.autoDispose<_BoolPreferenceNotifier, bool>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return _BoolPreferenceNotifier(
        prefs,
        'clashmiao_analytics_enabled',
        false,
      );
    });

class _BoolPreferenceNotifier extends StateNotifier<bool> {
  _BoolPreferenceNotifier(this._prefs, this._key, bool defaultValue)
    : super(_prefs.getBool(_key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String _key;

  Future<void> update(bool value) async {
    state = value;
    await _prefs.setBool(_key, value);
  }
}

const _regionChoices = ['ir', 'cn', 'ru', 'af', 'id', 'other'];

/// 记录"用户是否手动选过地区"的持久化标记 key（[_State._onRegionManuallySelected]
/// 写，[_State._currentlyShouldAutoDetect] 读，见 `shouldAutoDetectRegion`
/// 的 `manuallySet` 参数文档、`region_detection_service.dart`）——修复"手选
/// other 后被打断、下次重启自动识别把它覆盖回去"的跨会话 bug。故意用独立的
/// key，不复用 `clashmiao_region`：后者的 `'other'` 值本身就是默认哨兵值和
/// 合法手选项的叠加，没法只靠它自己区分"从没碰过"和"手选了 other"。
const _kRegionManuallySet = 'clashmiao_region_manually_set';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _State();
}

class _State extends ConsumerState<OnboardingPage> {
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    // 首帧渲染完之后再触发识别：跟参照实现一致的"首帧自动跑一次"模式，避免
    // 在 build 过程中就发起异步 I/O（时区平台通道 + 可能的 IP 请求）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoDetectRegion());
    });
  }

  /// 只在"初始默认态"触发一次自动识别：region 还没被用户手动改过（仍是
  /// `network_settings.dart` 默认值 `'other'`）、onboarding 还没标记完成、
  /// 且用户从没手动选过 region（[_currentlyShouldAutoDetect] 读独立标记位
  /// `clashmiao_region_manually_set`，见 `shouldAutoDetectRegion` 的
  /// `manuallySet` 参数文档，`region_detection_service.dart`）。三者任一
  /// 不满足都不再自动跑，不覆盖用户已经做出的选择——包括"手选了 other 但
  /// 被打断、下次重启"这种此前会被覆盖的跨会话场景。
  ///
  /// 识别本身（时区 -> IP 兜底）可能耗时到 2 秒左右；`await` 之后到真正写入
  /// region/locale 之前，用同一份守卫条件读最新状态再判一次——这段"读最新
  /// 状态 -> 判断 -> 写入"是同一段同步代码（中间没有再 `await`），不会被其它
  /// 事件（比如用户在识别过程中手动打开地区弹窗选了别的地区）插入执行，
  /// 从而避免识别结果在用户手动选择之后才姗姗来迟、反而覆盖掉用户刚做的
  /// 选择。
  Future<void> _maybeAutoDetectRegion() async {
    if (!_currentlyShouldAutoDetect()) return;

    final countryCode = await ref
        .read(regionDetectionServiceProvider)
        .detectCountryCode();
    if (!mounted) return;
    // 两级兜底都识别不到：保持当前 region/locale 不动（尤其是不要用"默认"
    // 映射的英文强行覆盖 localePreferencesProvider 自己已经做过的设备语言
    // 兜底）。
    if (countryCode == null) return;
    // 二次校验：识别这段时间里用户可能已经手动改过选择。
    if (!_currentlyShouldAutoDetect()) return;

    final mapping = mapCountryCodeToRegionLocale(countryCode);
    await _applyRegion(mapping.region);
    // 同 home_page 里的 updateMode：await 掉，别让"语言没存下来"静默发生。
    await ref
        .read(localePreferencesProvider.notifier)
        .changeLocale(mapping.locale);
  }

  bool _currentlyShouldAutoDetect() {
    final onboardingDone =
        ref.read(onboardingDoneProvider).valueOrNull ?? false;
    final currentRegion = ref.read(networkSettingsProvider).region;
    // valueOrNull ?? false：默认"没手动设置过"，跟 fix 之前的行为保持一致
    // （不会因为 prefs 意外未就绪就反过来拦住正常的首次启动自动识别）。
    final manuallySet =
        ref
            .read(sharedPreferencesProvider)
            .valueOrNull
            ?.getBool(_kRegionManuallySet) ??
        false;
    return shouldAutoDetectRegion(
      currentRegion: currentRegion,
      onboardingDone: onboardingDone,
      manuallySet: manuallySet,
    );
  }

  /// 设置 region + 与之配套的直连 DNS（中国大陆走阿里 DNS，其余走
  /// Cloudflare）。手选弹窗（[_showRegionDialog]）和首帧自动识别
  /// （[_maybeAutoDetectRegion]）共用同一份逻辑，保证不管 region 是怎么被
  /// 设置的，这个配套行为都一致。
  ///
  /// 注意：**不要**在这里写"用户手动选过地区"的标记（[_kRegionManuallySet]）
  /// ——这是手选和自动识别共用的方法，标记写在这里的话，自动识别跑完一次
  /// 也会被打上"手选"标记，`shouldAutoDetectRegion` 的 `manuallySet` 守卫就
  /// 直接失效了。那个标记只在手选专属的 [_onRegionManuallySelected] 里写。
  Future<void> _applyRegion(String region) async {
    final notifier = ref.read(networkSettingsProvider.notifier);
    await notifier.setRegion(region);
    await notifier.setDirectDnsAddress(
      region == 'cn' ? '223.5.5.5' : '1.1.1.1',
    );
  }

  /// 手选弹窗（[_showRegionDialog]）专属：写 region（[_applyRegion]）的同时，
  /// 额外打上"用户手动选过地区"的持久化标记。先写标记、再写 region——即使
  /// 这中间 App 被杀（本任务修复的正是这一类"选完没走完 onboarding 流程就被
  /// 打断"的场景），只要标记已经落盘，下次重启 `shouldAutoDetectRegion` 的
  /// `manuallySet` 守卫就会挡住自动识别，不会有任何窗口被反过来覆盖用户的
  /// 选择。
  Future<void> _onRegionManuallySelected(String region) async {
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .setBool(_kRegionManuallySet, true);
    await _applyRegion(region);
  }

  Future<void> _finish() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await markOnboardingDone(prefs);
    if (!mounted) return;
    ref.invalidate(onboardingDoneProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider);
    final locale = ref.watch(localePreferencesProvider);
    final settings = ref.watch(networkSettingsProvider);
    final analyticsEnabled = ref.watch(_analyticsPreferenceProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          shrinkWrap: true,
          slivers: [
            const SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 224,
                  height: 224,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: BrandMark(size: 176),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 368),
                  child: Column(
                    children: [
                      _IntroTile(
                        icon: FluentIcons.local_language_24_regular,
                        title: t.settings.general.locale,
                        subtitle: _localeName(locale),
                        onTap: () => _showLocaleDialog(context, t),
                      ),
                      const SizedBox(height: 4),
                      _IntroTile(
                        icon: FluentIcons.globe_24_regular,
                        title: t.settings.general.region,
                        subtitle: _regionLabel(t, settings.region),
                        onTap: () => _showRegionDialog(context, t),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.light
                              ? Colors.white
                              : theme.aiUi.glassColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: theme.aiUi.borderColor),
                          boxShadow: theme.aiUi.cardShadow,
                        ),
                        child: AnalyticsToggleTile(
                          label: t.settings.general.enableAnalytics,
                          subtitle: t.settings.general.enableAnalyticsMsg,
                          value: analyticsEnabled,
                          onChanged: (value) => ref
                              .read(_analyticsPreferenceProvider.notifier)
                              .update(value),
                        ),
                      ),
                      // 没配置条款链接时整行不显示。显示一个点了没反应的死链已经
                      // 够糟，而"继续即表示您同意条款"这句话在拿不出条款文档的
                      // 情况下更是不该说——那不是缺个链接，是在声称一份不存在的
                      // 协议已经生效。构建期怎么注入见 core/config/build_config.dart。
                      if (hasTermsAndConditions) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text.rich(
                            t.intro.termsAndPolicyCaution(
                              tap: (text) => TextSpan(
                                text: text,
                                style: const TextStyle(color: Colors.blue),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _openTerms,
                              ),
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _finish,
                            child: _isStarting
                                ? LinearProgressIndicator(
                                    backgroundColor: Colors.transparent,
                                    color: theme.colorScheme.onSurface,
                                  )
                                : Text(t.intro.start),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocaleDialog(BuildContext context, TranslationsEn t) {
    final current = ref.read(localePreferencesProvider);
    showAiUiModal<void>(
      context: context,
      builder: (_) {
        return SettingsSelectionModal<AppLocale>(
          title: t.settings.general.locale,
          items: AppLocale.values,
          selectedItem: current,
          itemIcon: (_) => FluentIcons.local_language_24_regular,
          itemLabel: _localeName,
          onSelected: (item) {
            ref.read(localePreferencesProvider.notifier).changeLocale(item);
          },
        );
      },
    );
  }

  void _showRegionDialog(BuildContext context, TranslationsEn t) {
    final current = ref.read(networkSettingsProvider).region;
    showAiUiModal<void>(
      context: context,
      builder: (_) {
        return SettingsSelectionModal<String>(
          title: t.settings.general.region,
          items: _regionChoices,
          selectedItem: current,
          itemIcon: (_) => FluentIcons.globe_24_regular,
          itemLabel: (item) => _regionLabel(t, item),
          onSelected: (item) => _onRegionManuallySelected(item),
        );
      },
    );
  }

  Future<void> _openTerms() async {
    if (!hasTermsAndConditions) return;
    await launchUrl(
      Uri.parse(termsAndConditionsUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _IntroTile extends StatelessWidget {
  const _IntroTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : aiUi.glassColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: aiUi.borderColor),
            boxShadow: aiUi.cardShadow,
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: aiUi.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_20_regular,
                size: 18,
                color: aiUi.secondaryTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
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

String _localeName(AppLocale locale) {
  if (locale == AppLocale.en) {
    return 'English';
  } else if (locale == AppLocale.zhCn) {
    return '简体中文';
  } else if (locale == AppLocale.fa) {
    return 'فارسی';
  } else if (locale == AppLocale.id) {
    return 'Indonesia';
  } else if (locale == AppLocale.zhTw) {
    return '繁體中文';
  } else if (locale == AppLocale.ru) {
    return 'Русский';
  } else if (locale == AppLocale.ptBr) {
    return 'Português (Brasil)';
  } else if (locale == AppLocale.ar) {
    return 'العربية';
  } else if (locale == AppLocale.es) {
    return 'Español';
  } else if (locale == AppLocale.tr) {
    return 'Türkçe';
  }
  return locale.languageTag;
}
