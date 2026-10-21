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
class TranslationsZhTw extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsZhTw({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zhTw,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh-TW>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsZhTw _root = this; // ignore: unused_field

	@override 
	TranslationsZhTw $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsZhTw(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$zh_TW general = Translations$general$zh_TW.internal(_root);
	@override late final Translations$intro$zh_TW intro = Translations$intro$zh_TW.internal(_root);
	@override late final Translations$home$zh_TW home = Translations$home$zh_TW.internal(_root);
	@override late final Translations$stats$zh_TW stats = Translations$stats$zh_TW.internal(_root);
	@override late final Translations$profile$zh_TW profile = Translations$profile$zh_TW.internal(_root);
	@override late final Translations$proxies$zh_TW proxies = Translations$proxies$zh_TW.internal(_root);
	@override late final Translations$logs$zh_TW logs = Translations$logs$zh_TW.internal(_root);
	@override late final Translations$settings$zh_TW settings = Translations$settings$zh_TW.internal(_root);
	@override late final Translations$about$zh_TW about = Translations$about$zh_TW.internal(_root);
	@override late final Translations$appUpdate$zh_TW appUpdate = Translations$appUpdate$zh_TW.internal(_root);
	@override late final Translations$tray$zh_TW tray = Translations$tray$zh_TW.internal(_root);
	@override late final Translations$failure$zh_TW failure = Translations$failure$zh_TW.internal(_root);
	@override late final Translations$connection$zh_TW connection = Translations$connection$zh_TW.internal(_root);
	@override late final Translations$config$zh_TW config = Translations$config$zh_TW.internal(_root);
}

// Path: general
class Translations$general$zh_TW extends Translations$general$en {
	Translations$general$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => '重置';
	@override late final Translations$general$toggle$zh_TW toggle = Translations$general$toggle$zh_TW.internal(_root);
	@override late final Translations$general$state$zh_TW state = Translations$general$state$zh_TW.internal(_root);
	@override String get sort => '排序';
	@override String get sortBy => '排序方式';
	@override String get addToClipboard => '新增至剪貼簿';
	@override String get notSet => '未設定';
	@override String get agree => '同意';
	@override String get decline => '拒絕';
	@override String get unknown => '不明';
	@override String get hidden => '隱藏';
	@override String get timeout => '超時';
	@override String get clipboardExportSuccessMsg => '已匯出至剪貼簿';
	@override String get showMore => '顯示更多';
	@override String get showLess => '顯示較少';
	@override String get openAppSettings => '開啟應用程式設定';
	@override String get grantPermission => '授予權限';
	@override String get underDevelopment => '功能開發中';
	@override String get confirm => '確認';
	@override String get close => '關閉';
	@override String get cancel => '取消';
	@override String get clipboardEmpty => '剪貼簿為空';
	@override String get clipboardReadFailed => '讀取剪貼簿失敗';
	@override String get moreOptions => '更多選項';
}

// Path: intro
class Translations$intro$zh_TW extends Translations$intro$en {
	Translations$intro$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: '繼續即表示您同意合約 '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => '開始';
}

// Path: home
class Translations$home$zh_TW extends Translations$home$en {
	Translations$home$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '首頁';
	@override String get emptyProfilesMsg => '首先新增訂閱設定檔';
	@override String get noActiveProfileMsg => '選擇設定檔';
	@override late final Translations$home$routingMode$zh_TW routingMode = Translations$home$routingMode$zh_TW.internal(_root);
	@override String failedToSwitchMode({required Object error}) => '切換模式失敗：${error}';
	@override String get connectionFailedTitle => '連線失敗';
	@override String get coreMissingTitle => '找不到核心程式庫';
	@override String get coreMissingMsg => '應用程式未能載入網路核心程式庫，無法建立連線。請重新安裝應用程式，或確認核心程式庫檔案與主程式在同一目錄下。';
	@override String get degradedTitle => '已連線，但無法存取網路';
	@override String get degradedMsg => '通道已建立，但資料送不出去。可能是節點已失效——試試換一個節點，或者中斷連線。';
	@override String get degradedRetry => '重新檢測';
	@override late final Translations$home$egressIp$zh_TW egressIp = Translations$home$egressIp$zh_TW.internal(_root);
	@override String get emptyProfilesHint => '點擊下方按鈕開始探索';
	@override String get noActiveProfileTitle => '未選擇設定檔';
}

// Path: stats
class Translations$stats$zh_TW extends Translations$stats$en {
	Translations$stats$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get traffic => '流量';
	@override String get trafficLive => '即時流量';
	@override String get trafficTotal => '總流量';
	@override String get uplink => '上行';
	@override String get downlink => '下行';
	@override String get connection => '連線';
	@override String get speed => '速度';
	@override String get totalTransferred => '總傳輸量';
	@override String get trafficUsage => '流量使用';
	@override String get liveSpeed => '即時速度';
	@override String get sessionTraffic => '本次流量';
	@override String get downloadSpeed => '下載速度';
}

// Path: profile
class Translations$profile$zh_TW extends Translations$profile$en {
	Translations$profile$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => '設定檔';
	@override String get detailsPageTitle => '設定檔';
	@override String activeProfileNameSemanticLabel({required Object name}) => '活動設定檔名稱：“${name}”。';
	@override String get activeProfileBtnSemanticLabel => '查看所有設定檔';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => '選擇“${name}”作為活動設定檔。';
	@override late final Translations$profile$subscription$zh_TW subscription = Translations$profile$subscription$zh_TW.internal(_root);
	@override late final Translations$profile$sortBy$zh_TW sortBy = Translations$profile$sortBy$zh_TW.internal(_root);
	@override late final Translations$profile$add$zh_TW add = Translations$profile$add$zh_TW.internal(_root);
	@override late final Translations$profile$update$zh_TW update = Translations$profile$update$zh_TW.internal(_root);
	@override late final Translations$profile$share$zh_TW share = Translations$profile$share$zh_TW.internal(_root);
	@override late final Translations$profile$edit$zh_TW edit = Translations$profile$edit$zh_TW.internal(_root);
	@override late final Translations$profile$delete$zh_TW delete = Translations$profile$delete$zh_TW.internal(_root);
	@override late final Translations$profile$save$zh_TW save = Translations$profile$save$zh_TW.internal(_root);
	@override late final Translations$profile$detailsForm$zh_TW detailsForm = Translations$profile$detailsForm$zh_TW.internal(_root);
	@override late final Translations$profile$actionButtons$zh_TW actionButtons = Translations$profile$actionButtons$zh_TW.internal(_root);
	@override late final Translations$profile$details$zh_TW details = Translations$profile$details$zh_TW.internal(_root);
	@override late final Translations$profile$overview$zh_TW overview = Translations$profile$overview$zh_TW.internal(_root);
	@override String get remoteProfile => '遠端訂閱';
	@override String get defaultLocalName => '本機匯入';
	@override String get defaultDeepLinkName => '連結匯入';
	@override String get switchFailedMsg => '切換設定檔失敗';
}

// Path: proxies
class Translations$proxies$zh_TW extends Translations$proxies$en {
	Translations$proxies$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '線路';
	@override String get emptyProxiesMsg => '沒有可用的線路';
	@override String get delayTestTooltip => '測試延遲';
	@override String get sortTooltip => '對線路進行排序';
	@override String get checkIp => '檢測 IP 地址';
	@override String get unknownIp => '不明的 IP';
	@override late final Translations$proxies$sortOptions$zh_TW sortOptions = Translations$proxies$sortOptions$zh_TW.internal(_root);
	@override String get activeProxySemanticLabel => '生效中的線路';
	@override late final Translations$proxies$delaySemantics$zh_TW delaySemantics = Translations$proxies$delaySemantics$zh_TW.internal(_root);
	@override late final Translations$proxies$ipInfoSemantics$zh_TW ipInfoSemantics = Translations$proxies$ipInfoSemantics$zh_TW.internal(_root);
	@override String get autoSelect => '自動選擇';
	@override String get autoSelectDescription => '自動連線到最快的節點';
	@override String get sortModalTitle => '選擇排序方式';
	@override String testingDelayInfo({required Object name}) => '正在檢測延遲：${name}';
	@override String switchedTo({required Object name}) => '已切換到 ${name}';
	@override String get switchFailed => '切換線路失敗，請稍後重試';
	@override String get testFailed => '測速失敗，請稍後重試';
	@override String get groupsLoading => '線路資訊載入中，請稍候再試';
	@override String get connectBeforeSwitch => '請先連線再切換線路';
	@override String startDelayTestForGroups({required Object count}) => '已開始檢測 ${count} 條線路的延遲';
	@override String get delayTestBtn => '延遲';
	@override String get delayTimeout => '逾時';
	@override String get connectBeforeTest => '請連線後再測速';
	@override String lineCount({required Object count}) => '${count} 條線路';
	@override String get manualSelect => '手動選擇';
	@override String get autoTest => '自動測速';
}

// Path: logs
class Translations$logs$zh_TW extends Translations$logs$en {
	Translations$logs$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '記錄檔';
	@override String get filterHint => '篩選';
	@override String get allLevelsFilter => '全部';
	@override String get shareCoreLogs => '分享核心記錄檔';
	@override String get shareAppLogs => '分享應用程式記錄檔';
	@override String get pauseTooltip => '暫停';
	@override String get resumeTooltip => '恢復';
	@override String get clearTooltip => '清除';
	@override String get logsCleared => '日誌已清空';
	@override String get logsCopied => '日誌已複製';
	@override String get logsUnderDevelopment => '日誌功能開發中';
	@override String get noLogsWhenDisconnected => '未連線，無日誌';
	@override String get loadFailed => '日誌讀取失敗';
	@override String get empty => '暫無日誌';
	@override String get clearFailed => '清除日誌失敗';
}

// Path: settings
class Translations$settings$zh_TW extends Translations$settings$en {
	Translations$settings$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '設定';
	@override String get requiresRestartMsg => '若要使其生效，請重新啟動應用程式';
	@override String get experimental => '實驗性的';
	@override String get experimentalMsg => '帶有實驗標誌的功能仍在開發中，可能會導致問題。';
	@override String get exportOptions => '匯出選項至剪貼簿';
	@override String get exportAllOptions => '匯出選項至剪貼簿(用於偵錯) ';
	@override String get importOptions => '從剪貼簿匯入選項';
	@override String get importOptionsMsg => '這將使用提供的值複寫所有配置選項。您確定嗎？';
	@override late final Translations$settings$backup$zh_TW backup = Translations$settings$backup$zh_TW.internal(_root);
	@override late final Translations$settings$general$zh_TW general = Translations$settings$general$zh_TW.internal(_root);
	@override late final Translations$settings$advanced$zh_TW advanced = Translations$settings$advanced$zh_TW.internal(_root);
	@override late final Translations$settings$network$zh_TW network = Translations$settings$network$zh_TW.internal(_root);
	@override late final Translations$settings$geoAssets$zh_TW geoAssets = Translations$settings$geoAssets$zh_TW.internal(_root);
	@override String get systemProxyEnabled => '系統代理已啟用';
	@override String get systemProxyDisabled => '系統代理已停用（重新連線後生效）';
	@override String get adminPrivilegesRequired => 'macOS 上需要管理員權限';
	@override String get portChangeNotice => '連接埠變更需要重新連線才會生效';
	@override late final Translations$settings$groups$zh_TW groups = Translations$settings$groups$zh_TW.internal(_root);
	@override String get importOptionsInvalid => '剪貼簿內容不是有效的設定 JSON';
	@override String get importOptionsNothing => '未識別到可匯入的設定項';
	@override String importOptionsDone({required Object count}) => '已匯入 ${count} 項設定';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '已匯入 ${applied} 項設定，${skipped} 項因格式無效被略過';
}

// Path: about
class Translations$about$zh_TW extends Translations$about$en {
	Translations$about$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '關於';
	@override String get version => '版本';
	@override String get sourceCode => '原始碼';
	@override String get telegramChannel => 'Telegram 頻道';
	@override String get checkForUpdate => '檢查更新';
	@override String get privacyPolicy => '隱私政策';
	@override String get termsAndConditions => '條款與條件';
	@override String get appDescription => '基於 sing-box 核心的跨平台代理用戶端';
	@override String get openSourceLicenses => '開放原始碼授權';
}

// Path: appUpdate
class Translations$appUpdate$zh_TW extends Translations$appUpdate$en {
	Translations$appUpdate$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => '已經是最新版本';
	@override String get dialogTitle => '有可用更新';
	@override String get updateMsg => '${_root.general.appTitle} 的更新版本現已推出。您想立即更新嗎？';
	@override String get currentVersionLbl => '目前版本';
	@override String get newVersionLbl => '新版本';
	@override String get updateNowBtnTxt => '立即更新';
	@override String get laterBtnTxt => '稍後再說';
	@override String get ignoreBtnTxt => '忽略';
	@override String get checkFailedMsg => '檢查更新失敗，請檢查網路後再試';
}

// Path: tray
class Translations$tray$zh_TW extends Translations$tray$en {
	Translations$tray$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get dashboard => '儀表板';
	@override String get quit => '退出';
	@override String get open => '開啟';
	@override late final Translations$tray$status$zh_TW status = Translations$tray$status$zh_TW.internal(_root);
	@override String get hide => '隱藏';
	@override String get proxyModeMenu => '代理模式';
}

// Path: failure
class Translations$failure$zh_TW extends Translations$failure$en {
	Translations$failure$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外錯誤';
	@override late final Translations$failure$clash$zh_TW clash = Translations$failure$clash$zh_TW.internal(_root);
	@override late final Translations$failure$singbox$zh_TW singbox = Translations$failure$singbox$zh_TW.internal(_root);
	@override late final Translations$failure$connectivity$zh_TW connectivity = Translations$failure$connectivity$zh_TW.internal(_root);
	@override late final Translations$failure$profiles$zh_TW profiles = Translations$failure$profiles$zh_TW.internal(_root);
	@override late final Translations$failure$connection$zh_TW connection = Translations$failure$connection$zh_TW.internal(_root);
	@override late final Translations$failure$geoAssets$zh_TW geoAssets = Translations$failure$geoAssets$zh_TW.internal(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}：${reason}';
}

// Path: connection
class Translations$connection$zh_TW extends Translations$connection$en {
	Translations$connection$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => '點擊以連線';
	@override String get connecting => '連線中';
	@override String get disconnecting => '中斷連線中';
	@override String get connected => '已連線';
	@override String get reconnect => '重新連線';
	@override String get connectAnyWay => '仍然連線';
	@override String get experimentalNotice => '實驗性功能提醒';
	@override String get experimentalNoticeMsg => '目前設定啟用了實驗性進階選項（例如 TLS 混淆分片、封包填充、多工、WARP 中轉，或允許區域網路存取等），可能不穩定，連線品質或成功率會受影響。';
	@override String get disableExperimentalNotice => '不再提示';
	@override String get reconnectMsg => '重新連線以使變更生效';
	@override String get staleSystemProxyCleaned => '已清理上次異常結束殘留的系統代理設定';
}

// Path: config
class Translations$config$zh_TW extends Translations$config$en {
	Translations$config$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => '重置選項';
	@override String get serviceMode => '服務模式';
	@override String get quickSettings => '快速設定';
	@override String get setupWarp => '配置 WARP';
	@override String get allOptions => '全部配置選項';
	@override late final Translations$config$serviceModes$zh_TW serviceModes = Translations$config$serviceModes$zh_TW.internal(_root);
	@override late final Translations$config$shortServiceModes$zh_TW shortServiceModes = Translations$config$shortServiceModes$zh_TW.internal(_root);
	@override late final Translations$config$section$zh_TW section = Translations$config$section$zh_TW.internal(_root);
	@override late final Translations$config$warpConsent$zh_TW warpConsent = Translations$config$warpConsent$zh_TW.internal(_root);
	@override String get generateWarpConfig => '生成 WARP 配置檔案';
	@override String get missingWarpConfig => 'WARP 配置檔案缺失';
	@override String get warpConfigGenerated => 'WARP 配置檔案已生成';
	@override String get pageTitle => '配置選項';
	@override String get logLevel => '紀錄等級';
	@override String get resolveDestination => '解析目標地址';
	@override String get ipv6Mode => 'IPv6 路由';
	@override late final Translations$config$ipv6Modes$zh_TW ipv6Modes = Translations$config$ipv6Modes$zh_TW.internal(_root);
	@override String get remoteDnsAddress => '遠端 DNS';
	@override String get remoteDnsDomainStrategy => '遠端 DNS 網域策略';
	@override String get directDnsAddress => '直連 DNS';
	@override String get directDnsDomainStrategy => '直連 DNS 網域策略';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => '未套用：IPv6 路由已停用，但「${field}」為僅 IPv6，會導致網域無法解析。請先啟用 IPv6 路由，或換一個策略。';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => '未套用：IPv6 路由為僅限 IPv6，但「${field}」為僅 IPv4，會導致網域無法解析。請先調整其中一項。';
	@override String dnsStrategyReset({required Object field}) => '「${field}」與 IPv6 路由設定衝突（會導致網域無法解析），已重設為自動。';
	@override String get mixedPort => '混合連接埠';
	@override String get tproxyPort => '透明線路埠';
	@override String get localDnsPort => '本機 DNS 連接埠';
	@override String get allowConnectionFromLan => '允許區域網路連線';
	@override String get tunImplementation => 'TUN 實現';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => '連線測試網址';
	@override String get urlTestInterval => '網址測試間隔';
	@override String get enableClashApi => '啟用 Clash API';
	@override String get clashApiPort => 'Clash API 連接埠';
	@override String get enableTun => '啟用 TUN';
	@override String get setSystemProxy => '設定系統線路';
	@override String get enableDnsRouting => '啟用 DNS 路由';
	@override String get enableFakeDns => '啟用 Fake DNS';
	@override String get bypassLan => '繞過區域網路';
	@override String get strictRoute => '嚴格路由';
	@override String get enableTlsFragment => '啟用 TLS 分段';
	@override String get tlsFragmentSize => 'TLS 分段大小';
	@override String get tlsFragmentSleep => 'TLS 分段睡眠';
	@override String get enableTlsMixedSniCase => '啟用 TLS 混合 SNI 情況';
	@override String get enableTlsPadding => '啟用 TLS 填充';
	@override String get tlsPaddingSize => 'TLS 填充';
	@override String get enableMux => '啟用復用器';
	@override String get muxProtocol => '復用器控制';
	@override String get muxMaxStreams => '最大並發數';
	@override String get enableWarp => '啟用 WARP';
	@override String get setUpWarp => '設定 WARP';
	@override String get warpNotConfigured => '未設定';
	@override String get warpDetourMode => '鏈式線路';
	@override late final Translations$config$warpDetourModes$zh_TW warpDetourModes = Translations$config$warpDetourModes$zh_TW.internal(_root);
	@override String get warpLicenseKey => '授權金鑰';
	@override String get warpCleanIp => '清理 IP';
	@override String get warpPort => '連接埠';
	@override String get warpNoise => '噪音計數';
	@override String get warpNoiseDelay => '噪音延遲';
	@override String get quickSettingsSubtitle => '自訂您的連線體驗';
	@override String get allAdvancedOptions => '所有進階選項';
	@override String get blockAds => '封鎖廣告';
	@override String get warpNoiseSize => '雜訊大小';
	@override String get warpNoiseMode => '雜訊模式';
	@override String get desktopProxyScopeNotice => '桌面端只有遵循系統代理設定的程式會走通道。不遵循的軟體（部分遊戲、命令列工具、自帶代理設定的用戶端）會直連，暴露你的真實 IP。';
	@override String get serviceModeIosVpnOnly => 'iOS 僅支援 VPN 模式';
	@override String get warpGenerating => '正在產生 WARP 設定…';
	@override String get warpConfigFailed => 'WARP 設定產生失敗，請稍後再試';
	@override String get portRangeError => '連接埠範圍 1024-65535';
	@override String get dnsEmptyError => 'DNS 位址不能為空';
	@override String get rangeFormatError => '請輸入數字或範圍，例如 10-30';
	@override String get urlSchemeError => 'URL 必須以 http:// 或 https:// 開頭';
	@override String get manageRuleAssets => '規則庫管理';
}

// Path: general.toggle
class Translations$general$toggle$zh_TW extends Translations$general$toggle$en {
	Translations$general$toggle$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get enabled => '啟用';
	@override String get disabled => '停用';
}

// Path: general.state
class Translations$general$state$zh_TW extends Translations$general$state$en {
	Translations$general$state$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get disable => '停用';
}

// Path: home.routingMode
class Translations$home$routingMode$zh_TW extends Translations$home$routingMode$en {
	Translations$home$routingMode$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get global => '全域代理';
	@override String get smart => '智慧分流';
}

// Path: home.egressIp
class Translations$home$egressIp$zh_TW extends Translations$home$egressIp$en {
	Translations$home$egressIp$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get label => '出口 IP';
	@override String get notConnected => '連線後顯示出口 IP';
	@override String get tapToCheck => '點擊檢測出口 IP';
	@override String get checking => '正在檢測…';
	@override String get failedRetry => '檢測失敗，點擊重試';
}

// Path: profile.subscription
class Translations$profile$subscription$zh_TW extends Translations$profile$subscription$en {
	Translations$profile$subscription$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get traffic => '流量';
	@override String updatedTimeAgo({required Object timeago}) => '更新於 ${timeago}';
	@override String remainingDuration({required Object duration}) => '剩餘 ${duration} 天';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '已使用 ${consumed} 流量，總共 ${total} 流量。';
	@override String get expired => '已到期';
	@override String get noTraffic => '超過配額';
	@override String get upload => '上傳';
	@override String get download => '下載';
	@override String get total => '總流量';
	@override String get expireDate => '到期時間';
}

// Path: profile.sortBy
class Translations$profile$sortBy$zh_TW extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => '最近更新';
	@override String get name => '按字母順序';
}

// Path: profile.add
class Translations$profile$add$zh_TW extends Translations$profile$add$en {
	Translations$profile$add$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '新的設定檔';
	@override String get shortBtnTxt => '新的設定檔';
	@override String get fromClipboard => '從剪貼簿新增';
	@override String get scanQr => '掃描 QR code';
	@override late final Translations$profile$add$qrScanner$zh_TW qrScanner = Translations$profile$add$qrScanner$zh_TW.internal(_root);
	@override String get manually => '手動輸入';
	@override String get addWarp => '添加 WARP';
	@override String get addingWarpMsg => '我們正在註冊 WARP，請稍候。';
	@override String get addingProfileMsg => '新增設定檔';
	@override String get failureMsg => '新增設定檔失敗';
	@override String get modalSubtitle => '選擇新增設定檔的方式';
	@override String get manuallyDescription => '手動輸入伺服器設定';
	@override String get warpDescription => '使用 Cloudflare WARP 免費加速';
	@override String importedNamed({required Object name}) => '已匯入訂閱：${name}';
	@override String get clipboardEmpty => '剪貼簿為空，無法匯入訂閱';
	@override String get deepLinkMissingUrl => '連結中缺少訂閱位址';
	@override String get successMsg => '新增成功';
	@override String get nameAutoHint => '自動識別（選填）';
}

// Path: profile.update
class Translations$profile$update$zh_TW extends Translations$profile$update$en {
	Translations$profile$update$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '更新';
	@override String get tooltip => '更新設定檔';
	@override String get updateSubscriptions => '更新訂閱';
	@override String get failureMsg => '更新設定檔失敗';
	@override String get successMsg => '設定檔更新成功';
	@override String namedFailureMsg({required Object name}) => '無法更新“${name}”';
	@override String namedSuccessMsg({required Object name}) => '“${name}” 更新成功';
}

// Path: profile.share
class Translations$profile$share$zh_TW extends Translations$profile$share$en {
	Translations$profile$share$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '分享';
	@override String get exportToClipboardSuccess => '匯出到剪貼簿';
	@override String get exportSubLinkToClipboard => '將訂閱連結匯出到剪貼簿';
	@override String get subLinkQrCode => '訂閱連結 QR code';
	@override String get exportConfigToClipboard => '將配置匯出到剪貼簿';
	@override String get exportConfigToClipboardSuccess => '配置已複製到剪貼簿';
	@override String get shareLink => '分享連結';
	@override String get subscriptionLinkCopied => '訂閱連結已複製';
	@override String get configCopied => '設定已複製';
	@override String get copyFailed => '複製失敗';
}

// Path: profile.edit
class Translations$profile$edit$zh_TW extends Translations$profile$edit$en {
	Translations$profile$edit$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '編輯';
	@override String get selectActiveTxt => '選擇活動設定檔';
}

// Path: profile.delete
class Translations$profile$delete$zh_TW extends Translations$profile$delete$en {
	Translations$profile$delete$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => '刪除';
	@override String get confirmationMsg => '要永久刪除設定檔嗎？';
	@override String get successMsg => '設定檔刪除成功';
	@override String get confirmTitle => '刪除設定檔';
	@override String namedConfirmMsg({required Object name}) => '確定要刪除「${name}」嗎？此操作無法復原。';
}

// Path: profile.save
class Translations$profile$save$zh_TW extends Translations$profile$save$en {
	Translations$profile$save$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get buttonText => '儲存';
	@override String get successMsg => '設定檔儲存成功';
	@override String get failureMsg => '設定檔儲存失敗';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$zh_TW extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => '名稱';
	@override String get nameHint => '設定檔名稱';
	@override String get urlLabel => '網址';
	@override String get urlHint => '完整配置網址';
	@override String get emptyNameMsg => '名稱為必填項';
	@override String get invalidUrlMsg => '無效的網址';
	@override String get lastUpdate => '最後更新';
	@override String get updateInterval => '自動更新';
	@override String get updateIntervalDialogTitle => '自動更新間隔（以小時為單位）';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => '關閉';
	@override String updateIntervalHours({required Object hours}) => '${hours} 小時';
	@override String updateIntervalDays({required Object days}) => '${days} 天';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$zh_TW extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get add => '新增';
	@override String get updateAll => '全部更新';
	@override String get sort => '排序';
	@override String get copyConfigSuccess => '設定已複製';
	@override String get editConfig => '編輯設定';
}

// Path: profile.details
class Translations$profile$details$zh_TW extends Translations$profile$details$en {
	Translations$profile$details$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => '基本資訊';
	@override String get subscriptionStatus => '訂閱狀態';
	@override String get options => '選項';
	@override String get updateNow => '立即更新';
	@override String get updateNowDescription => '從伺服器取得最新設定';
	@override String get expireDate => '到期日期';
	@override String get unlimited => '無限制';
}

// Path: profile.overview
class Translations$profile$overview$zh_TW extends Translations$profile$overview$en {
	Translations$profile$overview$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => '目前使用中';
	@override String remainingDays({required Object days}) => '剩餘 ${days} 天';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$zh_TW extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unsorted => '預設';
	@override String get name => '按字母排序';
	@override String get delay => '按延遲排序';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$zh_TW extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => '延遲： ${delay}ms';
	@override String get timeout => '延遲測試超時';
	@override String get testing => '正在測試延遲';
	@override String get untested => '延遲： 未測試';
	@override String stale({required Object delay}) => '延遲： ${delay}ms（歷史值）';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$zh_TW extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get address => 'IP 地址';
	@override String get country => '國家';
}

// Path: settings.backup
class Translations$settings$backup$zh_TW extends Translations$settings$backup$en {
	Translations$settings$backup$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => '匯入備份';
	@override String get importConfirmMsg => '這會用備份中的訂閱取代目前的訂閱，並套用備份中的設定。匯入前會先儲存目前資料的快照，匯入失敗時自動還原。';
	@override String importRemovesMsg({required Object count}) => '本機有 ${count} 個訂閱不在備份中，匯入後將被移除。';
	@override String reportImported({required Object profiles, required Object settings}) => '已匯入 ${profiles} 個訂閱、${settings} 項設定。';
	@override String reportDropped({required Object count}) => '備份中有 ${count} 個訂閱因資料無效而被略過。';
	@override String reportSettingsSkipped({required Object count}) => '有 ${count} 項設定被略過，保留了目前的值。';
	@override String get reportWarpOff => '匯入時已關閉 WARP，請在本機重新啟用。';
	@override String reportBackfill({required Object count}) => '有 ${count} 個訂閱將在背景下載。';
	@override String get errInvalidFile => '這不是有效的 ClashMiao 備份檔案。';
	@override String get errUnsupportedVersion => '不支援這種備份格式。';
	@override String get errNewerSchema => '此備份由較新版本的應用程式建立，請先升級應用程式。';
	@override String get errNoUsableProfiles => '此備份中沒有可以匯入的訂閱。';
	@override String get errSnapshotFailed => '無法儲存目前資料的快照，因此沒有做任何變更。';
	@override String get errUnresolvedPrevious => '上一次匯入被中斷，尚未能復原。沒有做任何變更，請重新啟動應用程式後再試。';
	@override String get errRolledBack => '匯入失敗，已還原到匯入之前的資料。';
	@override String errNotRolledBack({required Object path}) => '匯入失敗，且自動還原沒有完成。請重新啟動應用程式讓它重試。快照儲存在 ${path}。';
	@override String get errFailed => '匯入失敗。';
	@override String get errBusy => '已有另一個匯入正在進行，請等它結束後再試。';
	@override String get recoveryFailedTitle => '自動還原沒有完成';
	@override String get recoveryFailedMsg => '上一次備份匯入被中斷，應用程式未能把資料還原到匯入之前的狀態，部分資料可能只匯入了一半。現在重試自動還原。';
	@override String get recoveryUnrecoverableTitle => '無法復原被中斷的匯入';
	@override String get recoveryUnrecoverableMsg => '上一次備份匯入被中斷，但它的快照遺失或無法讀取，因此無法復原。請檢查你的訂閱和設定。';
	@override String get recoveryRetry => '重試';
	@override String get recoveryClose => '關閉';
	@override String get recoveryRetried => '已把資料還原到被中斷的匯入之前。';
	@override String get exportAction => '匯出備份';
	@override String get importAction => '匯入備份';
	@override String get exportFailed => '匯出失敗';
	@override String get shareText => 'ClashMiao 備份';
}

// Path: settings.general
class Translations$settings$general$zh_TW extends Translations$settings$general$en {
	Translations$settings$general$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '一般';
	@override String get locale => '語言';
	@override String get region => '地區';
	@override String get regionMsg => '幫助設定預設選項以繞過國內地址';
	@override late final Translations$settings$general$regions$zh_TW regions = Translations$settings$general$regions$zh_TW.internal(_root);
	@override String get themeMode => '主題模式';
	@override late final Translations$settings$general$themeModes$zh_TW themeModes = Translations$settings$general$themeModes$zh_TW.internal(_root);
	@override String get enableAnalytics => '啟用分析';
	@override String get enableAnalyticsMsg => '授予收集分析並傳送崩潰報告以改進應用程式的權限';
	@override String get autoStart => '隨系統啟動';
	@override String get silentStart => '啟動最小化';
	@override String get openWorkingDir => '開啟工作目錄';
	@override String get ignoreBatteryOptimizations => '停用電池最佳化';
	@override String get ignoreBatteryOptimizationsMsg => '消除限制以獲得最佳 VPN 效能';
	@override String get dynamicNotification => '在通知中顯示速度';
	@override String get hapticFeedback => '觸覺回饋';
	@override String get autoIpCheck => '自動檢查連線的 IP';
	@override late final Translations$settings$general$batteryOptimizationStatus$zh_TW batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$zh_TW.internal(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$zh_TW extends Translations$settings$advanced$en {
	Translations$settings$advanced$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => '進階設定';
	@override String get debugMode => '偵錯模式';
	@override String get debugModeMsg => '重新啟動應用程式以套用此變更';
	@override String get memoryLimit => '記憶體限制';
	@override String get memoryLimitMsg => '如果您遇到記憶體不足錯誤或頻繁應用程式崩潰，請啟用';
	@override String get resetTunnel => '重置 VPN 設定檔';
	@override String get resetTunnelSuccess => 'VPN 設定檔已重設';
}

// Path: settings.network
class Translations$settings$network$zh_TW extends Translations$settings$network$en {
	Translations$settings$network$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => '應用程式線路模式';
	@override late final Translations$settings$network$perAppProxyModes$zh_TW perAppProxyModes = Translations$settings$network$perAppProxyModes$zh_TW.internal(_root);
	@override String get showSystemApps => '顯示系統應用程式';
	@override String get hideSystemApps => '隱藏系統應用程式';
	@override String get clearSelection => '清空選項';
	@override String get perAppProxyLoadFailedMsg => '載入應用程式清單失敗';
	@override String get perAppProxyRetry => '重試';
	@override String get perAppProxyEmptyMsg => '找不到結果';
	@override String get perAppProxyAndroidOnlyMsg => '分應用線路模式僅支援 Android';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$zh_TW extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => '路由資源文件';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => '版本${version}';
	@override String get fileMissing => '檔案遺失';
	@override String get update => '更新';
	@override String get download => '下載';
	@override String get failureMsg => '更新資源文件失敗';
	@override String get successMsg => '已成功更新資源文件';
	@override String get addRecommended => '新增推薦的資源文件';
	@override String get missingGeoAssetsMsg => '所選路由資源的檔案遺失。下載它們或選擇現有的。';
}

// Path: settings.groups
class Translations$settings$groups$zh_TW extends Translations$settings$groups$en {
	Translations$settings$groups$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get general => '一般';
	@override String get connection => '連線';
	@override String get privacy => '隱私';
}

// Path: tray.status
class Translations$tray$status$zh_TW extends Translations$tray$status$en {
	Translations$tray$status$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get connect => '連線';
	@override String get connecting => '連線中';
	@override String get disconnect => '中斷連線';
	@override String get disconnecting => '中斷連線中';
}

// Path: failure.clash
class Translations$failure$clash$zh_TW extends Translations$failure$clash$en {
	Translations$failure$clash$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外錯誤';
	@override String core({required Object reason}) => 'Clash 錯誤 ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$zh_TW extends Translations$failure$singbox$en {
	Translations$failure$singbox$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外服務錯誤';
	@override String get serviceNotRunning => '服務未執行';
	@override String get missingPrivilege => '缺少權限';
	@override String get missingPrivilegeMsg => 'VPN 模式需要管理員權限。以管理員身分重新啟動應用程式或變更服務模式。';
	@override String get missingGeoAssets => '缺少 GEO 資源文件';
	@override String get missingGeoAssetsMsg => 'GEO 資源文件缺失。請考慮更改活動資源文件或在設定中下載選定的資源文件。';
	@override String get invalidConfigOptions => '配置選項無效';
	@override String get invalidConfig => '無效配置';
	@override String get create => '服務建立錯誤';
	@override String get start => '服務啟動錯誤';
	@override String get coreLibraryMissing => '核心程式庫未安裝';
	@override String get startTimeout => '服務啟動逾時';
	@override String get kernelUnresponsive => '核心無回應，請重試或重新啟動應用程式';
	@override String get kernelExited => '核心意外結束';
}

// Path: failure.connectivity
class Translations$failure$connectivity$zh_TW extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外失敗';
	@override String get missingVpnPermission => '缺少 VPN 權限';
	@override String get missingNotificationPermission => '缺少通知權限';
	@override String get core => '核心錯誤';
	@override String get networkUnavailable => '網路無法使用';
	@override String get nativeUnresponsive => '與背景服務失去連線，請重試';
}

// Path: failure.profiles
class Translations$failure$profiles$zh_TW extends Translations$failure$profiles$en {
	Translations$failure$profiles$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外錯誤';
	@override String get notFound => '未找到設定檔';
	@override String get invalidConfig => '無效配置';
	@override String get invalidUrl => '無效網址';
	@override String get noActive => '沒有啟用的訂閱';
	@override String get readOnlyUpgrade => '請升級 App 後再修改訂閱';
}

// Path: failure.connection
class Translations$failure$connection$zh_TW extends Translations$failure$connection$en {
	Translations$failure$connection$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外連線錯誤';
	@override String get timeout => '連線超時';
	@override String get badResponse => '錯誤反應';
	@override String get connectionError => '連線錯誤';
	@override String get badCertificate => '無效證書';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$zh_TW extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get unexpected => '意外錯誤';
	@override String get notUpdate => '暫無可用更新';
	@override String get activeNotFound => '未找到活動 GEO 資源文件';
}

// Path: config.serviceModes
class Translations$config$serviceModes$zh_TW extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get proxy => '僅線路';
	@override String get systemProxy => '系統線路';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN 服務';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$zh_TW extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get proxy => '僅線路';
	@override String get systemProxy => '系統線路';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN 服務';
}

// Path: config.section
class Translations$config$section$zh_TW extends Translations$config$section$en {
	Translations$config$section$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get route => '路由選項';
	@override String get dns => 'DNS 選項';
	@override String get inbound => '入站選項';
	@override String get mux => '復用器';
	@override String get outbound => '出站選項';
	@override String get tlsTricks => 'TLS 特性';
	@override String get warp => 'WARP 選項';
	@override String get misc => '其他選項';
}

// Path: config.warpConsent
class Translations$config$warpConsent$zh_TW extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cloudflare WARP 授權條款';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP 是一個免費的 WireGuard VPN 提供商。啟用此選項即表示您同意 Cloudflare WARP 的 '),
		tos('服務條款'),
		const TextSpan(text: ' 和 '),
		privacy('隱私權政策'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$zh_TW extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get disable => '停用';
	@override String get enable => '啟用';
	@override String get prefer => '首選';
	@override String get only => '僅限';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$zh_TW extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get proxyOverWarp => '透過 WARP 連線線路';
	@override String get warpOverProxy => '透過線路連線 WARP';
	@override String get inbound => '透過線路繞過 WARP';
	@override String get outbound => '透過 WARP 繞過線路';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$zh_TW extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => '沒有權限';
	@override String get unexpectedError => '出了點問題';
	@override String get torchSemanticLabel => '手電筒';
	@override String get facingSemanticLabel => '相機朝向';
	@override String get permissionRequest => '授予相機權限已允許掃描 QR code';
}

