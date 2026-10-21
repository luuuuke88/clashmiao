///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'translations.g.dart';

// Path: <root>
class TranslationsZhCn extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsZhCn({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zhCn,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh-CN>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsZhCn _root = this; // ignore: unused_field

	@override 
	TranslationsZhCn $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsZhCn(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$zh_CN general = Translations$general$zh_CN.internal(_root);
	@override late final Translations$intro$zh_CN intro = Translations$intro$zh_CN.internal(_root);
	@override late final Translations$home$zh_CN home = Translations$home$zh_CN.internal(_root);
	@override late final Translations$stats$zh_CN stats = Translations$stats$zh_CN.internal(_root);
	@override late final Translations$profile$zh_CN profile = Translations$profile$zh_CN.internal(_root);
	@override late final Translations$proxies$zh_CN proxies = Translations$proxies$zh_CN.internal(_root);
	@override late final Translations$logs$zh_CN logs = Translations$logs$zh_CN.internal(_root);
	@override late final Translations$settings$zh_CN settings = Translations$settings$zh_CN.internal(_root);
	@override late final Translations$about$zh_CN about = Translations$about$zh_CN.internal(_root);
	@override late final Translations$appUpdate$zh_CN appUpdate = Translations$appUpdate$zh_CN.internal(_root);
	@override late final Translations$tray$zh_CN tray = Translations$tray$zh_CN.internal(_root);
	@override late final Translations$failure$zh_CN failure = Translations$failure$zh_CN.internal(_root);
	@override late final Translations$connection$zh_CN connection = Translations$connection$zh_CN.internal(_root);
	@override late final Translations$config$zh_CN config = Translations$config$zh_CN.internal(_root);
}

// Path: general
class Translations$general$zh_CN extends Translations$general$en {
	Translations$general$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'Clash喵喵';
	@override String get reset => '重置';
	@override late final Translations$general$toggle$zh_CN toggle = Translations$general$toggle$zh_CN.internal(_root);
	@override late final Translations$general$state$zh_CN state = Translations$general$state$zh_CN.internal(_root);
	@override String get sort => '排序';
	@override String get sortBy => '排序方式';
	@override String get addToClipboard => '添加到剪贴板';
	@override String get notSet => '未设置';
	@override String get agree => '同意';
	@override String get decline => '拒绝';
	@override String get unknown => '未知';
	@override String get hidden => '隐藏';
	@override String get timeout => '超时';
	@override String get clipboardExportSuccessMsg => '已导出到剪贴板';
	@override String get showMore => '显示更多';
	@override String get showLess => '显示更少';
	@override String get openAppSettings => '打开应用设置';
	@override String get grantPermission => '授予权限';
	@override String get underDevelopment => '功能开发中';
	@override String get confirm => '确认';
	@override String get close => '关闭';
	@override String get cancel => '取消';
	@override String get clipboardEmpty => '剪贴板为空';
	@override String get clipboardReadFailed => '读取剪贴板失败';
	@override String get moreOptions => '更多选项';
}

// Path: intro
class Translations$intro$zh_CN extends Translations$intro$en {
	Translations$intro$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: '继续即表示您同意 '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => '开始';
}

// Path: home
class Translations$home$zh_CN extends Translations$home$en {
	Translations$home$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '主页';
	@override String get emptyProfilesMsg => '还没有线路喵';
	@override String get noActiveProfileMsg => '选择配置文件';
	@override late final Translations$home$routingMode$zh_CN routingMode = Translations$home$routingMode$zh_CN.internal(_root);
	@override String failedToSwitchMode({required Object error}) => '切换模式失败: ${error}';
	@override String get connectionFailedTitle => '连接失败';
	@override String get coreMissingTitle => '未找到核心库';
	@override String get coreMissingMsg => '应用没能加载网络核心库，无法建立连接。请重新安装应用，或确认核心库文件与主程序在同一目录下。';
	@override String get degradedTitle => '已连接，但无法访问网络';
	@override String get degradedMsg => '隧道已建立，但数据送不出去。可能是节点已失效——试试换一个节点，或者断开连接。';
	@override String get degradedRetry => '重新检测';
	@override late final Translations$home$egressIp$zh_CN egressIp = Translations$home$egressIp$zh_CN.internal(_root);
	@override String get emptyProfilesHint => '点击下方按钮开始探索';
	@override String get noActiveProfileTitle => '未选择配置文件';
}

// Path: stats
class Translations$stats$zh_CN extends Translations$stats$en {
	Translations$stats$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get traffic => '流量';
	@override String get trafficLive => '实时流量';
	@override String get trafficTotal => '总流量';
	@override String get trafficUsage => '流量使用';
	@override String get liveSpeed => '实时速度';
	@override String get uplink => '上行';
	@override String get downlink => '下行';
	@override String get connection => '连接';
	@override String get speed => '速度';
	@override String get totalTransferred => '总传输量';
	@override String get sessionTraffic => '本次流量';
	@override String get downloadSpeed => '下载速度';
}

// Path: profile
class Translations$profile$zh_CN extends Translations$profile$en {
	Translations$profile$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => '配置文件';
	@override String get detailsPageTitle => '配置文件';
	@override String activeProfileNameSemanticLabel({required Object name}) => '激活的配置文件名称：“${name}”。';
	@override String get activeProfileBtnSemanticLabel => '查看所有配置文件';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => '选择 “${name}” 作为激活的配置文件';
	@override late final Translations$profile$subscription$zh_CN subscription = Translations$profile$subscription$zh_CN.internal(_root);
	@override late final Translations$profile$sortBy$zh_CN sortBy = Translations$profile$sortBy$zh_CN.internal(_root);
	@override late final Translations$profile$actionButtons$zh_CN actionButtons = Translations$profile$actionButtons$zh_CN.internal(_root);
	@override late final Translations$profile$add$zh_CN add = Translations$profile$add$zh_CN.internal(_root);
	@override late final Translations$profile$details$zh_CN details = Translations$profile$details$zh_CN.internal(_root);
	@override late final Translations$profile$share$zh_CN share = Translations$profile$share$zh_CN.internal(_root);
	@override late final Translations$profile$overview$zh_CN overview = Translations$profile$overview$zh_CN.internal(_root);
	@override late final Translations$profile$update$zh_CN update = Translations$profile$update$zh_CN.internal(_root);
	@override late final Translations$profile$edit$zh_CN edit = Translations$profile$edit$zh_CN.internal(_root);
	@override late final Translations$profile$delete$zh_CN delete = Translations$profile$delete$zh_CN.internal(_root);
	@override late final Translations$profile$save$zh_CN save = Translations$profile$save$zh_CN.internal(_root);
	@override late final Translations$profile$detailsForm$zh_CN detailsForm = Translations$profile$detailsForm$zh_CN.internal(_root);
	@override String get remoteProfile => '远程订阅';
	@override String get defaultLocalName => '本地导入';
	@override String get defaultDeepLinkName => '深链导入';
	@override String get switchFailedMsg => '切换配置文件失败';
}

// Path: proxies
class Translations$proxies$zh_CN extends Translations$proxies$en {
	Translations$proxies$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '线路';
	@override String get emptyProxiesMsg => '无可用的线路';
	@override String get delayTestTooltip => '测试延迟';
	@override String get sortTooltip => '对线路进行排序';
	@override String get checkIp => '检测 IP 地址';
	@override String get unknownIp => '未知的 IP';
	@override String get autoSelect => '自动选择';
	@override String get autoSelectDescription => '自动连接到最快的节点';
	@override late final Translations$proxies$sortOptions$zh_CN sortOptions = Translations$proxies$sortOptions$zh_CN.internal(_root);
	@override String get sortModalTitle => '选择排序方式';
	@override String get activeProxySemanticLabel => '激活的线路';
	@override late final Translations$proxies$delaySemantics$zh_CN delaySemantics = Translations$proxies$delaySemantics$zh_CN.internal(_root);
	@override late final Translations$proxies$ipInfoSemantics$zh_CN ipInfoSemantics = Translations$proxies$ipInfoSemantics$zh_CN.internal(_root);
	@override String testingDelayInfo({required Object name}) => '正在测速: ${name}';
	@override String switchedTo({required Object name}) => '已切换到 ${name}';
	@override String get switchFailed => '切换线路失败，请稍后重试';
	@override String get testFailed => '测速失败，请稍后重试';
	@override String get groupsLoading => '线路信息加载中，请稍候再试';
	@override String get connectBeforeSwitch => '请先连接后再切换节点';
	@override String startDelayTestForGroups({required Object count}) => '已开始测试当前订阅的 ${count} 个节点';
	@override String get delayTestBtn => '测速';
	@override String get delayTimeout => '超时';
	@override String get connectBeforeTest => '请连接后测速';
	@override String lineCount({required Object count}) => '${count} 个节点';
	@override String get manualSelect => '手动选择';
	@override String get autoTest => '自动测速';
}

// Path: logs
class Translations$logs$zh_CN extends Translations$logs$en {
	Translations$logs$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '日志';
	@override String get filterHint => '筛选';
	@override String get allLevelsFilter => '全部';
	@override String get shareCoreLogs => '分享核心日志';
	@override String get shareAppLogs => '分享应用日志';
	@override String get pauseTooltip => '暂停';
	@override String get resumeTooltip => '恢复';
	@override String get clearTooltip => '清除';
	@override String get logsCleared => '日志已清空';
	@override String get logsCopied => '日志已复制';
	@override String get logsUnderDevelopment => '日志功能开发中';
	@override String get noLogsWhenDisconnected => '未连接，无日志';
	@override String get loadFailed => '日志读取失败';
	@override String get empty => '暂无日志';
	@override String get clearFailed => '清除日志失败';
}

// Path: settings
class Translations$settings$zh_CN extends Translations$settings$en {
	Translations$settings$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '设置';
	@override String get requiresRestartMsg => '要使其生效，请重新启动应用程序';
	@override String get experimental => '实验性选项';
	@override String get experimentalMsg => '带有实验标志的功能仍在开发中，可能会出现问题。';
	@override String get exportOptions => '将匿名选项导出到剪贴板';
	@override String get exportAllOptions => '将所有选项导出到剪贴板（用于调试）';
	@override String get importOptions => '从剪贴板导入选项';
	@override String get importOptionsMsg => '这将使用提供的值重写所有配置选项。您确定吗？';
	@override late final Translations$settings$backup$zh_CN backup = Translations$settings$backup$zh_CN.internal(_root);
	@override late final Translations$settings$general$zh_CN general = Translations$settings$general$zh_CN.internal(_root);
	@override late final Translations$settings$advanced$zh_CN advanced = Translations$settings$advanced$zh_CN.internal(_root);
	@override late final Translations$settings$network$zh_CN network = Translations$settings$network$zh_CN.internal(_root);
	@override late final Translations$settings$geoAssets$zh_CN geoAssets = Translations$settings$geoAssets$zh_CN.internal(_root);
	@override String get systemProxyEnabled => '已开启系统代理';
	@override String get systemProxyDisabled => '已关闭系统代理（需重连生效）';
	@override String get adminPrivilegesRequired => 'macOS 需要管理员权限';
	@override String get portChangeNotice => '端口修改需要重启连接生效';
	@override late final Translations$settings$groups$zh_CN groups = Translations$settings$groups$zh_CN.internal(_root);
	@override String get importOptionsInvalid => '剪贴板内容不是有效的配置 JSON';
	@override String get importOptionsNothing => '未识别到可导入的配置项';
	@override String importOptionsDone({required Object count}) => '已导入 ${count} 项配置';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '已导入 ${applied} 项配置，${skipped} 项因格式无效被跳过';
}

// Path: about
class Translations$about$zh_CN extends Translations$about$en {
	Translations$about$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '关于';
	@override String get version => '版本';
	@override String get sourceCode => '源代码';
	@override String get telegramChannel => 'Telegram 频道';
	@override String get checkForUpdate => '检查更新';
	@override String get privacyPolicy => '隐私政策';
	@override String get termsAndConditions => '条款和条件';
	@override String get appDescription => '基于 sing-box 核心的跨平台代理客户端';
	@override String get openSourceLicenses => '开源许可';
}

// Path: appUpdate
class Translations$appUpdate$zh_CN extends Translations$appUpdate$en {
	Translations$appUpdate$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => '已是最新版本';
	@override String get dialogTitle => '有可用更新';
	@override String get updateMsg => '${_root.general.appTitle} 的新版本现已推出。您想现在更新吗？';
	@override String get currentVersionLbl => '当前版本';
	@override String get newVersionLbl => '新版本';
	@override String get updateNowBtnTxt => '现在更新';
	@override String get laterBtnTxt => '以后再说';
	@override String get ignoreBtnTxt => '忽略';
	@override String get checkFailedMsg => '检查更新失败，请检查网络后重试';
}

// Path: tray
class Translations$tray$zh_CN extends Translations$tray$en {
	Translations$tray$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get dashboard => '仪表板';
	@override String get quit => '退出';
	@override String get open => '打开';
	@override String get hide => '隐藏到托盘';
	@override late final Translations$tray$status$zh_CN status = Translations$tray$status$zh_CN.internal(_root);
	@override String get proxyModeMenu => '代理模式';
}

// Path: failure
class Translations$failure$zh_CN extends Translations$failure$en {
	Translations$failure$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外错误';
	@override late final Translations$failure$clash$zh_CN clash = Translations$failure$clash$zh_CN.internal(_root);
	@override late final Translations$failure$singbox$zh_CN singbox = Translations$failure$singbox$zh_CN.internal(_root);
	@override late final Translations$failure$connectivity$zh_CN connectivity = Translations$failure$connectivity$zh_CN.internal(_root);
	@override late final Translations$failure$profiles$zh_CN profiles = Translations$failure$profiles$zh_CN.internal(_root);
	@override late final Translations$failure$connection$zh_CN connection = Translations$failure$connection$zh_CN.internal(_root);
	@override late final Translations$failure$geoAssets$zh_CN geoAssets = Translations$failure$geoAssets$zh_CN.internal(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}：${reason}';
}

// Path: connection
class Translations$connection$zh_CN extends Translations$connection$en {
	Translations$connection$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => '点击连接';
	@override String get connecting => '正在连接';
	@override String get disconnecting => '正在断开连接';
	@override String get connected => '已连接';
	@override String get reconnect => '重新连接';
	@override String get connectAnyWay => '仍然连接';
	@override String get experimentalNotice => '实验性功能提醒';
	@override String get experimentalNoticeMsg => '当前配置启用了实验性高级选项（例如 TLS 混淆分片、封包填充、多路复用、WARP 中转，或允许局域网访问等），可能不稳定，连接质量或成功率会受影响。';
	@override String get disableExperimentalNotice => '不再提示';
	@override String get reconnectMsg => '重新连接以使更改生效';
	@override String get staleSystemProxyCleaned => '已清理上次异常退出残留的系统代理设置';
}

// Path: config
class Translations$config$zh_CN extends Translations$config$en {
	Translations$config$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => '重置选项';
	@override String get serviceMode => '服务模式';
	@override String get quickSettings => '快速设置';
	@override String get quickSettingsSubtitle => '自定义您的连接体验';
	@override String get setupWarp => '配置 WARP';
	@override String get allOptions => '全部配置选项';
	@override String get allAdvancedOptions => '所有进阶选项';
	@override late final Translations$config$serviceModes$zh_CN serviceModes = Translations$config$serviceModes$zh_CN.internal(_root);
	@override late final Translations$config$shortServiceModes$zh_CN shortServiceModes = Translations$config$shortServiceModes$zh_CN.internal(_root);
	@override late final Translations$config$section$zh_CN section = Translations$config$section$zh_CN.internal(_root);
	@override late final Translations$config$warpConsent$zh_CN warpConsent = Translations$config$warpConsent$zh_CN.internal(_root);
	@override String get generateWarpConfig => '生成 WARP 配置文件';
	@override String get missingWarpConfig => 'WARP 配置文件缺失';
	@override String get warpConfigGenerated => 'WARP 配置文件已生成';
	@override String get pageTitle => '配置选项';
	@override String get logLevel => '日志级别';
	@override String get blockAds => '阻止广告';
	@override String get resolveDestination => '解析目标地址';
	@override String get ipv6Mode => 'IPv6 路由';
	@override late final Translations$config$ipv6Modes$zh_CN ipv6Modes = Translations$config$ipv6Modes$zh_CN.internal(_root);
	@override String get remoteDnsAddress => '远程 DNS';
	@override String get remoteDnsDomainStrategy => '远程 DNS 域名策略';
	@override String get directDnsAddress => '直连 DNS';
	@override String get directDnsDomainStrategy => '直连 DNS 域名策略';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => '未应用：IPv6 路由已禁用，但「${field}」为仅 IPv6，会导致域名无法解析。请先启用 IPv6 路由，或换一个策略。';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => '未应用：IPv6 路由为仅限 IPv6，但「${field}」为仅 IPv4，会导致域名无法解析。请先调整其中一项。';
	@override String dnsStrategyReset({required Object field}) => '「${field}」与 IPv6 路由设置冲突（会导致域名无法解析），已重置为自动。';
	@override String get mixedPort => '混合端口';
	@override String get tproxyPort => '透明线路端口';
	@override String get localDnsPort => '本地 DNS 端口';
	@override String get allowConnectionFromLan => '允许局域网连接';
	@override String get tunImplementation => 'TUN 实现';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => '连接测试网址';
	@override String get urlTestInterval => '网址测试间隔';
	@override String get enableClashApi => '启用 Clash API';
	@override String get clashApiPort => 'Clash API 端口';
	@override String get enableTun => '启用 TUN';
	@override String get setSystemProxy => '设置系统线路';
	@override String get enableDnsRouting => '启用 DNS 路由';
	@override String get enableFakeDns => '启用 Fake DNS';
	@override String get bypassLan => '绕过局域网';
	@override String get strictRoute => '严格路由';
	@override String get enableTlsFragment => '启用 TLS 数据分段';
	@override String get tlsFragmentSize => 'TLS 分段大小';
	@override String get tlsFragmentSleep => 'TLS 分段休眠';
	@override String get enableTlsMixedSniCase => '启用 TLS 混合 SNI 情形';
	@override String get enableTlsPadding => '启用 TLS 填充';
	@override String get tlsPaddingSize => 'TLS 填充';
	@override String get enableMux => '启用 Mux 多路复用';
	@override String get muxProtocol => 'Mux 协议';
	@override String get muxMaxStreams => 'Mux 最大并发数';
	@override String get enableWarp => '启用 WARP';
	@override String get setUpWarp => '设置 WARP';
	@override String get warpNotConfigured => '未配置';
	@override String get warpDetourMode => '链式线路';
	@override late final Translations$config$warpDetourModes$zh_CN warpDetourModes = Translations$config$warpDetourModes$zh_CN.internal(_root);
	@override String get warpLicenseKey => '许可证密钥';
	@override String get warpCleanIp => '清理 IP';
	@override String get warpPort => '端口';
	@override String get warpNoise => '噪音计数';
	@override String get warpNoiseDelay => '噪音延迟';
	@override String get desktopProxyScopeNotice => '桌面端只有遵循系统代理设置的程序会走隧道。不遵循的软件（部分游戏、命令行工具、自带代理设置的客户端）会直连，暴露你的真实 IP。';
	@override String get warpNoiseSize => '噪音大小';
	@override String get warpNoiseMode => '噪音模式';
	@override String get serviceModeIosVpnOnly => 'iOS 仅支持 VPN 模式';
	@override String get warpGenerating => '正在生成 WARP 配置…';
	@override String get warpConfigFailed => 'WARP 配置生成失败，请稍后重试';
	@override String get portRangeError => '端口范围 1024-65535';
	@override String get dnsEmptyError => 'DNS 地址不能为空';
	@override String get rangeFormatError => '请输入数字或范围，例如 10-30';
	@override String get urlSchemeError => 'URL 必须以 http:// 或 https:// 开头';
	@override String get manageRuleAssets => '规则库管理';
}

// Path: general.toggle
class Translations$general$toggle$zh_CN extends Translations$general$toggle$en {
	Translations$general$toggle$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get enabled => '启用';
	@override String get disabled => '禁用';
}

// Path: general.state
class Translations$general$state$zh_CN extends Translations$general$state$en {
	Translations$general$state$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get disable => '禁用';
}

// Path: home.routingMode
class Translations$home$routingMode$zh_CN extends Translations$home$routingMode$en {
	Translations$home$routingMode$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get global => '全局代理';
	@override String get smart => '智能分流';
}

// Path: home.egressIp
class Translations$home$egressIp$zh_CN extends Translations$home$egressIp$en {
	Translations$home$egressIp$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get label => '出口 IP';
	@override String get notConnected => '连接后显示出口 IP';
	@override String get tapToCheck => '点击检测出口 IP';
	@override String get checking => '正在检测…';
	@override String get failedRetry => '检测失败，点击重试';
}

// Path: profile.subscription
class Translations$profile$subscription$zh_CN extends Translations$profile$subscription$en {
	Translations$profile$subscription$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get traffic => '流量';
	@override String updatedTimeAgo({required Object timeago}) => '更新于 ${timeago}';
	@override String remainingDuration({required Object duration}) => '剩余 ${duration} 天';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '已使用 ${consumed} 流量，共 ${total} 流量。';
	@override String get expired => '已过期';
	@override String get noTraffic => '超出限额';
	@override String get upload => '上传';
	@override String get download => '下载';
	@override String get total => '总流量';
	@override String get expireDate => '到期时间';
}

// Path: profile.sortBy
class Translations$profile$sortBy$zh_CN extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => '最近更新';
	@override String get name => '按字母顺序';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$zh_CN extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get add => '添加';
	@override String get updateAll => '更新全部';
	@override String get sort => '排序';
	@override String get copyConfigSuccess => '配置内容已复制';
	@override String get editConfig => '编辑配置';
}

// Path: profile.add
class Translations$profile$add$zh_CN extends Translations$profile$add$en {
	Translations$profile$add$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '新的配置文件';
	@override String get shortBtnTxt => '新的配置文件';
	@override String get modalSubtitle => '选择添加配置文件的方式';
	@override String get fromClipboard => '从剪贴板添加';
	@override String get scanQr => '扫描二维码';
	@override late final Translations$profile$add$qrScanner$zh_CN qrScanner = Translations$profile$add$qrScanner$zh_CN.internal(_root);
	@override String get manually => '手动输入';
	@override String get manuallyDescription => '手动输入服务器配置信息';
	@override String get addWarp => '添加 WARP';
	@override String get warpDescription => '使用 Cloudflare WARP 免费加速';
	@override String get addingWarpMsg => '我们正在注册 WARP，请稍候。';
	@override String get addingProfileMsg => '添加配置文件';
	@override String get failureMsg => '添加配置文件失败';
	@override String importedNamed({required Object name}) => '已导入订阅：${name}';
	@override String get clipboardEmpty => '剪贴板为空，无法导入订阅';
	@override String get deepLinkMissingUrl => '链接中缺少订阅地址';
	@override String get successMsg => '添加成功';
	@override String get nameAutoHint => '自动识别（可选）';
}

// Path: profile.details
class Translations$profile$details$zh_CN extends Translations$profile$details$en {
	Translations$profile$details$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => '基础信息';
	@override String get subscriptionStatus => '订阅状态';
	@override String get options => '选项';
	@override String get updateNow => '立即更新';
	@override String get updateNowDescription => '从服务器获取最新配置';
	@override String get expireDate => '到期时间';
	@override String get unlimited => '无限期';
}

// Path: profile.share
class Translations$profile$share$zh_CN extends Translations$profile$share$en {
	Translations$profile$share$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '分享';
	@override String get shareLink => '分享链接';
	@override String get subscriptionLinkCopied => '订阅链接已复制';
	@override String get configCopied => '配置内容已复制';
	@override String get copyFailed => '复制失败';
	@override String get exportToClipboardSuccess => '导出到剪贴板';
	@override String get exportSubLinkToClipboard => '将订阅链接导出到剪贴板';
	@override String get subLinkQrCode => '订阅链接二维码';
	@override String get exportConfigToClipboard => '将配置导出到剪贴板';
	@override String get exportConfigToClipboardSuccess => '配置已复制到剪贴板';
}

// Path: profile.overview
class Translations$profile$overview$zh_CN extends Translations$profile$overview$en {
	Translations$profile$overview$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => '当前使用';
	@override String remainingDays({required Object days}) => '剩余 ${days} 天';
}

// Path: profile.update
class Translations$profile$update$zh_CN extends Translations$profile$update$en {
	Translations$profile$update$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '更新';
	@override String get tooltip => '更新配置文件';
	@override String get updateSubscriptions => '更新订阅';
	@override String get failureMsg => '更新配置文件失败';
	@override String get successMsg => '配置文件更新成功';
	@override String namedFailureMsg({required Object name}) => '无法更新"${name}"';
	@override String namedSuccessMsg({required Object name}) => '"${name}" 更新成功';
}

// Path: profile.edit
class Translations$profile$edit$zh_CN extends Translations$profile$edit$en {
	Translations$profile$edit$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '编辑';
	@override String get selectActiveTxt => '选择并激活配置文件';
}

// Path: profile.delete
class Translations$profile$delete$zh_CN extends Translations$profile$delete$en {
	Translations$profile$delete$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '删除';
	@override String get confirmationMsg => '要永久删除配置文件吗？';
	@override String get successMsg => '配置文件删除成功';
	@override String get confirmTitle => '删除配置文件';
	@override String namedConfirmMsg({required Object name}) => '确定要删除"${name}"吗？此操作不可撤销。';
}

// Path: profile.save
class Translations$profile$save$zh_CN extends Translations$profile$save$en {
	Translations$profile$save$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '保存';
	@override String get successMsg => '配置文件保存成功';
	@override String get failureMsg => '配置文件保存失败';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$zh_CN extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => '名称';
	@override String get nameHint => '配置文件名称';
	@override String get urlLabel => '网址';
	@override String get urlHint => '完整配置网址';
	@override String get emptyNameMsg => '名称为必填项';
	@override String get invalidUrlMsg => '无效的网址';
	@override String get lastUpdate => '最后更新';
	@override String get updateInterval => '自动更新';
	@override String get updateIntervalDialogTitle => '自动更新间隔（小时）';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => '未设置';
	@override String get mux => 'Mux 多路复用';
	@override String get muxDescription => '复用出站连接以减少握手开销';
	@override String get updateIntervalOff => '关闭';
	@override String updateIntervalHours({required Object hours}) => '${hours} 小时';
	@override String updateIntervalDays({required Object days}) => '${days} 天';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$zh_CN extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unsorted => '默认';
	@override String get name => '按字母顺序';
	@override String get delay => '按延迟顺序';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$zh_CN extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => '延迟: ${delay}ms';
	@override String get timeout => '延迟测试超时';
	@override String get testing => '正在测试延迟';
	@override String get untested => '延迟: 未测试';
	@override String stale({required Object delay}) => '延迟: ${delay}ms（历史值）';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$zh_CN extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get address => 'IP 地址';
	@override String get country => '国家';
}

// Path: settings.backup
class Translations$settings$backup$zh_CN extends Translations$settings$backup$en {
	Translations$settings$backup$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => '导入备份';
	@override String get importConfirmMsg => '这会用备份中的订阅替换当前订阅，并应用备份中的设置。导入前会先保存当前数据的快照，导入失败时自动恢复。';
	@override String importRemovesMsg({required Object count}) => '本机有 ${count} 个订阅不在备份中，导入后将被移除。';
	@override String reportImported({required Object profiles, required Object settings}) => '已导入 ${profiles} 个订阅、${settings} 项设置。';
	@override String reportDropped({required Object count}) => '备份中有 ${count} 个订阅因数据无效被跳过。';
	@override String reportSettingsSkipped({required Object count}) => '有 ${count} 项设置被跳过，保留了当前值。';
	@override String get reportWarpOff => '导入时已关闭 WARP，请在本机重新启用。';
	@override String reportBackfill({required Object count}) => '有 ${count} 个订阅将在后台下载。';
	@override String get errInvalidFile => '这不是有效的 ClashMiao 备份文件。';
	@override String get errUnsupportedVersion => '不支持这种备份格式。';
	@override String get errNewerSchema => '此备份由更新版本的应用生成，请先升级应用。';
	@override String get errNoUsableProfiles => '此备份中没有可以导入的订阅。';
	@override String get errSnapshotFailed => '无法保存当前数据的快照，所以没有做任何改动。';
	@override String get errUnresolvedPrevious => '上一次导入被中断，尚未能撤销。没有做任何改动，请重启应用后再试。';
	@override String get errRolledBack => '导入失败，已恢复到导入之前的数据。';
	@override String errNotRolledBack({required Object path}) => '导入失败，且自动恢复没有完成。请重启应用让它重试。快照保存在 ${path}。';
	@override String get errFailed => '导入失败。';
	@override String get errBusy => '已有另一个导入正在进行，请等它结束后再试。';
	@override String get recoveryFailedTitle => '自动恢复没有完成';
	@override String get recoveryFailedMsg => '上一次备份导入被中断，应用没能把数据恢复到导入之前的状态，部分数据可能只导入了一半。现在重试自动恢复。';
	@override String get recoveryUnrecoverableTitle => '无法撤销被中断的导入';
	@override String get recoveryUnrecoverableMsg => '上一次备份导入被中断，但它的快照丢失或无法读取，因此无法撤销。请检查你的订阅和设置。';
	@override String get recoveryRetry => '重试';
	@override String get recoveryClose => '关闭';
	@override String get recoveryRetried => '已把数据恢复到被中断的导入之前。';
	@override String get exportAction => '导出备份';
	@override String get importAction => '导入备份';
	@override String get exportFailed => '导出失败';
	@override String get shareText => 'ClashMiao 备份';
}

// Path: settings.general
class Translations$settings$general$zh_CN extends Translations$settings$general$en {
	Translations$settings$general$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '一般选项';
	@override String get locale => '语言';
	@override String get region => '地区';
	@override String get regionMsg => '帮助设置默认选项以绕过国内地址';
	@override late final Translations$settings$general$regions$zh_CN regions = Translations$settings$general$regions$zh_CN.internal(_root);
	@override String get themeMode => '主题模式';
	@override late final Translations$settings$general$themeModes$zh_CN themeModes = Translations$settings$general$themeModes$zh_CN.internal(_root);
	@override String get enableAnalytics => '启用分析';
	@override String get enableAnalyticsMsg => '授予收集分析并发送崩溃报告以改进应用程序的权限';
	@override String get autoStart => '开机启动';
	@override String get silentStart => '静默启动';
	@override String get openWorkingDir => '打开工作目录';
	@override String get ignoreBatteryOptimizations => '禁用电池优化';
	@override String get ignoreBatteryOptimizationsMsg => '消除限制以获得最佳 VPN 性能';
	@override String get dynamicNotification => '在通知中显示网络速度';
	@override String get hapticFeedback => '触觉反馈';
	@override String get autoIpCheck => '自动检查连接的 IP';
	@override String get autoStartPermission => '允许自启动';
	@override String get autoStartPermissionMsg => '开启后，手机重启或 App 更新后能自动恢复连接';
	@override late final Translations$settings$general$autoStartPermissionStatus$zh_CN autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$zh_CN.internal(_root);
	@override late final Translations$settings$general$batteryOptimizationStatus$zh_CN batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$zh_CN.internal(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$zh_CN extends Translations$settings$advanced$en {
	Translations$settings$advanced$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '高级选项';
	@override String get debugMode => '调试模式';
	@override String get debugModeMsg => '重新启动应用程序以应用此更改';
	@override String get memoryLimit => '内存限制';
	@override String get memoryLimitMsg => '如果您遇到内存不足错误或频繁应用程序崩溃，请启用';
	@override String get resetTunnel => '重置 VPN 配置文件';
	@override String get resetTunnelSuccess => 'VPN 配置文件已重置';
}

// Path: settings.network
class Translations$settings$network$zh_CN extends Translations$settings$network$en {
	Translations$settings$network$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => '分应用线路';
	@override late final Translations$settings$network$perAppProxyModes$zh_CN perAppProxyModes = Translations$settings$network$perAppProxyModes$zh_CN.internal(_root);
	@override String get perAppProxyLoadFailedMsg => '加载应用列表失败';
	@override String get perAppProxyRetry => '重试';
	@override String get perAppProxyEmptyMsg => '未找到匹配的应用';
	@override String get perAppProxyAndroidOnlyMsg => '仅 Android 支持分应用线路';
	@override String get showSystemApps => '显示系统应用程序';
	@override String get hideSystemApps => '隐藏系统应用程序';
	@override String get clearSelection => '清空选项';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$zh_CN extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '路由资源文件';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => '版本 ${version}';
	@override String get fileMissing => '文件丢失';
	@override String get update => '更新';
	@override String get download => '下载';
	@override String get failureMsg => '更新资源文件失败';
	@override String get successMsg => '已成功更新资源文件';
	@override String get addRecommended => '添加建议的资源文件';
	@override String get missingGeoAssetsMsg => '所选路由资源的文件丢失。下载它们或选择现有的。';
}

// Path: settings.groups
class Translations$settings$groups$zh_CN extends Translations$settings$groups$en {
	Translations$settings$groups$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get general => '通用';
	@override String get connection => '连接';
	@override String get privacy => '隐私';
}

// Path: tray.status
class Translations$tray$status$zh_CN extends Translations$tray$status$en {
	Translations$tray$status$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get connect => '连接';
	@override String get connecting => '正在连接';
	@override String get disconnect => '断开连接';
	@override String get disconnecting => '正在断开连接';
}

// Path: failure.clash
class Translations$failure$clash$zh_CN extends Translations$failure$clash$en {
	Translations$failure$clash$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外错误';
	@override String core({required Object reason}) => 'Clash 错误 ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$zh_CN extends Translations$failure$singbox$en {
	Translations$failure$singbox$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外服务错误';
	@override String get serviceNotRunning => '服务未运行';
	@override String get coreLibraryMissing => '核心库未安装';
	@override String get missingPrivilege => '缺少权限';
	@override String get missingPrivilegeMsg => 'VPN 模式需要管理员权限。以管理员身份重新启动应用程序或更改服务模式';
	@override String get missingGeoAssets => '缺失 GEO 资源文件';
	@override String get missingGeoAssetsMsg => '缺失 GEO 资源文件。请考虑更改激活的资源文件或在设置中下载所选资源文件。';
	@override String get invalidConfigOptions => '配置选项无效';
	@override String get invalidConfig => '无效配置';
	@override String get create => '服务创建错误';
	@override String get start => '服务启动错误';
	@override String get startTimeout => '服务启动超时';
	@override String get kernelUnresponsive => '内核无响应，请重试或重启应用';
	@override String get kernelExited => '内核意外退出';
}

// Path: failure.connectivity
class Translations$failure$connectivity$zh_CN extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外失败';
	@override String get missingVpnPermission => '缺少 VPN 权限';
	@override String get missingNotificationPermission => '缺少通知权限';
	@override String get networkUnavailable => '网络不可用';
	@override String get core => '核心错误';
	@override String get nativeUnresponsive => '与后台服务失去联系，请重试';
}

// Path: failure.profiles
class Translations$failure$profiles$zh_CN extends Translations$failure$profiles$en {
	Translations$failure$profiles$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外错误';
	@override String get notFound => '未找到配置文件';
	@override String get noActive => '没有激活的订阅';
	@override String get invalidConfig => '无效配置';
	@override String get invalidUrl => '网址无效';
	@override String get readOnlyUpgrade => '请升级 App 后再修改订阅';
}

// Path: failure.connection
class Translations$failure$connection$zh_CN extends Translations$failure$connection$en {
	Translations$failure$connection$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外连接错误';
	@override String get timeout => '连接超时';
	@override String get badResponse => '错误响应';
	@override String get connectionError => '连接错误';
	@override String get badCertificate => '证书无效';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$zh_CN extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外错误';
	@override String get notUpdate => '无可用更新';
	@override String get activeNotFound => '未找到激活的 GEO 资源文件';
}

// Path: config.serviceModes
class Translations$config$serviceModes$zh_CN extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get proxy => '仅线路';
	@override String get systemProxy => '系统线路';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN 服务';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$zh_CN extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get proxy => '仅线路';
	@override String get systemProxy => '系统线路';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN 服务';
}

// Path: config.section
class Translations$config$section$zh_CN extends Translations$config$section$en {
	Translations$config$section$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get route => '路由选项';
	@override String get dns => 'DNS 选项';
	@override String get inbound => '入站选项';
	@override String get mux => '多路复用';
	@override String get outbound => '出站选项';
	@override String get tlsTricks => 'TLS 特性';
	@override String get warp => 'WARP 选项';
	@override String get misc => '其它选项';
}

// Path: config.warpConsent
class Translations$config$warpConsent$zh_CN extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cloudflare WARP 许可条款';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP 是一个免费的 WireGuard VPN 提供商。启用此选项即表示您同意 Cloudflare WARP 的 '),
		tos('服務條款'),
		const TextSpan(text: ' 和 '),
		privacy('隱私權政策'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$zh_CN extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get disable => '禁用';
	@override String get enable => '启用';
	@override String get prefer => '首选';
	@override String get only => '仅限';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$zh_CN extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get proxyOverWarp => '通过 WARP 连接线路';
	@override String get warpOverProxy => '通过线路连接 WARP';
	@override String get inbound => '通过线路绕过 WARP';
	@override String get outbound => '通过 WARP 绕过线路';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$zh_CN extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => '权限不足';
	@override String get unexpectedError => '出了些问题';
	@override String get torchSemanticLabel => '闪光灯';
	@override String get facingSemanticLabel => '切换摄像头';
	@override String get permissionRequest => '授予相机权限以允许扫描二维码';
}