// Path: settings.general.regions
class Translations$settings$general$regions$zh_TW extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get ir => '伊朗 (ir)';
	@override String get cn => '中國 (cn)';
	@override String get ru => '俄羅斯 (ru)';
	@override String get af => '阿富汗 (af)';
	@override String get id => '印尼 (id)';
	@override String get other => '其他';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$zh_TW extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get system => '跟隨系統顏色';
	@override String get dark => '深色';
	@override String get light => '淺色';
	@override String get black => '黑色';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$zh_TW extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get exempted => '已豁免';
	@override String get notExempted => '未豁免';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$zh_TW extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$zh_TW.internal(TranslationsZhTw root) : this._root = root, super.internal(root);

	final TranslationsZhTw _root; // ignore: unused_field

	// Translations
	@override String get off => '全部';
	@override String get offMsg => '透過線路代理所有應用程式';
	@override String get include => '代理';
	@override String get includeMsg => '僅透過線路代理選定的應用程式';
	@override String get exclude => '略過';
	@override String get excludeMsg => '不透過線路代理選定的應用程式';
}

/// The flat map containing all translations for locale <zh-TW>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsZhTw {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => '重置',
			'general.toggle.enabled' => '啟用',
			'general.toggle.disabled' => '停用',
			'general.state.disable' => '停用',
			'general.sort' => '排序',
			'general.sortBy' => '排序方式',
			'general.addToClipboard' => '新增至剪貼簿',
			'general.notSet' => '未設定',
			'general.agree' => '同意',
			'general.decline' => '拒絕',
			'general.unknown' => '不明',
			'general.hidden' => '隱藏',
			'general.timeout' => '超時',
			'general.clipboardExportSuccessMsg' => '已匯出至剪貼簿',
			'general.showMore' => '顯示更多',
			'general.showLess' => '顯示較少',
			'general.openAppSettings' => '開啟應用程式設定',
			'general.grantPermission' => '授予權限',
			'general.underDevelopment' => '功能開發中',
			'general.confirm' => '確認',
			'general.close' => '關閉',
			'general.cancel' => '取消',
			'general.clipboardEmpty' => '剪貼簿為空',
			'general.clipboardReadFailed' => '讀取剪貼簿失敗',
			'general.moreOptions' => '更多選項',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: '繼續即表示您同意合約 '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => '開始',
			'home.pageTitle' => '首頁',
			'home.emptyProfilesMsg' => '首先新增訂閱設定檔',
			'home.noActiveProfileMsg' => '選擇設定檔',
			'home.routingMode.global' => '全域代理',
			'home.routingMode.smart' => '智慧分流',
			'home.failedToSwitchMode' => ({required Object error}) => '切換模式失敗：${error}',
			'home.connectionFailedTitle' => '連線失敗',
			'home.coreMissingTitle' => '找不到核心程式庫',
			'home.coreMissingMsg' => '應用程式未能載入網路核心程式庫，無法建立連線。請重新安裝應用程式，或確認核心程式庫檔案與主程式在同一目錄下。',
			'home.degradedTitle' => '已連線，但無法存取網路',
			'home.degradedMsg' => '通道已建立，但資料送不出去。可能是節點已失效——試試換一個節點，或者中斷連線。',
			'home.degradedRetry' => '重新檢測',
			'home.egressIp.label' => '出口 IP',
			'home.egressIp.notConnected' => '連線後顯示出口 IP',
			'home.egressIp.tapToCheck' => '點擊檢測出口 IP',
			'home.egressIp.checking' => '正在檢測…',
			'home.egressIp.failedRetry' => '檢測失敗，點擊重試',
			'home.emptyProfilesHint' => '點擊下方按鈕開始探索',
			'home.noActiveProfileTitle' => '未選擇設定檔',
			'stats.traffic' => '流量',
			'stats.trafficLive' => '即時流量',
			'stats.trafficTotal' => '總流量',
			'stats.uplink' => '上行',
			'stats.downlink' => '下行',
			'stats.connection' => '連線',
			'stats.speed' => '速度',
			'stats.totalTransferred' => '總傳輸量',
			'stats.trafficUsage' => '流量使用',
			'stats.liveSpeed' => '即時速度',
			'stats.sessionTraffic' => '本次流量',
			'stats.downloadSpeed' => '下載速度',
			'profile.overviewPageTitle' => '設定檔',
			'profile.detailsPageTitle' => '設定檔',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => '活動設定檔名稱：“${name}”。',
			'profile.activeProfileBtnSemanticLabel' => '查看所有設定檔',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => '選擇“${name}”作為活動設定檔。',
			'profile.subscription.traffic' => '流量',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => '更新於 ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '剩餘 ${duration} 天',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '已使用 ${consumed} 流量，總共 ${total} 流量。',
			'profile.subscription.expired' => '已到期',
			'profile.subscription.noTraffic' => '超過配額',
			'profile.subscription.upload' => '上傳',
			'profile.subscription.download' => '下載',
			'profile.subscription.total' => '總流量',
			'profile.subscription.expireDate' => '到期時間',
			'profile.sortBy.lastUpdate' => '最近更新',
			'profile.sortBy.name' => '按字母順序',
			'profile.add.buttonText' => '新的設定檔',
			'profile.add.shortBtnTxt' => '新的設定檔',
			'profile.add.fromClipboard' => '從剪貼簿新增',
			'profile.add.scanQr' => '掃描 QR code',
			'profile.add.qrScanner.permissionDeniedError' => '沒有權限',
			'profile.add.qrScanner.unexpectedError' => '出了點問題',
			'profile.add.qrScanner.torchSemanticLabel' => '手電筒',
			'profile.add.qrScanner.facingSemanticLabel' => '相機朝向',
			'profile.add.qrScanner.permissionRequest' => '授予相機權限已允許掃描 QR code',
			'profile.add.manually' => '手動輸入',
			'profile.add.addWarp' => '添加 WARP',
			'profile.add.addingWarpMsg' => '我們正在註冊 WARP，請稍候。',
			'profile.add.addingProfileMsg' => '新增設定檔',
			'profile.add.failureMsg' => '新增設定檔失敗',
			'profile.add.modalSubtitle' => '選擇新增設定檔的方式',
			'profile.add.manuallyDescription' => '手動輸入伺服器設定',
			'profile.add.warpDescription' => '使用 Cloudflare WARP 免費加速',
			'profile.add.importedNamed' => ({required Object name}) => '已匯入訂閱：${name}',
			'profile.add.clipboardEmpty' => '剪貼簿為空，無法匯入訂閱',
			'profile.add.deepLinkMissingUrl' => '連結中缺少訂閱位址',
			'profile.add.successMsg' => '新增成功',
			'profile.add.nameAutoHint' => '自動識別（選填）',
			'profile.update.buttonTxt' => '更新',
			'profile.update.tooltip' => '更新設定檔',
			'profile.update.updateSubscriptions' => '更新訂閱',
			'profile.update.failureMsg' => '更新設定檔失敗',
			'profile.update.successMsg' => '設定檔更新成功',
			'profile.update.namedFailureMsg' => ({required Object name}) => '無法更新“${name}”',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '“${name}” 更新成功',
			'profile.share.buttonText' => '分享',
			'profile.share.exportToClipboardSuccess' => '匯出到剪貼簿',
			'profile.share.exportSubLinkToClipboard' => '將訂閱連結匯出到剪貼簿',
			'profile.share.subLinkQrCode' => '訂閱連結 QR code',
			'profile.share.exportConfigToClipboard' => '將配置匯出到剪貼簿',
			'profile.share.exportConfigToClipboardSuccess' => '配置已複製到剪貼簿',
			'profile.share.shareLink' => '分享連結',
			'profile.share.subscriptionLinkCopied' => '訂閱連結已複製',
			'profile.share.configCopied' => '設定已複製',
			'profile.share.copyFailed' => '複製失敗',
			'profile.edit.buttonTxt' => '編輯',
			'profile.edit.selectActiveTxt' => '選擇活動設定檔',
			'profile.delete.buttonTxt' => '刪除',
			'profile.delete.confirmationMsg' => '要永久刪除設定檔嗎？',
			'profile.delete.successMsg' => '設定檔刪除成功',
			'profile.delete.confirmTitle' => '刪除設定檔',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => '確定要刪除「${name}」嗎？此操作無法復原。',
			'profile.save.buttonText' => '儲存',
			'profile.save.successMsg' => '設定檔儲存成功',
			'profile.save.failureMsg' => '設定檔儲存失敗',
			'profile.detailsForm.nameLabel' => '名稱',
			'profile.detailsForm.nameHint' => '設定檔名稱',
			'profile.detailsForm.urlLabel' => '網址',
			'profile.detailsForm.urlHint' => '完整配置網址',
			'profile.detailsForm.emptyNameMsg' => '名稱為必填項',
			'profile.detailsForm.invalidUrlMsg' => '無效的網址',
			'profile.detailsForm.lastUpdate' => '最後更新',
			'profile.detailsForm.updateInterval' => '自動更新',
			'profile.detailsForm.updateIntervalDialogTitle' => '自動更新間隔（以小時為單位）',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => '關閉',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} 小時',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} 天',
			'profile.actionButtons.add' => '新增',
			'profile.actionButtons.updateAll' => '全部更新',
			'profile.actionButtons.sort' => '排序',
			'profile.actionButtons.copyConfigSuccess' => '設定已複製',
			'profile.actionButtons.editConfig' => '編輯設定',
			'profile.details.basicInfo' => '基本資訊',
			'profile.details.subscriptionStatus' => '訂閱狀態',
			'profile.details.options' => '選項',
			'profile.details.updateNow' => '立即更新',
			'profile.details.updateNowDescription' => '從伺服器取得最新設定',
			'profile.details.expireDate' => '到期日期',
			'profile.details.unlimited' => '無限制',
			'profile.overview.currentlyUsing' => '目前使用中',
			'profile.overview.remainingDays' => ({required Object days}) => '剩餘 ${days} 天',
			'profile.remoteProfile' => '遠端訂閱',
			'profile.defaultLocalName' => '本機匯入',
			'profile.defaultDeepLinkName' => '連結匯入',
			'profile.switchFailedMsg' => '切換設定檔失敗',
			'proxies.pageTitle' => '線路',
			'proxies.emptyProxiesMsg' => '沒有可用的線路',
			'proxies.delayTestTooltip' => '測試延遲',
			'proxies.sortTooltip' => '對線路進行排序',
			'proxies.checkIp' => '檢測 IP 地址',
			'proxies.unknownIp' => '不明的 IP',
			'proxies.sortOptions.unsorted' => '預設',
			'proxies.sortOptions.name' => '按字母排序',
			'proxies.sortOptions.delay' => '按延遲排序',
			'proxies.activeProxySemanticLabel' => '生效中的線路',
			'proxies.delaySemantics.result' => ({required Object delay}) => '延遲： ${delay}ms',
			'proxies.delaySemantics.timeout' => '延遲測試超時',
			'proxies.delaySemantics.testing' => '正在測試延遲',
			'proxies.delaySemantics.untested' => '延遲： 未測試',
			'proxies.delaySemantics.stale' => ({required Object delay}) => '延遲： ${delay}ms（歷史值）',
			'proxies.ipInfoSemantics.address' => 'IP 地址',
			'proxies.ipInfoSemantics.country' => '國家',
			'proxies.autoSelect' => '自動選擇',
			'proxies.autoSelectDescription' => '自動連線到最快的節點',
			'proxies.sortModalTitle' => '選擇排序方式',
			'proxies.testingDelayInfo' => ({required Object name}) => '正在檢測延遲：${name}',
			'proxies.switchedTo' => ({required Object name}) => '已切換到 ${name}',
			'proxies.switchFailed' => '切換線路失敗，請稍後重試',
			'proxies.testFailed' => '測速失敗，請稍後重試',
			'proxies.groupsLoading' => '線路資訊載入中，請稍候再試',
			'proxies.connectBeforeSwitch' => '請先連線再切換線路',
			'proxies.startDelayTestForGroups' => ({required Object count}) => '已開始檢測 ${count} 條線路的延遲',
			'proxies.delayTestBtn' => '延遲',
			'proxies.delayTimeout' => '逾時',
			'proxies.connectBeforeTest' => '請連線後再測速',
			'proxies.lineCount' => ({required Object count}) => '${count} 條線路',
			'proxies.manualSelect' => '手動選擇',
			'proxies.autoTest' => '自動測速',
			'logs.pageTitle' => '記錄檔',
			'logs.filterHint' => '篩選',
			'logs.allLevelsFilter' => '全部',
			'logs.shareCoreLogs' => '分享核心記錄檔',
			'logs.shareAppLogs' => '分享應用程式記錄檔',
			'logs.pauseTooltip' => '暫停',
			'logs.resumeTooltip' => '恢復',
			'logs.clearTooltip' => '清除',
			'logs.logsCleared' => '日誌已清空',
			'logs.logsCopied' => '日誌已複製',
			'logs.logsUnderDevelopment' => '日誌功能開發中',
			'logs.noLogsWhenDisconnected' => '未連線，無日誌',
			'logs.loadFailed' => '日誌讀取失敗',
			'logs.empty' => '暫無日誌',
			'logs.clearFailed' => '清除日誌失敗',
			'settings.pageTitle' => '設定',
			'settings.requiresRestartMsg' => '若要使其生效，請重新啟動應用程式',
			'settings.experimental' => '實驗性的',
			'settings.experimentalMsg' => '帶有實驗標誌的功能仍在開發中，可能會導致問題。',
			'settings.exportOptions' => '匯出選項至剪貼簿',
			'settings.exportAllOptions' => '匯出選項至剪貼簿(用於偵錯) ',
			'settings.importOptions' => '從剪貼簿匯入選項',
			'settings.importOptionsMsg' => '這將使用提供的值複寫所有配置選項。您確定嗎？',
			'settings.backup.importConfirmTitle' => '匯入備份',
			'settings.backup.importConfirmMsg' => '這會用備份中的訂閱取代目前的訂閱，並套用備份中的設定。匯入前會先儲存目前資料的快照，匯入失敗時自動還原。',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '本機有 ${count} 個訂閱不在備份中，匯入後將被移除。',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '已匯入 ${profiles} 個訂閱、${settings} 項設定。',
			'settings.backup.reportDropped' => ({required Object count}) => '備份中有 ${count} 個訂閱因資料無效而被略過。',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '有 ${count} 項設定被略過，保留了目前的值。',
			'settings.backup.reportWarpOff' => '匯入時已關閉 WARP，請在本機重新啟用。',
			'settings.backup.reportBackfill' => ({required Object count}) => '有 ${count} 個訂閱將在背景下載。',
			'settings.backup.errInvalidFile' => '這不是有效的 ClashMiao 備份檔案。',
			'settings.backup.errUnsupportedVersion' => '不支援這種備份格式。',
			'settings.backup.errNewerSchema' => '此備份由較新版本的應用程式建立，請先升級應用程式。',
			'settings.backup.errNoUsableProfiles' => '此備份中沒有可以匯入的訂閱。',
			'settings.backup.errSnapshotFailed' => '無法儲存目前資料的快照，因此沒有做任何變更。',
			'settings.backup.errUnresolvedPrevious' => '上一次匯入被中斷，尚未能復原。沒有做任何變更，請重新啟動應用程式後再試。',
			'settings.backup.errRolledBack' => '匯入失敗，已還原到匯入之前的資料。',
			'settings.backup.errNotRolledBack' => ({required Object path}) => '匯入失敗，且自動還原沒有完成。請重新啟動應用程式讓它重試。快照儲存在 ${path}。',
			'settings.backup.errFailed' => '匯入失敗。',
			'settings.backup.errBusy' => '已有另一個匯入正在進行，請等它結束後再試。',
			'settings.backup.recoveryFailedTitle' => '自動還原沒有完成',
			'settings.backup.recoveryFailedMsg' => '上一次備份匯入被中斷，應用程式未能把資料還原到匯入之前的狀態，部分資料可能只匯入了一半。現在重試自動還原。',
			'settings.backup.recoveryUnrecoverableTitle' => '無法復原被中斷的匯入',
			'settings.backup.recoveryUnrecoverableMsg' => '上一次備份匯入被中斷，但它的快照遺失或無法讀取，因此無法復原。請檢查你的訂閱和設定。',
			'settings.backup.recoveryRetry' => '重試',
			'settings.backup.recoveryClose' => '關閉',
			'settings.backup.recoveryRetried' => '已把資料還原到被中斷的匯入之前。',
			'settings.backup.exportAction' => '匯出備份',
			'settings.backup.importAction' => '匯入備份',
			'settings.backup.exportFailed' => '匯出失敗',
			'settings.backup.shareText' => 'ClashMiao 備份',
			'settings.general.sectionTitle' => '一般',
			'settings.general.locale' => '語言',
			'settings.general.region' => '地區',
			'settings.general.regionMsg' => '幫助設定預設選項以繞過國內地址',
			'settings.general.regions.ir' => '伊朗 (ir)',
			'settings.general.regions.cn' => '中國 (cn)',
			'settings.general.regions.ru' => '俄羅斯 (ru)',
			'settings.general.regions.af' => '阿富汗 (af)',
			'settings.general.regions.id' => '印尼 (id)',
			'settings.general.regions.other' => '其他',
			'settings.general.themeMode' => '主題模式',
			'settings.general.themeModes.system' => '跟隨系統顏色',
			'settings.general.themeModes.dark' => '深色',
			'settings.general.themeModes.light' => '淺色',
			'settings.general.themeModes.black' => '黑色',
			'settings.general.enableAnalytics' => '啟用分析',
			'settings.general.enableAnalyticsMsg' => '授予收集分析並傳送崩潰報告以改進應用程式的權限',
			'settings.general.autoStart' => '隨系統啟動',
			'settings.general.silentStart' => '啟動最小化',
			'settings.general.openWorkingDir' => '開啟工作目錄',
			'settings.general.ignoreBatteryOptimizations' => '停用電池最佳化',
			'settings.general.ignoreBatteryOptimizationsMsg' => '消除限制以獲得最佳 VPN 效能',
			'settings.general.dynamicNotification' => '在通知中顯示速度',
			'settings.general.hapticFeedback' => '觸覺回饋',
			'settings.general.autoIpCheck' => '自動檢查連線的 IP',
			'settings.general.batteryOptimizationStatus.exempted' => '已豁免',
			'settings.general.batteryOptimizationStatus.notExempted' => '未豁免',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => '進階設定',
			'settings.advanced.debugMode' => '偵錯模式',
			'settings.advanced.debugModeMsg' => '重新啟動應用程式以套用此變更',
			'settings.advanced.memoryLimit' => '記憶體限制',
			'settings.advanced.memoryLimitMsg' => '如果您遇到記憶體不足錯誤或頻繁應用程式崩潰，請啟用',
			'settings.advanced.resetTunnel' => '重置 VPN 設定檔',
			'settings.advanced.resetTunnelSuccess' => 'VPN 設定檔已重設',
			'settings.network.perAppProxyPageTitle' => '應用程式線路模式',
			'settings.network.perAppProxyModes.off' => '全部',
			'settings.network.perAppProxyModes.offMsg' => '透過線路代理所有應用程式',
			'settings.network.perAppProxyModes.include' => '代理',
			'settings.network.perAppProxyModes.includeMsg' => '僅透過線路代理選定的應用程式',
			'settings.network.perAppProxyModes.exclude' => '略過',
			'settings.network.perAppProxyModes.excludeMsg' => '不透過線路代理選定的應用程式',
			'settings.network.showSystemApps' => '顯示系統應用程式',
			'settings.network.hideSystemApps' => '隱藏系統應用程式',
			'settings.network.clearSelection' => '清空選項',
			'settings.network.perAppProxyLoadFailedMsg' => '載入應用程式清單失敗',
			'settings.network.perAppProxyRetry' => '重試',
			'settings.network.perAppProxyEmptyMsg' => '找不到結果',
			'settings.network.perAppProxyAndroidOnlyMsg' => '分應用線路模式僅支援 Android',
			'settings.geoAssets.pageTitle' => '路由資源文件',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => '版本${version}',
			'settings.geoAssets.fileMissing' => '檔案遺失',
			'settings.geoAssets.update' => '更新',
			'settings.geoAssets.download' => '下載',
			'settings.geoAssets.failureMsg' => '更新資源文件失敗',
			'settings.geoAssets.successMsg' => '已成功更新資源文件',
			'settings.geoAssets.addRecommended' => '新增推薦的資源文件',
			'settings.geoAssets.missingGeoAssetsMsg' => '所選路由資源的檔案遺失。下載它們或選擇現有的。',
			'settings.systemProxyEnabled' => '系統代理已啟用',
			'settings.systemProxyDisabled' => '系統代理已停用（重新連線後生效）',
			'settings.adminPrivilegesRequired' => 'macOS 上需要管理員權限',
			'settings.portChangeNotice' => '連接埠變更需要重新連線才會生效',
			'settings.groups.general' => '一般',
			'settings.groups.connection' => '連線',
			'settings.groups.privacy' => '隱私',
			'settings.importOptionsInvalid' => '剪貼簿內容不是有效的設定 JSON',
			'settings.importOptionsNothing' => '未識別到可匯入的設定項',
			'settings.importOptionsDone' => ({required Object count}) => '已匯入 ${count} 項設定',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '已匯入 ${applied} 項設定，${skipped} 項因格式無效被略過',
			'about.pageTitle' => '關於',
			'about.version' => '版本',
			'about.sourceCode' => '原始碼',
			'about.telegramChannel' => 'Telegram 頻道',
			'about.checkForUpdate' => '檢查更新',
			'about.privacyPolicy' => '隱私政策',
			'about.termsAndConditions' => '條款與條件',
			'about.appDescription' => '基於 sing-box 核心的跨平台代理用戶端',
			'about.openSourceLicenses' => '開放原始碼授權',
			'appUpdate.notAvailableMsg' => '已經是最新版本',
			'appUpdate.dialogTitle' => '有可用更新',
			'appUpdate.updateMsg' => '${_root.general.appTitle} 的更新版本現已推出。您想立即更新嗎？',
			'appUpdate.currentVersionLbl' => '目前版本',
			'appUpdate.newVersionLbl' => '新版本',
			'appUpdate.updateNowBtnTxt' => '立即更新',
			'appUpdate.laterBtnTxt' => '稍後再說',
			'appUpdate.ignoreBtnTxt' => '忽略',
			'appUpdate.checkFailedMsg' => '檢查更新失敗，請檢查網路後再試',
			'tray.dashboard' => '儀表板',
			'tray.quit' => '退出',
			'tray.open' => '開啟',
			'tray.status.connect' => '連線',
			'tray.status.connecting' => '連線中',
			'tray.status.disconnect' => '中斷連線',
			'tray.status.disconnecting' => '中斷連線中',
			'tray.hide' => '隱藏',
			'tray.proxyModeMenu' => '代理模式',
			'failure.unexpected' => '意外錯誤',
			'failure.clash.unexpected' => '意外錯誤',
			'failure.clash.core' => ({required Object reason}) => 'Clash 錯誤 ${reason}',
			'failure.singbox.unexpected' => '意外服務錯誤',
			'failure.singbox.serviceNotRunning' => '服務未執行',
			'failure.singbox.missingPrivilege' => '缺少權限',
			'failure.singbox.missingPrivilegeMsg' => 'VPN 模式需要管理員權限。以管理員身分重新啟動應用程式或變更服務模式。',
			'failure.singbox.missingGeoAssets' => '缺少 GEO 資源文件',
			'failure.singbox.missingGeoAssetsMsg' => 'GEO 資源文件缺失。請考慮更改活動資源文件或在設定中下載選定的資源文件。',
			'failure.singbox.invalidConfigOptions' => '配置選項無效',
			'failure.singbox.invalidConfig' => '無效配置',
			'failure.singbox.create' => '服務建立錯誤',
			'failure.singbox.start' => '服務啟動錯誤',
			'failure.singbox.coreLibraryMissing' => '核心程式庫未安裝',
			'failure.singbox.startTimeout' => '服務啟動逾時',
			'failure.singbox.kernelUnresponsive' => '核心無回應，請重試或重新啟動應用程式',
			'failure.singbox.kernelExited' => '核心意外結束',
			'failure.connectivity.unexpected' => '意外失敗',
			'failure.connectivity.missingVpnPermission' => '缺少 VPN 權限',
			'failure.connectivity.missingNotificationPermission' => '缺少通知權限',
			'failure.connectivity.core' => '核心錯誤',
			'failure.connectivity.networkUnavailable' => '網路無法使用',
			'failure.connectivity.nativeUnresponsive' => '與背景服務失去連線，請重試',
			'failure.profiles.unexpected' => '意外錯誤',
			'failure.profiles.notFound' => '未找到設定檔',
			'failure.profiles.invalidConfig' => '無效配置',
			'failure.profiles.invalidUrl' => '無效網址',
			'failure.profiles.noActive' => '沒有啟用的訂閱',
			'failure.profiles.readOnlyUpgrade' => '請升級 App 後再修改訂閱',
			'failure.connection.unexpected' => '意外連線錯誤',
			'failure.connection.timeout' => '連線超時',
			'failure.connection.badResponse' => '錯誤反應',
			'failure.connection.connectionError' => '連線錯誤',
			'failure.connection.badCertificate' => '無效證書',
			'failure.geoAssets.unexpected' => '意外錯誤',
			'failure.geoAssets.notUpdate' => '暫無可用更新',
			'failure.geoAssets.activeNotFound' => '未找到活動 GEO 資源文件',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}：${reason}',
			'connection.tapToConnect' => '點擊以連線',
			'connection.connecting' => '連線中',
			'connection.disconnecting' => '中斷連線中',
			'connection.connected' => '已連線',
			'connection.reconnect' => '重新連線',
			'connection.connectAnyWay' => '仍然連線',
			'connection.experimentalNotice' => '實驗性功能提醒',
			'connection.experimentalNoticeMsg' => '目前設定啟用了實驗性進階選項（例如 TLS 混淆分片、封包填充、多工、WARP 中轉，或允許區域網路存取等），可能不穩定，連線品質或成功率會受影響。',
			'connection.disableExperimentalNotice' => '不再提示',
			'connection.reconnectMsg' => '重新連線以使變更生效',
			'connection.staleSystemProxyCleaned' => '已清理上次異常結束殘留的系統代理設定',
			'config.resetBtn' => '重置選項',
			'config.serviceMode' => '服務模式',
			'config.quickSettings' => '快速設定',
			'config.setupWarp' => '配置 WARP',
			'config.allOptions' => '全部配置選項',
			'config.serviceModes.proxy' => '僅線路',
			'config.serviceModes.systemProxy' => '系統線路',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'VPN 服務',
			'config.shortServiceModes.proxy' => '僅線路',
			'config.shortServiceModes.systemProxy' => '系統線路',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'VPN 服務',
			'config.section.route' => '路由選項',
			'config.section.dns' => 'DNS 選項',
			'config.section.inbound' => '入站選項',
			'config.section.mux' => '復用器',
			'config.section.outbound' => '出站選項',
			'config.section.tlsTricks' => 'TLS 特性',
			'config.section.warp' => 'WARP 選項',
			'config.section.misc' => '其他選項',
			'config.warpConsent.title' => 'Cloudflare WARP 授權條款',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP 是一個免費的 WireGuard VPN 提供商。啟用此選項即表示您同意 Cloudflare WARP 的 '), tos('服務條款'), const TextSpan(text: ' 和 '), privacy('隱私權政策'), ]), 
			'config.generateWarpConfig' => '生成 WARP 配置檔案',
			'config.missingWarpConfig' => 'WARP 配置檔案缺失',
			'config.warpConfigGenerated' => 'WARP 配置檔案已生成',
			'config.pageTitle' => '配置選項',
			'config.logLevel' => '紀錄等級',
			'config.resolveDestination' => '解析目標地址',
			'config.ipv6Mode' => 'IPv6 路由',
			'config.ipv6Modes.disable' => '停用',
			'config.ipv6Modes.enable' => '啟用',
			'config.ipv6Modes.prefer' => '首選',
			'config.ipv6Modes.only' => '僅限',
			'config.remoteDnsAddress' => '遠端 DNS',
			'config.remoteDnsDomainStrategy' => '遠端 DNS 網域策略',
			'config.directDnsAddress' => '直連 DNS',
			'config.directDnsDomainStrategy' => '直連 DNS 網域策略',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => '未套用：IPv6 路由已停用，但「${field}」為僅 IPv6，會導致網域無法解析。請先啟用 IPv6 路由，或換一個策略。',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => '未套用：IPv6 路由為僅限 IPv6，但「${field}」為僅 IPv4，會導致網域無法解析。請先調整其中一項。',
			'config.dnsStrategyReset' => ({required Object field}) => '「${field}」與 IPv6 路由設定衝突（會導致網域無法解析），已重設為自動。',
			'config.mixedPort' => '混合連接埠',
			'config.tproxyPort' => '透明線路埠',
			'config.localDnsPort' => '本機 DNS 連接埠',
			'config.allowConnectionFromLan' => '允許區域網路連線',
			'config.tunImplementation' => 'TUN 實現',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => '連線測試網址',
			'config.urlTestInterval' => '網址測試間隔',
			'config.enableClashApi' => '啟用 Clash API',
			'config.clashApiPort' => 'Clash API 連接埠',
			'config.enableTun' => '啟用 TUN',
			'config.setSystemProxy' => '設定系統線路',
			'config.enableDnsRouting' => '啟用 DNS 路由',
			'config.enableFakeDns' => '啟用 Fake DNS',
			'config.bypassLan' => '繞過區域網路',
			'config.strictRoute' => '嚴格路由',
			'config.enableTlsFragment' => '啟用 TLS 分段',
			'config.tlsFragmentSize' => 'TLS 分段大小',
			'config.tlsFragmentSleep' => 'TLS 分段睡眠',
			'config.enableTlsMixedSniCase' => '啟用 TLS 混合 SNI 情況',
			'config.enableTlsPadding' => '啟用 TLS 填充',
			'config.tlsPaddingSize' => 'TLS 填充',
			'config.enableMux' => '啟用復用器',
			'config.muxProtocol' => '復用器控制',
			'config.muxMaxStreams' => '最大並發數',
			'config.enableWarp' => '啟用 WARP',
			'config.setUpWarp' => '設定 WARP',
			'config.warpNotConfigured' => '未設定',
			'config.warpDetourMode' => '鏈式線路',
			'config.warpDetourModes.proxyOverWarp' => '透過 WARP 連線線路',
			'config.warpDetourModes.warpOverProxy' => '透過線路連線 WARP',
			'config.warpDetourModes.inbound' => '透過線路繞過 WARP',
			'config.warpDetourModes.outbound' => '透過 WARP 繞過線路',
			'config.warpLicenseKey' => '授權金鑰',
			'config.warpCleanIp' => '清理 IP',
			'config.warpPort' => '連接埠',
			'config.warpNoise' => '噪音計數',
			'config.warpNoiseDelay' => '噪音延遲',
			'config.quickSettingsSubtitle' => '自訂您的連線體驗',
			'config.allAdvancedOptions' => '所有進階選項',
			'config.blockAds' => '封鎖廣告',
			'config.warpNoiseSize' => '雜訊大小',
			'config.warpNoiseMode' => '雜訊模式',
			'config.desktopProxyScopeNotice' => '桌面端只有遵循系統代理設定的程式會走通道。不遵循的軟體（部分遊戲、命令列工具、自帶代理設定的用戶端）會直連，暴露你的真實 IP。',
			'config.serviceModeIosVpnOnly' => 'iOS 僅支援 VPN 模式',
			'config.warpGenerating' => '正在產生 WARP 設定…',
			'config.warpConfigFailed' => 'WARP 設定產生失敗，請稍後再試',
			'config.portRangeError' => '連接埠範圍 1024-65535',
			'config.dnsEmptyError' => 'DNS 位址不能為空',
			'config.rangeFormatError' => '請輸入數字或範圍，例如 10-30',
			'config.urlSchemeError' => 'URL 必須以 http:// 或 https:// 開頭',
			'config.manageRuleAssets' => '規則庫管理',
			_ => null,
		};
	}
}