// Path: settings.general.regions
class Translations$settings$general$regions$zh_CN extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get ir => '伊朗 (ir)';
	@override String get cn => '中国 (cn)';
	@override String get ru => '俄罗斯 (ru)';
	@override String get af => '阿富汗 (af)';
	@override String get id => '印度尼西亚 (id)';
	@override String get other => '其它';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$zh_CN extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get system => '跟随系统颜色';
	@override String get dark => '暗色';
	@override String get light => '浅色';
	@override String get black => '黑色';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$zh_CN extends Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get allowed => '已开启';
	@override String get denied => '未开启';
	@override String get unknown => '未知';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$zh_CN extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get exempted => '已豁免';
	@override String get notExempted => '未豁免';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$zh_CN extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$zh_CN.internal(TranslationsZhCn root) : this._root = root, super.internal(root);

	final TranslationsZhCn _root; // ignore: unused_field

	// Translations
	@override String get off => '全部';
	@override String get offMsg => '代理所有应用程序';
	@override String get include => '代理';
	@override String get includeMsg => '仅代理选定的应用程序';
	@override String get exclude => '绕过';
	@override String get excludeMsg => '不代理选中的应用程序';
}

/// The flat map containing all translations for locale <zh-CN>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsZhCn {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'Clash喵喵',
			'general.reset' => '重置',
			'general.toggle.enabled' => '启用',
			'general.toggle.disabled' => '禁用',
			'general.state.disable' => '禁用',
			'general.sort' => '排序',
			'general.sortBy' => '排序方式',
			'general.addToClipboard' => '添加到剪贴板',
			'general.notSet' => '未设置',
			'general.agree' => '同意',
			'general.decline' => '拒绝',
			'general.unknown' => '未知',
			'general.hidden' => '隐藏',
			'general.timeout' => '超时',
			'general.clipboardExportSuccessMsg' => '已导出到剪贴板',
			'general.showMore' => '显示更多',
			'general.showLess' => '显示更少',
			'general.openAppSettings' => '打开应用设置',
			'general.grantPermission' => '授予权限',
			'general.underDevelopment' => '功能开发中',
			'general.confirm' => '确认',
			'general.close' => '关闭',
			'general.cancel' => '取消',
			'general.clipboardEmpty' => '剪贴板为空',
			'general.clipboardReadFailed' => '读取剪贴板失败',
			'general.moreOptions' => '更多选项',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: '继续即表示您同意 '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => '开始',
			'home.pageTitle' => '主页',
			'home.emptyProfilesMsg' => '还没有线路喵',
			'home.noActiveProfileMsg' => '选择配置文件',
			'home.routingMode.global' => '全局代理',
			'home.routingMode.smart' => '智能分流',
			'home.failedToSwitchMode' => ({required Object error}) => '切换模式失败: ${error}',
			'home.connectionFailedTitle' => '连接失败',
			'home.coreMissingTitle' => '未找到核心库',
			'home.coreMissingMsg' => '应用没能加载网络核心库，无法建立连接。请重新安装应用，或确认核心库文件与主程序在同一目录下。',
			'home.degradedTitle' => '已连接，但无法访问网络',
			'home.degradedMsg' => '隧道已建立，但数据送不出去。可能是节点已失效——试试换一个节点，或者断开连接。',
			'home.degradedRetry' => '重新检测',
			'home.egressIp.label' => '出口 IP',
			'home.egressIp.notConnected' => '连接后显示出口 IP',
			'home.egressIp.tapToCheck' => '点击检测出口 IP',
			'home.egressIp.checking' => '正在检测…',
			'home.egressIp.failedRetry' => '检测失败，点击重试',
			'home.emptyProfilesHint' => '点击下方按钮开始探索',
			'home.noActiveProfileTitle' => '未选择配置文件',
			'stats.traffic' => '流量',
			'stats.trafficLive' => '实时流量',
			'stats.trafficTotal' => '总流量',
			'stats.trafficUsage' => '流量使用',
			'stats.liveSpeed' => '实时速度',
			'stats.uplink' => '上行',
			'stats.downlink' => '下行',
			'stats.connection' => '连接',
			'stats.speed' => '速度',
			'stats.totalTransferred' => '总传输量',
			'stats.sessionTraffic' => '本次流量',
			'stats.downloadSpeed' => '下载速度',
			'profile.overviewPageTitle' => '配置文件',
			'profile.detailsPageTitle' => '配置文件',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => '激活的配置文件名称：“${name}”。',
			'profile.activeProfileBtnSemanticLabel' => '查看所有配置文件',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => '选择 “${name}” 作为激活的配置文件',
			'profile.subscription.traffic' => '流量',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => '更新于 ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '剩余 ${duration} 天',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '已使用 ${consumed} 流量，共 ${total} 流量。',
			'profile.subscription.expired' => '已过期',
			'profile.subscription.noTraffic' => '超出限额',
			'profile.subscription.upload' => '上传',
			'profile.subscription.download' => '下载',
			'profile.subscription.total' => '总流量',
			'profile.subscription.expireDate' => '到期时间',
			'profile.sortBy.lastUpdate' => '最近更新',
			'profile.sortBy.name' => '按字母顺序',
			'profile.actionButtons.add' => '添加',
			'profile.actionButtons.updateAll' => '更新全部',
			'profile.actionButtons.sort' => '排序',
			'profile.actionButtons.copyConfigSuccess' => '配置内容已复制',
			'profile.actionButtons.editConfig' => '编辑配置',
			'profile.add.buttonText' => '新的配置文件',
			'profile.add.shortBtnTxt' => '新的配置文件',
			'profile.add.modalSubtitle' => '选择添加配置文件的方式',
			'profile.add.fromClipboard' => '从剪贴板添加',
			'profile.add.scanQr' => '扫描二维码',
			'profile.add.qrScanner.permissionDeniedError' => '权限不足',
			'profile.add.qrScanner.unexpectedError' => '出了些问题',
			'profile.add.qrScanner.torchSemanticLabel' => '闪光灯',
			'profile.add.qrScanner.facingSemanticLabel' => '切换摄像头',
			'profile.add.qrScanner.permissionRequest' => '授予相机权限以允许扫描二维码',
			'profile.add.manually' => '手动输入',
			'profile.add.manuallyDescription' => '手动输入服务器配置信息',
			'profile.add.addWarp' => '添加 WARP',
			'profile.add.warpDescription' => '使用 Cloudflare WARP 免费加速',
			'profile.add.addingWarpMsg' => '我们正在注册 WARP，请稍候。',
			'profile.add.addingProfileMsg' => '添加配置文件',
			'profile.add.failureMsg' => '添加配置文件失败',
			'profile.add.importedNamed' => ({required Object name}) => '已导入订阅：${name}',
			'profile.add.clipboardEmpty' => '剪贴板为空，无法导入订阅',
			'profile.add.deepLinkMissingUrl' => '链接中缺少订阅地址',
			'profile.add.successMsg' => '添加成功',
			'profile.add.nameAutoHint' => '自动识别（可选）',
			'profile.details.basicInfo' => '基础信息',
			'profile.details.subscriptionStatus' => '订阅状态',
			'profile.details.options' => '选项',
			'profile.details.updateNow' => '立即更新',
			'profile.details.updateNowDescription' => '从服务器获取最新配置',
			'profile.details.expireDate' => '到期时间',
			'profile.details.unlimited' => '无限期',
			'profile.share.buttonText' => '分享',
			'profile.share.shareLink' => '分享链接',
			'profile.share.subscriptionLinkCopied' => '订阅链接已复制',
			'profile.share.configCopied' => '配置内容已复制',
			'profile.share.copyFailed' => '复制失败',
			'profile.share.exportToClipboardSuccess' => '导出到剪贴板',
			'profile.share.exportSubLinkToClipboard' => '将订阅链接导出到剪贴板',
			'profile.share.subLinkQrCode' => '订阅链接二维码',
			'profile.share.exportConfigToClipboard' => '将配置导出到剪贴板',
			'profile.share.exportConfigToClipboardSuccess' => '配置已复制到剪贴板',
			'profile.overview.currentlyUsing' => '当前使用',
			'profile.overview.remainingDays' => ({required Object days}) => '剩余 ${days} 天',
			'profile.update.buttonTxt' => '更新',
			'profile.update.tooltip' => '更新配置文件',
			'profile.update.updateSubscriptions' => '更新订阅',
			'profile.update.failureMsg' => '更新配置文件失败',
			'profile.update.successMsg' => '配置文件更新成功',
			'profile.update.namedFailureMsg' => ({required Object name}) => '无法更新"${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" 更新成功',
			'profile.edit.buttonTxt' => '编辑',
			'profile.edit.selectActiveTxt' => '选择并激活配置文件',
			'profile.delete.buttonTxt' => '删除',
			'profile.delete.confirmationMsg' => '要永久删除配置文件吗？',
			'profile.delete.successMsg' => '配置文件删除成功',
			'profile.delete.confirmTitle' => '删除配置文件',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => '确定要删除"${name}"吗？此操作不可撤销。',
			'profile.save.buttonText' => '保存',
			'profile.save.successMsg' => '配置文件保存成功',
			'profile.save.failureMsg' => '配置文件保存失败',
			'profile.detailsForm.nameLabel' => '名称',
			'profile.detailsForm.nameHint' => '配置文件名称',
			'profile.detailsForm.urlLabel' => '网址',
			'profile.detailsForm.urlHint' => '完整配置网址',
			'profile.detailsForm.emptyNameMsg' => '名称为必填项',
			'profile.detailsForm.invalidUrlMsg' => '无效的网址',
			'profile.detailsForm.lastUpdate' => '最后更新',
			'profile.detailsForm.updateInterval' => '自动更新',
			'profile.detailsForm.updateIntervalDialogTitle' => '自动更新间隔（小时）',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => '未设置',
			'profile.detailsForm.mux' => 'Mux 多路复用',
			'profile.detailsForm.muxDescription' => '复用出站连接以减少握手开销',
			'profile.detailsForm.updateIntervalOff' => '关闭',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} 小时',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} 天',
			'profile.remoteProfile' => '远程订阅',
			'profile.defaultLocalName' => '本地导入',
			'profile.defaultDeepLinkName' => '深链导入',
			'profile.switchFailedMsg' => '切换配置文件失败',
			'proxies.pageTitle' => '线路',
			'proxies.emptyProxiesMsg' => '无可用的线路',
			'proxies.delayTestTooltip' => '测试延迟',
			'proxies.sortTooltip' => '对线路进行排序',
			'proxies.checkIp' => '检测 IP 地址',
			'proxies.unknownIp' => '未知的 IP',
			'proxies.autoSelect' => '自动选择',
			'proxies.autoSelectDescription' => '自动连接到最快的节点',
			'proxies.sortOptions.unsorted' => '默认',
			'proxies.sortOptions.name' => '按字母顺序',
			'proxies.sortOptions.delay' => '按延迟顺序',
			'proxies.sortModalTitle' => '选择排序方式',
			'proxies.activeProxySemanticLabel' => '激活的线路',
			'proxies.delaySemantics.result' => ({required Object delay}) => '延迟: ${delay}ms',
			'proxies.delaySemantics.timeout' => '延迟测试超时',
			'proxies.delaySemantics.testing' => '正在测试延迟',
			'proxies.delaySemantics.untested' => '延迟: 未测试',
			'proxies.delaySemantics.stale' => ({required Object delay}) => '延迟: ${delay}ms（历史值）',
			'proxies.ipInfoSemantics.address' => 'IP 地址',
			'proxies.ipInfoSemantics.country' => '国家',
			'proxies.testingDelayInfo' => ({required Object name}) => '正在测速: ${name}',
			'proxies.switchedTo' => ({required Object name}) => '已切换到 ${name}',
			'proxies.switchFailed' => '切换线路失败，请稍后重试',
			'proxies.testFailed' => '测速失败，请稍后重试',
			'proxies.groupsLoading' => '线路信息加载中，请稍候再试',
			'proxies.connectBeforeSwitch' => '请先连接后再切换节点',
			'proxies.startDelayTestForGroups' => ({required Object count}) => '已开始测试当前订阅的 ${count} 个节点',
			'proxies.delayTestBtn' => '测速',
			'proxies.delayTimeout' => '超时',
			'proxies.connectBeforeTest' => '请连接后测速',
			'proxies.lineCount' => ({required Object count}) => '${count} 个节点',
			'proxies.manualSelect' => '手动选择',
			'proxies.autoTest' => '自动测速',
			'logs.pageTitle' => '日志',
			'logs.filterHint' => '筛选',
			'logs.allLevelsFilter' => '全部',
			'logs.shareCoreLogs' => '分享核心日志',
			'logs.shareAppLogs' => '分享应用日志',
			'logs.pauseTooltip' => '暂停',
			'logs.resumeTooltip' => '恢复',
			'logs.clearTooltip' => '清除',
			'logs.logsCleared' => '日志已清空',
			'logs.logsCopied' => '日志已复制',
			'logs.logsUnderDevelopment' => '日志功能开发中',
			'logs.noLogsWhenDisconnected' => '未连接，无日志',
			'logs.loadFailed' => '日志读取失败',
			'logs.empty' => '暂无日志',
			'logs.clearFailed' => '清除日志失败',
			'settings.pageTitle' => '设置',
			'settings.requiresRestartMsg' => '要使其生效，请重新启动应用程序',
			'settings.experimental' => '实验性选项',
			'settings.experimentalMsg' => '带有实验标志的功能仍在开发中，可能会出现问题。',
			'settings.exportOptions' => '将匿名选项导出到剪贴板',
			'settings.exportAllOptions' => '将所有选项导出到剪贴板（用于调试）',
			'settings.importOptions' => '从剪贴板导入选项',
			'settings.importOptionsMsg' => '这将使用提供的值重写所有配置选项。您确定吗？',
			'settings.backup.importConfirmTitle' => '导入备份',
			'settings.backup.importConfirmMsg' => '这会用备份中的订阅替换当前订阅，并应用备份中的设置。导入前会先保存当前数据的快照，导入失败时自动恢复。',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '本机有 ${count} 个订阅不在备份中，导入后将被移除。',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '已导入 ${profiles} 个订阅、${settings} 项设置。',
			'settings.backup.reportDropped' => ({required Object count}) => '备份中有 ${count} 个订阅因数据无效被跳过。',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '有 ${count} 项设置被跳过，保留了当前值。',
			'settings.backup.reportWarpOff' => '导入时已关闭 WARP，请在本机重新启用。',
			'settings.backup.reportBackfill' => ({required Object count}) => '有 ${count} 个订阅将在后台下载。',
			'settings.backup.errInvalidFile' => '这不是有效的 ClashMiao 备份文件。',
			'settings.backup.errUnsupportedVersion' => '不支持这种备份格式。',
			'settings.backup.errNewerSchema' => '此备份由更新版本的应用生成，请先升级应用。',
			'settings.backup.errNoUsableProfiles' => '此备份中没有可以导入的订阅。',
			'settings.backup.errSnapshotFailed' => '无法保存当前数据的快照，所以没有做任何改动。',
			'settings.backup.errUnresolvedPrevious' => '上一次导入被中断，尚未能撤销。没有做任何改动，请重启应用后再试。',
			'settings.backup.errRolledBack' => '导入失败，已恢复到导入之前的数据。',
			'settings.backup.errNotRolledBack' => ({required Object path}) => '导入失败，且自动恢复没有完成。请重启应用让它重试。快照保存在 ${path}。',
			'settings.backup.errFailed' => '导入失败。',
			'settings.backup.errBusy' => '已有另一个导入正在进行，请等它结束后再试。',
			'settings.backup.recoveryFailedTitle' => '自动恢复没有完成',
			'settings.backup.recoveryFailedMsg' => '上一次备份导入被中断，应用没能把数据恢复到导入之前的状态，部分数据可能只导入了一半。现在重试自动恢复。',
			'settings.backup.recoveryUnrecoverableTitle' => '无法撤销被中断的导入',
			'settings.backup.recoveryUnrecoverableMsg' => '上一次备份导入被中断，但它的快照丢失或无法读取，因此无法撤销。请检查你的订阅和设置。',
			'settings.backup.recoveryRetry' => '重试',
			'settings.backup.recoveryClose' => '关闭',
			'settings.backup.recoveryRetried' => '已把数据恢复到被中断的导入之前。',
			'settings.backup.exportAction' => '导出备份',
			'settings.backup.importAction' => '导入备份',
			'settings.backup.exportFailed' => '导出失败',
			'settings.backup.shareText' => 'ClashMiao 备份',
			'settings.general.sectionTitle' => '一般选项',
			'settings.general.locale' => '语言',
			'settings.general.region' => '地区',
			'settings.general.regionMsg' => '帮助设置默认选项以绕过国内地址',
			'settings.general.regions.ir' => '伊朗 (ir)',
			'settings.general.regions.cn' => '中国 (cn)',
			'settings.general.regions.ru' => '俄罗斯 (ru)',
			'settings.general.regions.af' => '阿富汗 (af)',
			'settings.general.regions.id' => '印度尼西亚 (id)',
			'settings.general.regions.other' => '其它',
			'settings.general.themeMode' => '主题模式',
			'settings.general.themeModes.system' => '跟随系统颜色',
			'settings.general.themeModes.dark' => '暗色',
			'settings.general.themeModes.light' => '浅色',
			'settings.general.themeModes.black' => '黑色',
			'settings.general.enableAnalytics' => '启用分析',
			'settings.general.enableAnalyticsMsg' => '授予收集分析并发送崩溃报告以改进应用程序的权限',
			'settings.general.autoStart' => '开机启动',
			'settings.general.silentStart' => '静默启动',
			'settings.general.openWorkingDir' => '打开工作目录',
			'settings.general.ignoreBatteryOptimizations' => '禁用电池优化',
			'settings.general.ignoreBatteryOptimizationsMsg' => '消除限制以获得最佳 VPN 性能',
			'settings.general.dynamicNotification' => '在通知中显示网络速度',
			'settings.general.hapticFeedback' => '触觉反馈',
			'settings.general.autoIpCheck' => '自动检查连接的 IP',
			'settings.general.autoStartPermission' => '允许自启动',
			'settings.general.autoStartPermissionMsg' => '开启后，手机重启或 App 更新后能自动恢复连接',
			'settings.general.autoStartPermissionStatus.allowed' => '已开启',
			'settings.general.autoStartPermissionStatus.denied' => '未开启',
			'settings.general.autoStartPermissionStatus.unknown' => '未知',
			'settings.general.batteryOptimizationStatus.exempted' => '已豁免',
			'settings.general.batteryOptimizationStatus.notExempted' => '未豁免',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => '高级选项',
			'settings.advanced.debugMode' => '调试模式',
			'settings.advanced.debugModeMsg' => '重新启动应用程序以应用此更改',
			'settings.advanced.memoryLimit' => '内存限制',
			'settings.advanced.memoryLimitMsg' => '如果您遇到内存不足错误或频繁应用程序崩溃，请启用',
			'settings.advanced.resetTunnel' => '重置 VPN 配置文件',
			'settings.advanced.resetTunnelSuccess' => 'VPN 配置文件已重置',
			'settings.network.perAppProxyPageTitle' => '分应用线路',
			'settings.network.perAppProxyModes.off' => '全部',
			'settings.network.perAppProxyModes.offMsg' => '代理所有应用程序',
			'settings.network.perAppProxyModes.include' => '代理',
			'settings.network.perAppProxyModes.includeMsg' => '仅代理选定的应用程序',
			'settings.network.perAppProxyModes.exclude' => '绕过',
			'settings.network.perAppProxyModes.excludeMsg' => '不代理选中的应用程序',
			'settings.network.perAppProxyLoadFailedMsg' => '加载应用列表失败',
			'settings.network.perAppProxyRetry' => '重试',
			'settings.network.perAppProxyEmptyMsg' => '未找到匹配的应用',
			'settings.network.perAppProxyAndroidOnlyMsg' => '仅 Android 支持分应用线路',
			'settings.network.showSystemApps' => '显示系统应用程序',
			'settings.network.hideSystemApps' => '隐藏系统应用程序',
			'settings.network.clearSelection' => '清空选项',
			'settings.geoAssets.pageTitle' => '路由资源文件',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => '版本 ${version}',
			'settings.geoAssets.fileMissing' => '文件丢失',
			'settings.geoAssets.update' => '更新',
			'settings.geoAssets.download' => '下载',
			'settings.geoAssets.failureMsg' => '更新资源文件失败',
			'settings.geoAssets.successMsg' => '已成功更新资源文件',
			'settings.geoAssets.addRecommended' => '添加建议的资源文件',
			'settings.geoAssets.missingGeoAssetsMsg' => '所选路由资源的文件丢失。下载它们或选择现有的。',
			'settings.systemProxyEnabled' => '已开启系统代理',
			'settings.systemProxyDisabled' => '已关闭系统代理（需重连生效）',
			'settings.adminPrivilegesRequired' => 'macOS 需要管理员权限',
			'settings.portChangeNotice' => '端口修改需要重启连接生效',
			'settings.groups.general' => '通用',
			'settings.groups.connection' => '连接',
			'settings.groups.privacy' => '隐私',
			'settings.importOptionsInvalid' => '剪贴板内容不是有效的配置 JSON',
			'settings.importOptionsNothing' => '未识别到可导入的配置项',
			'settings.importOptionsDone' => ({required Object count}) => '已导入 ${count} 项配置',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '已导入 ${applied} 项配置，${skipped} 项因格式无效被跳过',
			'about.pageTitle' => '关于',
			'about.version' => '版本',
			'about.sourceCode' => '源代码',
			'about.telegramChannel' => 'Telegram 频道',
			'about.checkForUpdate' => '检查更新',
			'about.privacyPolicy' => '隐私政策',
			'about.termsAndConditions' => '条款和条件',
			'about.appDescription' => '基于 sing-box 核心的跨平台代理客户端',
			'about.openSourceLicenses' => '开源许可',
			'appUpdate.notAvailableMsg' => '已是最新版本',
			'appUpdate.dialogTitle' => '有可用更新',
			'appUpdate.updateMsg' => '${_root.general.appTitle} 的新版本现已推出。您想现在更新吗？',
			'appUpdate.currentVersionLbl' => '当前版本',
			'appUpdate.newVersionLbl' => '新版本',
			'appUpdate.updateNowBtnTxt' => '现在更新',
			'appUpdate.laterBtnTxt' => '以后再说',
			'appUpdate.ignoreBtnTxt' => '忽略',
			'appUpdate.checkFailedMsg' => '检查更新失败，请检查网络后重试',
			'tray.dashboard' => '仪表板',
			'tray.quit' => '退出',
			'tray.open' => '打开',
			'tray.hide' => '隐藏到托盘',
			'tray.status.connect' => '连接',
			'tray.status.connecting' => '正在连接',
			'tray.status.disconnect' => '断开连接',
			'tray.status.disconnecting' => '正在断开连接',
			'tray.proxyModeMenu' => '代理模式',
			'failure.unexpected' => '意外错误',
			'failure.clash.unexpected' => '意外错误',
			'failure.clash.core' => ({required Object reason}) => 'Clash 错误 ${reason}',
			'failure.singbox.unexpected' => '意外服务错误',
			'failure.singbox.serviceNotRunning' => '服务未运行',
			'failure.singbox.coreLibraryMissing' => '核心库未安装',
			'failure.singbox.missingPrivilege' => '缺少权限',
			'failure.singbox.missingPrivilegeMsg' => 'VPN 模式需要管理员权限。以管理员身份重新启动应用程序或更改服务模式',
			'failure.singbox.missingGeoAssets' => '缺失 GEO 资源文件',
			'failure.singbox.missingGeoAssetsMsg' => '缺失 GEO 资源文件。请考虑更改激活的资源文件或在设置中下载所选资源文件。',
			'failure.singbox.invalidConfigOptions' => '配置选项无效',
			'failure.singbox.invalidConfig' => '无效配置',
			'failure.singbox.create' => '服务创建错误',
			'failure.singbox.start' => '服务启动错误',
			'failure.singbox.startTimeout' => '服务启动超时',
			'failure.singbox.kernelUnresponsive' => '内核无响应，请重试或重启应用',
			'failure.singbox.kernelExited' => '内核意外退出',
			'failure.connectivity.unexpected' => '意外失败',
			'failure.connectivity.missingVpnPermission' => '缺少 VPN 权限',
			'failure.connectivity.missingNotificationPermission' => '缺少通知权限',
			'failure.connectivity.networkUnavailable' => '网络不可用',
			'failure.connectivity.core' => '核心错误',
			'failure.connectivity.nativeUnresponsive' => '与后台服务失去联系，请重试',
			'failure.profiles.unexpected' => '意外错误',
			'failure.profiles.notFound' => '未找到配置文件',
			'failure.profiles.noActive' => '没有激活的订阅',
			'failure.profiles.invalidConfig' => '无效配置',
			'failure.profiles.invalidUrl' => '网址无效',
			'failure.profiles.readOnlyUpgrade' => '请升级 App 后再修改订阅',
			'failure.connection.unexpected' => '意外连接错误',
			'failure.connection.timeout' => '连接超时',
			'failure.connection.badResponse' => '错误响应',
			'failure.connection.connectionError' => '连接错误',
			'failure.connection.badCertificate' => '证书无效',
			'failure.geoAssets.unexpected' => '意外错误',
			'failure.geoAssets.notUpdate' => '无可用更新',
			'failure.geoAssets.activeNotFound' => '未找到激活的 GEO 资源文件',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}：${reason}',
			'connection.tapToConnect' => '点击连接',
			'connection.connecting' => '正在连接',
			'connection.disconnecting' => '正在断开连接',
			'connection.connected' => '已连接',
			'connection.reconnect' => '重新连接',
			'connection.connectAnyWay' => '仍然连接',
			'connection.experimentalNotice' => '实验性功能提醒',
			'connection.experimentalNoticeMsg' => '当前配置启用了实验性高级选项（例如 TLS 混淆分片、封包填充、多路复用、WARP 中转，或允许局域网访问等），可能不稳定，连接质量或成功率会受影响。',
			'connection.disableExperimentalNotice' => '不再提示',
			'connection.reconnectMsg' => '重新连接以使更改生效',
			'connection.staleSystemProxyCleaned' => '已清理上次异常退出残留的系统代理设置',
			'config.resetBtn' => '重置选项',
			'config.serviceMode' => '服务模式',
			'config.quickSettings' => '快速设置',
			'config.quickSettingsSubtitle' => '自定义您的连接体验',
			'config.setupWarp' => '配置 WARP',
			'config.allOptions' => '全部配置选项',
			'config.allAdvancedOptions' => '所有进阶选项',
			'config.serviceModes.proxy' => '仅线路',
			'config.serviceModes.systemProxy' => '系统线路',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'VPN 服务',
			'config.shortServiceModes.proxy' => '仅线路',
			'config.shortServiceModes.systemProxy' => '系统线路',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'VPN 服务',
			'config.section.route' => '路由选项',
			'config.section.dns' => 'DNS 选项',
			'config.section.inbound' => '入站选项',
			'config.section.mux' => '多路复用',
			'config.section.outbound' => '出站选项',
			'config.section.tlsTricks' => 'TLS 特性',
			'config.section.warp' => 'WARP 选项',
			'config.section.misc' => '其它选项',
			'config.warpConsent.title' => 'Cloudflare WARP 许可条款',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP 是一个免费的 WireGuard VPN 提供商。启用此选项即表示您同意 Cloudflare WARP 的 '), tos('服務條款'), const TextSpan(text: ' 和 '), privacy('隱私權政策'), ]), 
			'config.generateWarpConfig' => '生成 WARP 配置文件',
			'config.missingWarpConfig' => 'WARP 配置文件缺失',
			'config.warpConfigGenerated' => 'WARP 配置文件已生成',
			'config.pageTitle' => '配置选项',
			'config.logLevel' => '日志级别',
			'config.blockAds' => '阻止广告',
			'config.resolveDestination' => '解析目标地址',
			'config.ipv6Mode' => 'IPv6 路由',
			'config.ipv6Modes.disable' => '禁用',
			'config.ipv6Modes.enable' => '启用',
			'config.ipv6Modes.prefer' => '首选',
			'config.ipv6Modes.only' => '仅限',
			'config.remoteDnsAddress' => '远程 DNS',
			'config.remoteDnsDomainStrategy' => '远程 DNS 域名策略',
			'config.directDnsAddress' => '直连 DNS',
			'config.directDnsDomainStrategy' => '直连 DNS 域名策略',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => '未应用：IPv6 路由已禁用，但「${field}」为仅 IPv6，会导致域名无法解析。请先启用 IPv6 路由，或换一个策略。',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => '未应用：IPv6 路由为仅限 IPv6，但「${field}」为仅 IPv4，会导致域名无法解析。请先调整其中一项。',
			'config.dnsStrategyReset' => ({required Object field}) => '「${field}」与 IPv6 路由设置冲突（会导致域名无法解析），已重置为自动。',
			'config.mixedPort' => '混合端口',
			'config.tproxyPort' => '透明线路端口',
			'config.localDnsPort' => '本地 DNS 端口',
			'config.allowConnectionFromLan' => '允许局域网连接',
			'config.tunImplementation' => 'TUN 实现',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => '连接测试网址',
			'config.urlTestInterval' => '网址测试间隔',
			'config.enableClashApi' => '启用 Clash API',
			'config.clashApiPort' => 'Clash API 端口',
			'config.enableTun' => '启用 TUN',
			'config.setSystemProxy' => '设置系统线路',
			'config.enableDnsRouting' => '启用 DNS 路由',
			'config.enableFakeDns' => '启用 Fake DNS',
			'config.bypassLan' => '绕过局域网',
			'config.strictRoute' => '严格路由',
			'config.enableTlsFragment' => '启用 TLS 数据分段',
			'config.tlsFragmentSize' => 'TLS 分段大小',
			'config.tlsFragmentSleep' => 'TLS 分段休眠',
			'config.enableTlsMixedSniCase' => '启用 TLS 混合 SNI 情形',
			'config.enableTlsPadding' => '启用 TLS 填充',
			'config.tlsPaddingSize' => 'TLS 填充',
			'config.enableMux' => '启用 Mux 多路复用',
			'config.muxProtocol' => 'Mux 协议',
			'config.muxMaxStreams' => 'Mux 最大并发数',
			'config.enableWarp' => '启用 WARP',
			'config.setUpWarp' => '设置 WARP',
			'config.warpNotConfigured' => '未配置',
			'config.warpDetourMode' => '链式线路',
			'config.warpDetourModes.proxyOverWarp' => '通过 WARP 连接线路',
			'config.warpDetourModes.warpOverProxy' => '通过线路连接 WARP',
			'config.warpDetourModes.inbound' => '通过线路绕过 WARP',
			'config.warpDetourModes.outbound' => '通过 WARP 绕过线路',
			'config.warpLicenseKey' => '许可证密钥',
			'config.warpCleanIp' => '清理 IP',
			'config.warpPort' => '端口',
			'config.warpNoise' => '噪音计数',
			'config.warpNoiseDelay' => '噪音延迟',
			'config.desktopProxyScopeNotice' => '桌面端只有遵循系统代理设置的程序会走隧道。不遵循的软件（部分游戏、命令行工具、自带代理设置的客户端）会直连，暴露你的真实 IP。',
			'config.warpNoiseSize' => '噪音大小',
			'config.warpNoiseMode' => '噪音模式',
			'config.serviceModeIosVpnOnly' => 'iOS 仅支持 VPN 模式',
			'config.warpGenerating' => '正在生成 WARP 配置…',
			'config.warpConfigFailed' => 'WARP 配置生成失败，请稍后重试',
			'config.portRangeError' => '端口范围 1024-65535',
			'config.dnsEmptyError' => 'DNS 地址不能为空',
			'config.rangeFormatError' => '请输入数字或范围，例如 10-30',
			'config.urlSchemeError' => 'URL 必须以 http:// 或 https:// 开头',
			'config.manageRuleAssets' => '规则库管理',
			_ => null,
		};
	}
}
