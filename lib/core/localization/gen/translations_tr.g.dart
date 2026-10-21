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
class TranslationsTr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsTr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.tr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <tr>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsTr _root = this; // ignore: unused_field

	@override 
	TranslationsTr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsTr(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$tr general = Translations$general$tr._(_root);
	@override late final Translations$intro$tr intro = Translations$intro$tr._(_root);
	@override late final Translations$home$tr home = Translations$home$tr._(_root);
	@override late final Translations$stats$tr stats = Translations$stats$tr._(_root);
	@override late final Translations$profile$tr profile = Translations$profile$tr._(_root);
	@override late final Translations$proxies$tr proxies = Translations$proxies$tr._(_root);
	@override late final Translations$logs$tr logs = Translations$logs$tr._(_root);
	@override late final Translations$settings$tr settings = Translations$settings$tr._(_root);
	@override late final Translations$about$tr about = Translations$about$tr._(_root);
	@override late final Translations$appUpdate$tr appUpdate = Translations$appUpdate$tr._(_root);
	@override late final Translations$tray$tr tray = Translations$tray$tr._(_root);
	@override late final Translations$failure$tr failure = Translations$failure$tr._(_root);
	@override late final Translations$connection$tr connection = Translations$connection$tr._(_root);
	@override late final Translations$config$tr config = Translations$config$tr._(_root);
}

// Path: general
class Translations$general$tr extends Translations$general$en {
	Translations$general$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'Sıfırla';
	@override late final Translations$general$toggle$tr toggle = Translations$general$toggle$tr._(_root);
	@override late final Translations$general$state$tr state = Translations$general$state$tr._(_root);
	@override String get sort => 'Sırala';
	@override String get sortBy => 'Sırala';
	@override String get addToClipboard => 'Panoya ekle';
	@override String get notSet => 'Ayarlanmadı';
	@override String get agree => 'Kabul etmek';
	@override String get decline => 'Reddetmek';
	@override String get unknown => 'Bilinmeyen';
	@override String get hidden => 'Gizlenmiş';
	@override String get timeout => 'Zaman aşımı';
	@override String get showMore => 'Daha fazla göster';
	@override String get showLess => 'Daha az göster';
	@override String get grantPermission => 'İzin Ver';
	@override String get clipboardExportSuccessMsg => 'Panoya kopyalandı';
	@override String get openAppSettings => 'Uygulama Ayarlarını Aç';
	@override String get underDevelopment => 'Geliştirme Aşamasında';
	@override String get confirm => 'Onayla';
	@override String get close => 'Kapat';
	@override String get cancel => 'İptal';
	@override String get clipboardEmpty => 'Pano boş';
	@override String get clipboardReadFailed => 'Pano okunamadı';
	@override String get moreOptions => 'Diğer seçenekler';
}

// Path: intro
class Translations$intro$tr extends Translations$intro$en {
	Translations$intro$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'devam ederek '),
		tap(_root.about.termsAndConditions),
		const TextSpan(text: ' kabul etmiş olursunuz'),
	]);
	@override String get start => 'Başla';
}

// Path: home
class Translations$home$tr extends Translations$home$en {
	Translations$home$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Ana Sayfa';
	@override String get emptyProfilesMsg => 'Aboneliği profili ekleyerek başlayın';
	@override String get noActiveProfileMsg => 'Profil seçin';
	@override late final Translations$home$routingMode$tr routingMode = Translations$home$routingMode$tr._(_root);
	@override String failedToSwitchMode({required Object error}) => 'Mod değiştirilemedi: ${error}';
	@override String get connectionFailedTitle => 'Bağlantı Başarısız';
	@override String get coreMissingTitle => 'Çekirdek Kitaplığı Bulunamadı';
	@override String get coreMissingMsg => 'Uygulama ağ çekirdeğini yükleyemedi. Bağlantı kullanılamıyor. Uygulamayı yeniden kurun ya da çekirdek kitaplık dosyasının çalıştırılabilir dosyanın yanında olduğundan emin olun.';
	@override String get degradedTitle => 'Bağlandı, ancak internet erişimi yok';
	@override String get degradedMsg => 'Tünel açık ancak trafik geçmiyor. Sunucu çalışmıyor olabilir — başka bir sunucu deneyin veya bağlantıyı kesin.';
	@override String get degradedRetry => 'Yeniden Denetle';
	@override late final Translations$home$egressIp$tr egressIp = Translations$home$egressIp$tr._(_root);
	@override String get emptyProfilesHint => 'Başlamak için aşağıdaki düğmeye dokunun';
	@override String get noActiveProfileTitle => 'Profil seçilmedi';
}

// Path: stats
class Translations$stats$tr extends Translations$stats$en {
	Translations$stats$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get trafficLive => 'Canlı Trafik';
	@override String get trafficTotal => 'Toplam Trafik';
	@override String get uplink => 'Çıkış Yolu';
	@override String get downlink => 'Giriş Yolu';
	@override String get traffic => 'Trafik';
	@override String get trafficUsage => 'Trafik Kullanımı';
	@override String get liveSpeed => 'Anlık Hız';
	@override String get connection => 'Bağlantı';
	@override String get speed => 'Hız';
	@override String get totalTransferred => 'Toplam Aktarılan';
	@override String get sessionTraffic => 'Bu oturumun trafiği';
	@override String get downloadSpeed => 'İndirme hızı';
}

// Path: profile
class Translations$profile$tr extends Translations$profile$en {
	Translations$profile$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'Profiller';
	@override String get detailsPageTitle => 'Profil';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'Aktif profil adı: "${name}".';
	@override String get activeProfileBtnSemanticLabel => 'Tüm profilleri görüntüleyin';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Aktif profil olarak "${name}" seçeneğini seçin.';
	@override late final Translations$profile$subscription$tr subscription = Translations$profile$subscription$tr._(_root);
	@override late final Translations$profile$sortBy$tr sortBy = Translations$profile$sortBy$tr._(_root);
	@override late final Translations$profile$add$tr add = Translations$profile$add$tr._(_root);
	@override late final Translations$profile$update$tr update = Translations$profile$update$tr._(_root);
	@override late final Translations$profile$share$tr share = Translations$profile$share$tr._(_root);
	@override late final Translations$profile$edit$tr edit = Translations$profile$edit$tr._(_root);
	@override late final Translations$profile$delete$tr delete = Translations$profile$delete$tr._(_root);
	@override late final Translations$profile$save$tr save = Translations$profile$save$tr._(_root);
	@override late final Translations$profile$detailsForm$tr detailsForm = Translations$profile$detailsForm$tr._(_root);
	@override late final Translations$profile$actionButtons$tr actionButtons = Translations$profile$actionButtons$tr._(_root);
	@override late final Translations$profile$details$tr details = Translations$profile$details$tr._(_root);
	@override late final Translations$profile$overview$tr overview = Translations$profile$overview$tr._(_root);
	@override String get remoteProfile => 'Uzak Profil';
	@override String get defaultLocalName => 'Yerel içe aktarma';
	@override String get defaultDeepLinkName => 'Bağlantıdan içe aktarma';
	@override String get switchFailedMsg => 'Profil değiştirilemedi';
}

// Path: proxies
class Translations$proxies$tr extends Translations$proxies$en {
	Translations$proxies$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Proxyler';
	@override String get emptyProxiesMsg => 'Kullanılabilir proxy yok';
	@override String get delayTestTooltip => 'Test Gecikmesi';
	@override String get sortTooltip => 'Proxy\'leri Sırala';
	@override late final Translations$proxies$sortOptions$tr sortOptions = Translations$proxies$sortOptions$tr._(_root);
	@override String get checkIp => 'IP\'yi Denetle';
	@override String get unknownIp => 'Bilinmeyen IP';
	@override String get autoSelect => 'Otomatik Seçim';
	@override String get autoSelectDescription => 'En hızlı sunucuya otomatik bağlan';
	@override String get sortModalTitle => 'Sıralama yöntemini seçin';
	@override String get activeProxySemanticLabel => 'Etkin Hat';
	@override late final Translations$proxies$delaySemantics$tr delaySemantics = Translations$proxies$delaySemantics$tr._(_root);
	@override late final Translations$proxies$ipInfoSemantics$tr ipInfoSemantics = Translations$proxies$ipInfoSemantics$tr._(_root);
	@override String testingDelayInfo({required Object name}) => 'Gecikme test ediliyor: ${name}';
	@override String switchedTo({required Object name}) => '${name} olarak değiştirildi';
	@override String get switchFailed => 'Sunucu değiştirilemedi. Lütfen tekrar deneyin.';
	@override String get testFailed => 'Gecikme testi başarısız oldu. Lütfen tekrar deneyin.';
	@override String get groupsLoading => 'Sunucu listesi hâlâ yükleniyor. Lütfen birazdan tekrar deneyin.';
	@override String get connectBeforeSwitch => 'Hat değiştirmeden önce bağlanın';
	@override String startDelayTestForGroups({required Object count}) => '${count} hat için gecikme testi başlatıldı';
	@override String get delayTestBtn => 'Gecikme';
	@override String get delayTimeout => 'Zaman aşımı';
	@override String get connectBeforeTest => 'Gecikmeyi test etmek için önce bağlanın';
	@override String lineCount({required Object count}) => '${count} hat';
	@override String get manualSelect => 'Elle Seçim';
	@override String get autoTest => 'Otomatik Test';
}

// Path: logs
class Translations$logs$tr extends Translations$logs$en {
	Translations$logs$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Log';
	@override String get filterHint => 'Filtre';
	@override String get allLevelsFilter => 'Tüm';
	@override String get shareCoreLogs => 'Çekirdek Loglarını Paylaş';
	@override String get shareAppLogs => 'Uygulama Loglarını paylaş';
	@override String get pauseTooltip => 'Duraklat';
	@override String get resumeTooltip => 'Devam et';
	@override String get clearTooltip => 'Temizle';
	@override String get logsCleared => 'Günlükler temizlendi';
	@override String get logsCopied => 'Günlükler kopyalandı';
	@override String get logsUnderDevelopment => 'Günlük özelliği geliştirme aşamasında';
	@override String get noLogsWhenDisconnected => 'Bağlı değil, günlük yok';
	@override String get loadFailed => 'Günlükler yüklenemedi';
	@override String get empty => 'Henüz günlük yok';
	@override String get clearFailed => 'Günlükler temizlenemedi';
}

// Path: settings
class Translations$settings$tr extends Translations$settings$en {
	Translations$settings$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Ayarlar';
	@override String get requiresRestartMsg => 'Bunun etkili olması için uygulamayı yeniden başlatın';
	@override String get experimental => 'Deneysel';
	@override String get experimentalMsg => 'Deneysel işaretli özellikler hâlâ geliştirilme aşamasındadır ve sorunlara neden olabilir.';
	@override late final Translations$settings$general$tr general = Translations$settings$general$tr._(_root);
	@override late final Translations$settings$advanced$tr advanced = Translations$settings$advanced$tr._(_root);
	@override late final Translations$settings$network$tr network = Translations$settings$network$tr._(_root);
	@override late final Translations$settings$geoAssets$tr geoAssets = Translations$settings$geoAssets$tr._(_root);
	@override String get exportOptions => 'Anonim Seçenekleri Panoya Kopyala';
	@override String get exportAllOptions => 'Tüm Seçenekleri Panoya Kopyala';
	@override String get importOptions => 'Seçenekleri Panodan İçe Aktar';
	@override String get importOptionsMsg => 'Bu işlem tüm yapılandırma seçeneklerini verilen değerlerle değiştirir. Emin misiniz?';
	@override late final Translations$settings$backup$tr backup = Translations$settings$backup$tr._(_root);
	@override String get systemProxyEnabled => 'Sistem proxy’si etkin';
	@override String get systemProxyDisabled => 'Sistem proxy’si devre dışı (uygulamak için yeniden bağlanın)';
	@override String get adminPrivilegesRequired => 'macOS\'ta yönetici ayrıcalıkları gerekir';
	@override String get portChangeNotice => 'Bağlantı noktası değişikliklerinin uygulanması için yeniden bağlanmak gerekir';
	@override late final Translations$settings$groups$tr groups = Translations$settings$groups$tr._(_root);
	@override String get importOptionsInvalid => 'Pano geçerli bir ayar JSON\'u içermiyor';
	@override String get importOptionsNothing => 'İçe aktarılabilir ayar bulunamadı';
	@override String importOptionsDone({required Object count}) => '${count} ayar içe aktarıldı';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '${applied} ayar içe aktarıldı; ${skipped} ayar geçersiz olduğu için atlandı';
}

// Path: about
class Translations$about$tr extends Translations$about$en {
	Translations$about$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Hakkında';
	@override String get version => 'Sürüm';
	@override String get sourceCode => 'Kaynak kodu';
	@override String get telegramChannel => 'Telegram Kanalı';
	@override String get checkForUpdate => 'Güncellemeleri kontrol et';
	@override String get privacyPolicy => 'Gizlilik Politikası';
	@override String get termsAndConditions => 'Şartlar ve koşullar';
	@override String get appDescription => 'sing-box çekirdeğine dayalı çok platformlu proxy istemcisi';
	@override String get openSourceLicenses => 'Açık kaynak lisansları';
}

// Path: appUpdate
class Translations$appUpdate$tr extends Translations$appUpdate$en {
	Translations$appUpdate$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => ' En son sürümü kullanıyorsunuz';
	@override String get dialogTitle => 'Yeni Güncell';
	@override String get updateMsg => '${_root.general.appTitle}\'ın yeni bir sürümü mevcut. Şimdi güncellemek ister misiniz?';
	@override String get currentVersionLbl => 'Şimdiki versiyon';
	@override String get newVersionLbl => 'Yeni versiyon';
	@override String get updateNowBtnTxt => 'Şimdi güncelle';
	@override String get laterBtnTxt => 'Daha sonra';
	@override String get ignoreBtnTxt => 'Görmezden gel';
	@override String get checkFailedMsg => 'Güncellemeler denetlenemedi. Ağınızı kontrol edip tekrar deneyin.';
}

// Path: tray
class Translations$tray$tr extends Translations$tray$en {
	Translations$tray$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'Gösterge Paneli';
	@override String get quit => 'Çıkış yap';
	@override String get open => 'Açık';
	@override late final Translations$tray$status$tr status = Translations$tray$status$tr._(_root);
	@override String get hide => 'Gizle';
	@override String get proxyModeMenu => 'Proxy Modu';
}

// Path: failure
class Translations$failure$tr extends Translations$failure$en {
	Translations$failure$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmeyen hata';
	@override late final Translations$failure$clash$tr clash = Translations$failure$clash$tr._(_root);
	@override late final Translations$failure$singbox$tr singbox = Translations$failure$singbox$tr._(_root);
	@override late final Translations$failure$connectivity$tr connectivity = Translations$failure$connectivity$tr._(_root);
	@override late final Translations$failure$profiles$tr profiles = Translations$failure$profiles$tr._(_root);
	@override late final Translations$failure$connection$tr connection = Translations$failure$connection$tr._(_root);
	@override late final Translations$failure$geoAssets$tr geoAssets = Translations$failure$geoAssets$tr._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$tr extends Translations$connection$en {
	Translations$connection$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'Bağlanmak için dokunun';
	@override String get connecting => 'Bağlanıyor';
	@override String get disconnecting => 'Bağlantı kesiliyor';
	@override String get connected => 'Bağlandı';
	@override String get experimentalNotice => 'Kullanımdaki Deneysel Özellikler';
	@override String get experimentalNoticeMsg => 'Bağlantı kalitesini etkileyebilecek ve beklenmeyen hatalara neden olabilecek bazı deneysel özellikleri etkinleştirdiniz. Bu seçenekleri istediğiniz zaman Yapılandırma seçenekleri sayfasından değiştirebilir veya sıfırlayabilirsiniz.';
	@override String get disableExperimentalNotice => 'Bir daha gösterme';
	@override String get reconnect => 'Yeniden Bağlan';
	@override String get connectAnyWay => 'Yine de bağlan';
	@override String get reconnectMsg => 'Değişiklikleri uygulamak için yeniden bağlanılıyor...';
	@override String get staleSystemProxyCleaned => 'Önceki anormal çıkıştan kalan sistem proxy ayarları temizlendi';
}

// Path: config
class Translations$config$tr extends Translations$config$en {
	Translations$config$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'Ayarları sıfırla';
	@override String get serviceMode => 'Servis modu';
	@override late final Translations$config$serviceModes$tr serviceModes = Translations$config$serviceModes$tr._(_root);
	@override late final Translations$config$section$tr section = Translations$config$section$tr._(_root);
	@override late final Translations$config$warpConsent$tr warpConsent = Translations$config$warpConsent$tr._(_root);
	@override String get pageTitle => 'Yapılandırma Seçenekleri';
	@override String get logLevel => 'Log Seviyesi';
	@override String get resolveDestination => 'Hedefi Çöz';
	@override String get ipv6Mode => 'IPv6 Rotası';
	@override late final Translations$config$ipv6Modes$tr ipv6Modes = Translations$config$ipv6Modes$tr._(_root);
	@override String get remoteDnsAddress => 'Uzak DNS';
	@override String get remoteDnsDomainStrategy => 'Uzak DNS Domain Stratejisi';
	@override String get directDnsAddress => 'Doğrudan DNS';
	@override String get directDnsDomainStrategy => 'Doğrudan DNS Domain Stratejisi';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'Uygulanmadı: IPv6 yönlendirme kapalı ancak "${field}" yalnızca IPv6, bu yüzden hiçbir alan adı çözümlenemez. Önce IPv6 yönlendirmeyi açın veya başka bir strateji seçin.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'Uygulanmadı: IPv6 yönlendirme yalnızca IPv6 ancak "${field}" yalnızca IPv4, bu yüzden hiçbir alan adı çözümlenemez. Önce birini değiştirin.';
	@override String dnsStrategyReset({required Object field}) => '"${field}" IPv6 yönlendirme ayarıyla çakıştı (hiçbir alan adı çözümlenemezdi) ve otomatiğe sıfırlandı.';
	@override String get mixedPort => 'Mixed Port';
	@override String get localDnsPort => 'Yerel DNS Bağlantı Noktası';
	@override String get allowConnectionFromLan => 'Allow Connection from LAN';
	@override String get tunImplementation => 'TUN İmplementasyonu';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'Bağlantı Testi URL\'i';
	@override String get urlTestInterval => 'URL Test Aralığı';
	@override String get enableClashApi => 'Clash API\'yi etkinleştir';
	@override String get clashApiPort => 'Clash API Bağlantı Noktası';
	@override String get enableTun => 'TUN\'u etkinleştir';
	@override String get setSystemProxy => 'Sistem Proxy\'sini Ayarla';
	@override String get enableDnsRouting => 'Enable DNS Routing';
	@override String get enableFakeDns => 'Sahte DNS\'yi Etkinleştir';
	@override String get bypassLan => 'Lan\'ı Atla';
	@override String get strictRoute => 'Kesin Rota';
	@override String get enableTlsFragment => 'Enable TLS Fragment';
	@override String get tlsFragmentSize => 'TLS Fragment Size';
	@override String get tlsFragmentSleep => 'TLS Fragment Sleep';
	@override String get enableTlsMixedSniCase => 'Enable TLS Mixed SNI Case';
	@override String get enableTlsPadding => 'Enable TLS Padding';
	@override String get tlsPaddingSize => 'TLS Padding';
	@override String get enableMux => 'Enable Mux';
	@override String get muxProtocol => 'Mux Protocol';
	@override String get muxMaxStreams => 'Max Concurrent Streams';
	@override String get enableWarp => 'Enable WARP';
	@override String get setUpWarp => 'WARP\'ı ayarla';
	@override String get warpNotConfigured => 'Yapılandırılmadı';
	@override String get warpDetourMode => 'Detour Mode';
	@override late final Translations$config$warpDetourModes$tr warpDetourModes = Translations$config$warpDetourModes$tr._(_root);
	@override String get warpLicenseKey => 'License Key';
	@override String get warpCleanIp => 'Clean IP';
	@override String get warpPort => 'Port';
	@override String get warpNoise => 'Noise';
	@override String get quickSettings => 'Hızlı Ayarlar';
	@override String get quickSettingsSubtitle => 'Bağlantı deneyiminizi özelleştirin';
	@override String get setupWarp => 'WARP Kurulumu';
	@override String get allOptions => 'Tüm Yapılandırma Seçenekleri';
	@override String get allAdvancedOptions => 'Tüm Gelişmiş Seçenekler';
	@override late final Translations$config$shortServiceModes$tr shortServiceModes = Translations$config$shortServiceModes$tr._(_root);
	@override String get generateWarpConfig => 'WARP Yapılandırması Oluştur';
	@override String get missingWarpConfig => 'WARP Yapılandırması Eksik';
	@override String get warpConfigGenerated => 'WARP Yapılandırması Oluşturuldu';
	@override String get blockAds => 'Reklamları Engelle';
	@override String get tproxyPort => 'Şeffaf Hat Bağlantı Noktası';
	@override String get warpNoiseSize => 'Gürültü Boyutu';
	@override String get warpNoiseMode => 'Gürültü Modu';
	@override String get warpNoiseDelay => 'Gürültü Gecikmesi';
	@override String get desktopProxyScopeNotice => 'Masaüstünde yalnızca sistem proxy ayarına uyan uygulamalar tünelden geçer. Buna uymayan yazılımlar (bazı oyunlar, komut satırı araçları, kendi proxy ayarı olan uygulamalar) doğrudan bağlanır ve gerçek IP adresinizi açığa çıkarır.';
	@override String get serviceModeIosVpnOnly => 'iOS yalnızca VPN modunu destekler';
	@override String get warpGenerating => 'WARP yapılandırması oluşturuluyor…';
	@override String get warpConfigFailed => 'WARP yapılandırması oluşturulamadı. Lütfen daha sonra tekrar deneyin.';
	@override String get portRangeError => 'Port 1024 ile 65535 arasında olmalıdır';
	@override String get dnsEmptyError => 'DNS adresi boş olamaz';
	@override String get rangeFormatError => 'Bir sayı veya aralık girin, örn. 10-30';
	@override String get urlSchemeError => 'URL http:// veya https:// ile başlamalıdır';
	@override String get manageRuleAssets => 'Kural setlerini yönet';
}

// Path: general.toggle
class Translations$general$toggle$tr extends Translations$general$toggle$en {
	Translations$general$toggle$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'Etkin';
	@override String get disabled => 'Devre dışı';
}

// Path: general.state
class Translations$general$state$tr extends Translations$general$state$en {
	Translations$general$state$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Devre dışı bırak';
}

// Path: home.routingMode
class Translations$home$routingMode$tr extends Translations$home$routingMode$en {
	Translations$home$routingMode$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get global => 'Genel Proxy';
	@override String get smart => 'Akıllı Yönlendirme';
}

// Path: home.egressIp
class Translations$home$egressIp$tr extends Translations$home$egressIp$en {
	Translations$home$egressIp$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get label => 'Çıkış IP\'si';
	@override String get notConnected => 'Çıkış IP\'sini görmek için bağlanın';
	@override String get tapToCheck => 'Çıkış IP\'sini denetlemek için dokunun';
	@override String get checking => 'Denetleniyor…';
	@override String get failedRetry => 'Denetim başarısız, yeniden denemek için dokunun';
}

// Path: profile.subscription
class Translations$profile$subscription$tr extends Translations$profile$subscription$en {
	Translations$profile$subscription$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Trafik';
	@override String updatedTimeAgo({required Object timeago}) => '${timeago} güncellendi';
	@override String remainingDuration({required Object duration}) => '${duration} Gün Kaldı';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed}/${total} trafik tüketildi';
	@override String get expired => 'Süresi Doldu';
	@override String get noTraffic => 'Kotal Doldu';
	@override String get upload => 'Yükleme';
	@override String get download => 'İndirme';
	@override String get total => 'Toplam Trafik';
	@override String get expireDate => 'Son Kullanma Tarihi';
}

// Path: profile.sortBy
class Translations$profile$sortBy$tr extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'Yakın zamanda güncellendi';
	@override String get name => 'Alfabetik';
}

// Path: profile.add
class Translations$profile$add$tr extends Translations$profile$add$en {
	Translations$profile$add$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Yeni profil';
	@override String get shortBtnTxt => 'Yeni profil';
	@override String get fromClipboard => 'Panodan Ekle';
	@override String get scanQr => 'QR kodunu tarayın';
	@override late final Translations$profile$add$qrScanner$tr qrScanner = Translations$profile$add$qrScanner$tr._(_root);
	@override String get manually => 'Manuel giriş';
	@override String get addingProfileMsg => 'Profil Ekleniyor';
	@override String get failureMsg => 'Profil eklenemedi';
	@override String get modalSubtitle => 'Yapılandırma dosyasını nasıl ekleyeceğinizi seçin';
	@override String get manuallyDescription => 'Sunucu yapılandırmasını elle girin';
	@override String get addWarp => 'WARP Ekle';
	@override String get warpDescription => 'Cloudflare WARP ile ücretsiz hızlandırma';
	@override String get addingWarpMsg => 'WARP kaydedilirken lütfen bekleyin.';
	@override String importedNamed({required Object name}) => 'Abonelik içe aktarıldı: ${name}';
	@override String get clipboardEmpty => 'Pano boş, içe aktarılacak bir şey yok';
	@override String get deepLinkMissingUrl => 'Bağlantıda abonelik adresi yok';
	@override String get successMsg => 'Profil eklendi';
	@override String get nameAutoHint => 'Otomatik algılanır (isteğe bağlı)';
}

// Path: profile.update
class Translations$profile$update$tr extends Translations$profile$update$en {
	Translations$profile$update$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Güncelle';
	@override String get tooltip => 'Profili Güncelle';
	@override String get updateSubscriptions => 'Abonelikleri Güncelle';
	@override String get failureMsg => 'Profil güncellenemedi';
	@override String get successMsg => 'Profil başarıyla güncellendi';
	@override String namedFailureMsg({required Object name}) => '"${name}" güncellenemedi';
	@override String namedSuccessMsg({required Object name}) => '"${name}" başarıyla güncellendi';
}

// Path: profile.share
class Translations$profile$share$tr extends Translations$profile$share$en {
	Translations$profile$share$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Paylaş';
	@override String get exportToClipboardSuccess => 'Panoya aktarıldı';
	@override String get exportSubLinkToClipboard => 'Abonelik bağlantısını panoya aktar';
	@override String get subLinkQrCode => 'QR kodun abonelik bağlantısı ';
	@override String get exportConfigToClipboard => 'Yapılandırmayı panoya aktar';
	@override String get exportConfigToClipboardSuccess => 'Yapılandırma panoya kopyalandı';
	@override String get shareLink => 'Bağlantıyı Paylaş';
	@override String get subscriptionLinkCopied => 'Abonelik bağlantısı kopyalandı';
	@override String get configCopied => 'Yapılandırma kopyalandı';
	@override String get copyFailed => 'Kopyalama başarısız';
}

// Path: profile.edit
class Translations$profile$edit$tr extends Translations$profile$edit$en {
	Translations$profile$edit$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Düzenle';
	@override String get selectActiveTxt => 'Etkin profili seçin';
}

// Path: profile.delete
class Translations$profile$delete$tr extends Translations$profile$delete$en {
	Translations$profile$delete$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Sil';
	@override String get confirmationMsg => 'Profil kalıcı olarak silinsin mi?';
	@override String get successMsg => 'Profil başarıyla silindi';
	@override String get confirmTitle => 'Profili sil';
	@override String namedConfirmMsg({required Object name}) => '"${name}" silinsin mi? Bu işlem geri alınamaz.';
}

// Path: profile.save
class Translations$profile$save$tr extends Translations$profile$save$en {
	Translations$profile$save$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Kaydet';
	@override String get successMsg => 'Profil başarıyla kaydedildi';
	@override String get failureMsg => 'Profil kaydedilemedi';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$tr extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'İsim';
	@override String get nameHint => 'Profil ismi';
	@override String get urlLabel => 'URL';
	@override String get urlHint => 'Tam yapılandırma URL\'i';
	@override String get emptyNameMsg => 'İsim gerekli';
	@override String get invalidUrlMsg => 'Geçersiz URL';
	@override String get lastUpdate => 'Son Güncelleme';
	@override String get updateInterval => 'Otomatik güncelleme';
	@override String get updateIntervalDialogTitle => 'Otomatik Güncelleme Aralığı (saat olarak)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'Kapalı';
	@override String updateIntervalHours({required Object hours}) => '${hours} sa';
	@override String updateIntervalDays({required Object days}) => '${days} gün';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$tr extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get add => 'Ekle';
	@override String get updateAll => 'Tümünü Güncelle';
	@override String get sort => 'Sırala';
	@override String get copyConfigSuccess => 'Yapılandırma kopyalandı';
	@override String get editConfig => 'Yapılandırmayı Düzenle';
}

// Path: profile.details
class Translations$profile$details$tr extends Translations$profile$details$en {
	Translations$profile$details$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'Temel Bilgiler';
	@override String get subscriptionStatus => 'Abonelik Durumu';
	@override String get options => 'Seçenekler';
	@override String get updateNow => 'Şimdi Güncelle';
	@override String get updateNowDescription => 'Sunucudan en güncel yapılandırmayı al';
	@override String get expireDate => 'Son Kullanma Tarihi';
	@override String get unlimited => 'Sınırsız';
}

// Path: profile.overview
class Translations$profile$overview$tr extends Translations$profile$overview$en {
	Translations$profile$overview$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'Şu Anda Kullanılıyor';
	@override String remainingDays({required Object days}) => '${days} gün kaldı';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$tr extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'Varsayılan';
	@override String get name => 'Alfabetik olarak';
	@override String get delay => 'Gecikmeyle';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$tr extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'Gecikme: ${delay} ms';
	@override String get timeout => 'Gecikme Testi Zaman Aşımı';
	@override String get testing => 'Gecikme: Test ediliyor...';
	@override String get untested => 'Gecikme: Test edilmedi';
	@override String stale({required Object delay}) => 'Gecikme: ${delay} ms (önceki sonuç)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$tr extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get address => 'IP Adresi';
	@override String get country => 'Ülke';
}

// Path: settings.general
class Translations$settings$general$tr extends Translations$settings$general$en {
	Translations$settings$general$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Genel';
	@override String get locale => 'Dil';
	@override String get region => 'Bölge';
	@override String get regionMsg => 'Yerel adresleri atlamak için varsayılan seçeneği seçebilirsin';
	@override late final Translations$settings$general$regions$tr regions = Translations$settings$general$regions$tr._(_root);
	@override String get themeMode => 'Tema Modu';
	@override late final Translations$settings$general$themeModes$tr themeModes = Translations$settings$general$themeModes$tr._(_root);
	@override String get enableAnalytics => 'Analitikleri Etkinleştir';
	@override String get enableAnalyticsMsg => 'Uygulamayı iyileştirmek için analiz toplama ve kilitlenme raporları göndermeye izni verin';
	@override String get autoStart => 'Önyüklemede Başlat';
	@override String get silentStart => 'Sessiz Başlatma';
	@override String get openWorkingDir => 'Çalışma Dizinini Aç';
	@override String get ignoreBatteryOptimizations => 'Pil Optimizasyonunu Devre Dışı Bırak';
	@override String get ignoreBatteryOptimizationsMsg => 'Optimum VPN performansı için kısıtlamaları kaldırın';
	@override String get dynamicNotification => 'Bildirimde hızı göster';
	@override String get hapticFeedback => 'Dokunsal Geri Bildirim';
	@override String get autoIpCheck => 'Bağlantı IP’sini Otomatik Denetle';
	@override late final Translations$settings$general$batteryOptimizationStatus$tr batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$tr._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$tr extends Translations$settings$advanced$en {
	Translations$settings$advanced$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Gelişmiş';
	@override String get debugMode => 'Hata ayıklama modu';
	@override String get debugModeMsg => 'Bu değişikliği uygulamak için uygulamayı yeniden başlatın';
	@override String get memoryLimit => 'Bellek Sınırı';
	@override String get memoryLimitMsg => 'Yetersiz bellek hataları veya sık sık uygulama çökmesi yaşıyorsanız etkinleştirin';
	@override String get resetTunnel => 'VPN Profilini Sıfırla';
	@override String get resetTunnelSuccess => 'VPN profili sıfırlandı';
}

// Path: settings.network
class Translations$settings$network$tr extends Translations$settings$network$en {
	Translations$settings$network$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'Uygulama başına Proxy';
	@override late final Translations$settings$network$perAppProxyModes$tr perAppProxyModes = Translations$settings$network$perAppProxyModes$tr._(_root);
	@override String get showSystemApps => 'Sistem uygulamalarını göster';
	@override String get hideSystemApps => 'Sistem uygulamalarını gizle';
	@override String get clearSelection => 'Seçimi temizle';
	@override String get perAppProxyLoadFailedMsg => 'Uygulama listesi yüklenemedi';
	@override String get perAppProxyRetry => 'Yeniden Dene';
	@override String get perAppProxyEmptyMsg => 'Sonuç bulunamadı';
	@override String get perAppProxyAndroidOnlyMsg => 'Uygulama başına hat modu yalnızca Android’de desteklenir';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$tr extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Varlıkları Yönlendirme';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => 'Sürüm ${version}';
	@override String get fileMissing => 'Eksik dosya';
	@override String get update => 'Güncelleme';
	@override String get download => 'İndirmek';
	@override String get failureMsg => 'Öğe güncellenemedi';
	@override String get successMsg => 'Öğe başarıyla güncellendi';
	@override String get addRecommended => 'Önerilen Varlıkları Ekle';
	@override String get missingGeoAssetsMsg => 'Seçilen yönlendirme varlıklarının dosyaları eksik. Bunları indirin veya mevcut olanları seçin.';
}

// Path: settings.backup
class Translations$settings$backup$tr extends Translations$settings$backup$en {
	Translations$settings$backup$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'Yedeği İçe Aktar';
	@override String get importConfirmMsg => 'Bu işlem aboneliklerinizi yedekteki aboneliklerle değiştirir ve yedekteki ayarları uygular. Önce mevcut verilerin bir anlık görüntüsü kaydedilir; içe aktarma başarısız olursa otomatik olarak geri yüklenir.';
	@override String importRemovesMsg({required Object count}) => 'Bu cihazdaki ${count} abonelik yedekte yok ve kaldırılacak.';
	@override String reportImported({required Object profiles, required Object settings}) => '${profiles} abonelik ve ${settings} ayar içe aktarıldı.';
	@override String reportDropped({required Object count}) => 'Yedekteki ${count} abonelik, verileri geçersiz olduğu için atlandı.';
	@override String reportSettingsSkipped({required Object count}) => '${count} ayar atlandı; mevcut değerleriniz korundu.';
	@override String get reportWarpOff => 'İçe aktarma WARP\'ı kapattı. Bu cihazda yeniden etkinleştirin.';
	@override String reportBackfill({required Object count}) => '${count} abonelik arka planda indirilecek.';
	@override String get errInvalidFile => 'Bu geçerli bir ClashMiao yedek dosyası değil.';
	@override String get errUnsupportedVersion => 'Bu yedek biçimi desteklenmiyor.';
	@override String get errNewerSchema => 'Bu yedek uygulamanın daha yeni bir sürümüyle oluşturulmuş. Lütfen önce uygulamayı güncelleyin.';
	@override String get errNoUsableProfiles => 'Bu yedekteki aboneliklerin hiçbiri içe aktarılamıyor.';
	@override String get errSnapshotFailed => 'Mevcut verilerin anlık görüntüsü kaydedilemedi, bu yüzden hiçbir şey değiştirilmedi.';
	@override String get errUnresolvedPrevious => 'Önceki bir içe aktarma yarıda kaldı ve henüz geri alınamadı. Hiçbir şey değiştirilmedi. Uygulamayı yeniden başlatıp tekrar deneyin.';
	@override String get errRolledBack => 'İçe aktarma başarısız oldu. Önceki verileriniz geri yüklendi.';
	@override String errNotRolledBack({required Object path}) => 'İçe aktarma başarısız oldu ve otomatik geri yükleme tamamlanmadı. Yeniden denemek için uygulamayı yeniden başlatın. Bir anlık görüntü ${path} konumuna kaydedildi.';
	@override String get errFailed => 'İçe aktarma başarısız oldu.';
	@override String get errBusy => 'Başka bir içe aktarma zaten sürüyor. Bitmesini bekleyin.';
	@override String get recoveryFailedTitle => 'Otomatik geri yükleme tamamlanmadı';
	@override String get recoveryFailedMsg => 'Son yedek içe aktarma yarıda kesildi ve uygulama verilerinizi önceki durumuna döndüremedi. Bazı veriler yarım aktarılmış olabilir. Otomatik geri yüklemeyi şimdi yeniden deneyin.';
	@override String get recoveryUnrecoverableTitle => 'Yarıda kalan içe aktarma geri alınamadı';
	@override String get recoveryUnrecoverableMsg => 'Son yedek içe aktarma yarıda kesildi, ancak anlık görüntüsü eksik veya okunamıyor; bu yüzden geri alınamaz. Lütfen aboneliklerinizi ve ayarlarınızı kontrol edin.';
	@override String get recoveryRetry => 'Yeniden dene';
	@override String get recoveryClose => 'Kapat';
	@override String get recoveryRetried => 'Verileriniz yarıda kalan içe aktarmadan önceki duruma geri yüklendi.';
	@override String get exportAction => 'Yedeği dışa aktar';
	@override String get importAction => 'Yedeği içe aktar';
	@override String get exportFailed => 'Yedek dışa aktarılamadı';
	@override String get shareText => 'ClashMiao yedeği';
}

// Path: settings.groups
class Translations$settings$groups$tr extends Translations$settings$groups$en {
	Translations$settings$groups$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get general => 'Genel';
	@override String get connection => 'Bağlantı';
	@override String get privacy => 'Gizlilik';
}

// Path: tray.status
class Translations$tray$status$tr extends Translations$tray$status$en {
	Translations$tray$status$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get connect => 'Bağlan';
	@override String get connecting => 'Bağlanıyor';
	@override String get disconnect => 'Bağlantıyı kes';
	@override String get disconnecting => 'Bağlantı kesiliyor';
}

// Path: failure.clash
class Translations$failure$clash$tr extends Translations$failure$clash$en {
	Translations$failure$clash$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmeyen hata';
	@override String core({required Object reason}) => 'Çakışma Hatası ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$tr extends Translations$failure$singbox$en {
	Translations$failure$singbox$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmedik Hizmet Hatası';
	@override String get serviceNotRunning => 'Servis çalışmıyor';
	@override String get missingPrivilege => 'Eksik Ayrıcalık';
	@override String get missingPrivilegeMsg => 'VPN modu yönetici ayrıcalıkları gerektirir. Uygulamayı yönetici olarak yeniden başlatın veya hizmet modunu değiştirin.';
	@override String get missingGeoAssets => 'Eksik Coğrafi Varlıklar';
	@override String get missingGeoAssetsMsg => 'Coğrafi öğeler eksik. Aktif varlığı değiştirmeyi veya ayarlarda seçileni indirmeyi düşünün.';
	@override String get invalidConfigOptions => 'Geçersiz yapılandırma seçenekleri';
	@override String get invalidConfig => 'Geçersiz Yapılandırma';
	@override String get create => 'Servis oluşturma hatası';
	@override String get start => 'Servis başlatma hatası';
	@override String get coreLibraryMissing => 'Çekirdek Kitaplığı Yüklü Değil';
	@override String get startTimeout => 'Servis Başlatma Zaman Aşımı';
	@override String get kernelUnresponsive => 'Çekirdek yanıt vermiyor. Lütfen tekrar deneyin veya uygulamayı yeniden başlatın.';
	@override String get kernelExited => 'Çekirdek beklenmedik şekilde kapandı';
}

// Path: failure.connectivity
class Translations$failure$connectivity$tr extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmedik Hata';
	@override String get missingVpnPermission => 'Eksik VPN İzni';
	@override String get missingNotificationPermission => 'Eksik Bildirim İzni';
	@override String get core => 'Temel Hata';
	@override String get networkUnavailable => 'Ağ Kullanılamıyor';
	@override String get nativeUnresponsive => 'Arka plan hizmetiyle bağlantı kesildi. Lütfen tekrar deneyin.';
}

// Path: failure.profiles
class Translations$failure$profiles$tr extends Translations$failure$profiles$en {
	Translations$failure$profiles$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmedik hata';
	@override String get notFound => 'Profil bulunamadı';
	@override String get invalidConfig => 'Geçersiz Yapılandırmalar';
	@override String get invalidUrl => 'Geçersiz URL';
	@override String get noActive => 'Etkin Profil Yok';
	@override String get readOnlyUpgrade => 'Abonelikleri değiştirmeden önce uygulamayı güncelleyin';
}

// Path: failure.connection
class Translations$failure$connection$tr extends Translations$failure$connection$en {
	Translations$failure$connection$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmeyen bağlantı hatası';
	@override String get timeout => 'Bağlantı zamanaşımına uğradı';
	@override String get badResponse => 'Kötü yanıt';
	@override String get connectionError => 'Bağlantı hatası';
	@override String get badCertificate => 'Kötü sertifika';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$tr extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Beklenmeyen hata';
	@override String get notUpdate => 'Güncelleme mevcut değil';
	@override String get activeNotFound => 'Etkin Coğrafi Varlık Bulunamadı';
}

// Path: config.serviceModes
class Translations$config$serviceModes$tr extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Proxy';
	@override String get systemProxy => 'Sistem Proxy';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN Servisi';
}

// Path: config.section
class Translations$config$section$tr extends Translations$config$section$en {
	Translations$config$section$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get route => 'Rota Seçenekleri';
	@override String get dns => 'DNS Seçenekleri';
	@override String get inbound => 'Gelen Seçenekler';
	@override String get mux => 'Multiplexer';
	@override String get outbound => 'Outbound Options';
	@override String get tlsTricks => 'TLS Tricks';
	@override String get warp => 'WARP Options';
	@override String get misc => 'Çeşitli Seçenekler';
}

// Path: config.warpConsent
class Translations$config$warpConsent$tr extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cloudflare WARP Onayı';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP ücretsiz bir WireGuard VPN sağlayıcısıdır. Bu seçeneği etkinleştirerek Cloudflare WARP\'ın '),
		tos('Hizmet Şartları'),
		const TextSpan(text: ' ve '),
		privacy('Gizlilik Politikası'),
		const TextSpan(text: '\'nı kabul etmiş olursunuz.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$tr extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Devre dışı bırak';
	@override String get enable => 'Etkinleştir';
	@override String get prefer => 'Tercih edilen';
	@override String get only => 'Özel';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$tr extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get inbound => 'Detour WARP through proxies';
	@override String get outbound => 'Detour proxies through WARP';
	@override String get proxyOverWarp => 'Hatları WARP Üzerinden Geçir';
	@override String get warpOverProxy => 'WARP\'ı Hatlar Üzerinden Geçir';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$tr extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Yalnızca Hat';
	@override String get systemProxy => 'Sistem Hattı';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN Servisi';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$tr extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'İzin reddedildi';
	@override String get unexpectedError => 'Bir şeyler yanlış gitti';
	@override String get torchSemanticLabel => 'El feneri';
	@override String get facingSemanticLabel => 'Kameraya önü';
	@override String get permissionRequest => 'QR Kodu taramak için kamera izni';
}

// Path: settings.general.regions
class Translations$settings$general$regions$tr extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get ir => 'İran (ir)';
	@override String get cn => 'Çin (cn)';
	@override String get ru => 'Rusya (ru)';
	@override String get af => 'Afghanistan (af)';
	@override String get id => 'Endonezya (id)';
	@override String get other => 'Diğer';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$tr extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get system => 'Sistem temasını takip et';
	@override String get dark => 'Karanlık mod';
	@override String get light => 'Işık modu';
	@override String get black => 'Siyah mod';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$tr extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'Muaf';
	@override String get notExempted => 'Muaf Değil';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$tr extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$tr._(TranslationsTr root) : this._root = root, super.internal(root);

	final TranslationsTr _root; // ignore: unused_field

	// Translations
	@override String get off => 'Tümü';
	@override String get offMsg => 'Proxy tüm uygulamalar';
	@override String get include => 'Proxy';
	@override String get includeMsg => 'Yalnızca proxy seçilen uygulamalar';
	@override String get exclude => 'Atlatma';
	@override String get excludeMsg => 'Seçilen uygulamalara proxy uygulama';
}

/// The flat map containing all translations for locale <tr>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsTr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Sıfırla',
			'general.toggle.enabled' => 'Etkin',
			'general.toggle.disabled' => 'Devre dışı',
			'general.state.disable' => 'Devre dışı bırak',
			'general.sort' => 'Sırala',
			'general.sortBy' => 'Sırala',
			'general.addToClipboard' => 'Panoya ekle',
			'general.notSet' => 'Ayarlanmadı',
			'general.agree' => 'Kabul etmek',
			'general.decline' => 'Reddetmek',
			'general.unknown' => 'Bilinmeyen',
			'general.hidden' => 'Gizlenmiş',
			'general.timeout' => 'Zaman aşımı',
			'general.showMore' => 'Daha fazla göster',
			'general.showLess' => 'Daha az göster',
			'general.grantPermission' => 'İzin Ver',
			'general.clipboardExportSuccessMsg' => 'Panoya kopyalandı',
			'general.openAppSettings' => 'Uygulama Ayarlarını Aç',
			'general.underDevelopment' => 'Geliştirme Aşamasında',
			'general.confirm' => 'Onayla',
			'general.close' => 'Kapat',
			'general.cancel' => 'İptal',
			'general.clipboardEmpty' => 'Pano boş',
			'general.clipboardReadFailed' => 'Pano okunamadı',
			'general.moreOptions' => 'Diğer seçenekler',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'devam ederek '), tap(_root.about.termsAndConditions), const TextSpan(text: ' kabul etmiş olursunuz'), ]), 
			'intro.start' => 'Başla',
			'home.pageTitle' => 'Ana Sayfa',
			'home.emptyProfilesMsg' => 'Aboneliği profili ekleyerek başlayın',
			'home.noActiveProfileMsg' => 'Profil seçin',
			'home.routingMode.global' => 'Genel Proxy',
			'home.routingMode.smart' => 'Akıllı Yönlendirme',
			'home.failedToSwitchMode' => ({required Object error}) => 'Mod değiştirilemedi: ${error}',
			'home.connectionFailedTitle' => 'Bağlantı Başarısız',
			'home.coreMissingTitle' => 'Çekirdek Kitaplığı Bulunamadı',
			'home.coreMissingMsg' => 'Uygulama ağ çekirdeğini yükleyemedi. Bağlantı kullanılamıyor. Uygulamayı yeniden kurun ya da çekirdek kitaplık dosyasının çalıştırılabilir dosyanın yanında olduğundan emin olun.',
			'home.degradedTitle' => 'Bağlandı, ancak internet erişimi yok',
			'home.degradedMsg' => 'Tünel açık ancak trafik geçmiyor. Sunucu çalışmıyor olabilir — başka bir sunucu deneyin veya bağlantıyı kesin.',
			'home.degradedRetry' => 'Yeniden Denetle',
			'home.egressIp.label' => 'Çıkış IP\'si',
			'home.egressIp.notConnected' => 'Çıkış IP\'sini görmek için bağlanın',
			'home.egressIp.tapToCheck' => 'Çıkış IP\'sini denetlemek için dokunun',
			'home.egressIp.checking' => 'Denetleniyor…',
			'home.egressIp.failedRetry' => 'Denetim başarısız, yeniden denemek için dokunun',
			'home.emptyProfilesHint' => 'Başlamak için aşağıdaki düğmeye dokunun',
			'home.noActiveProfileTitle' => 'Profil seçilmedi',
			'stats.trafficLive' => 'Canlı Trafik',
			'stats.trafficTotal' => 'Toplam Trafik',
			'stats.uplink' => 'Çıkış Yolu',
			'stats.downlink' => 'Giriş Yolu',
			'stats.traffic' => 'Trafik',
			'stats.trafficUsage' => 'Trafik Kullanımı',
			'stats.liveSpeed' => 'Anlık Hız',
			'stats.connection' => 'Bağlantı',
			'stats.speed' => 'Hız',
			'stats.totalTransferred' => 'Toplam Aktarılan',
			'stats.sessionTraffic' => 'Bu oturumun trafiği',
			'stats.downloadSpeed' => 'İndirme hızı',
			'profile.overviewPageTitle' => 'Profiller',
			'profile.detailsPageTitle' => 'Profil',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Aktif profil adı: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'Tüm profilleri görüntüleyin',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Aktif profil olarak "${name}" seçeneğini seçin.',
			'profile.subscription.traffic' => 'Trafik',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => '${timeago} güncellendi',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '${duration} Gün Kaldı',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed}/${total} trafik tüketildi',
			'profile.subscription.expired' => 'Süresi Doldu',
			'profile.subscription.noTraffic' => 'Kotal Doldu',
			'profile.subscription.upload' => 'Yükleme',
			'profile.subscription.download' => 'İndirme',
			'profile.subscription.total' => 'Toplam Trafik',
			'profile.subscription.expireDate' => 'Son Kullanma Tarihi',
			'profile.sortBy.lastUpdate' => 'Yakın zamanda güncellendi',
			'profile.sortBy.name' => 'Alfabetik',
			'profile.add.buttonText' => 'Yeni profil',
			'profile.add.shortBtnTxt' => 'Yeni profil',
			'profile.add.fromClipboard' => 'Panodan Ekle',
			'profile.add.scanQr' => 'QR kodunu tarayın',
			'profile.add.qrScanner.permissionDeniedError' => 'İzin reddedildi',
			'profile.add.qrScanner.unexpectedError' => 'Bir şeyler yanlış gitti',
			'profile.add.qrScanner.torchSemanticLabel' => 'El feneri',
			'profile.add.qrScanner.facingSemanticLabel' => 'Kameraya önü',
			'profile.add.qrScanner.permissionRequest' => 'QR Kodu taramak için kamera izni',
			'profile.add.manually' => 'Manuel giriş',
			'profile.add.addingProfileMsg' => 'Profil Ekleniyor',
			'profile.add.failureMsg' => 'Profil eklenemedi',
			'profile.add.modalSubtitle' => 'Yapılandırma dosyasını nasıl ekleyeceğinizi seçin',
			'profile.add.manuallyDescription' => 'Sunucu yapılandırmasını elle girin',
			'profile.add.addWarp' => 'WARP Ekle',
			'profile.add.warpDescription' => 'Cloudflare WARP ile ücretsiz hızlandırma',
			'profile.add.addingWarpMsg' => 'WARP kaydedilirken lütfen bekleyin.',
			'profile.add.importedNamed' => ({required Object name}) => 'Abonelik içe aktarıldı: ${name}',
			'profile.add.clipboardEmpty' => 'Pano boş, içe aktarılacak bir şey yok',
			'profile.add.deepLinkMissingUrl' => 'Bağlantıda abonelik adresi yok',
			'profile.add.successMsg' => 'Profil eklendi',
			'profile.add.nameAutoHint' => 'Otomatik algılanır (isteğe bağlı)',
			'profile.update.buttonTxt' => 'Güncelle',
			'profile.update.tooltip' => 'Profili Güncelle',
			'profile.update.updateSubscriptions' => 'Abonelikleri Güncelle',
			'profile.update.failureMsg' => 'Profil güncellenemedi',
			'profile.update.successMsg' => 'Profil başarıyla güncellendi',
			'profile.update.namedFailureMsg' => ({required Object name}) => '"${name}" güncellenemedi',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" başarıyla güncellendi',
			'profile.share.buttonText' => 'Paylaş',
			'profile.share.exportToClipboardSuccess' => 'Panoya aktarıldı',
			'profile.share.exportSubLinkToClipboard' => 'Abonelik bağlantısını panoya aktar',
			'profile.share.subLinkQrCode' => 'QR kodun abonelik bağlantısı ',
			'profile.share.exportConfigToClipboard' => 'Yapılandırmayı panoya aktar',
			'profile.share.exportConfigToClipboardSuccess' => 'Yapılandırma panoya kopyalandı',
			'profile.share.shareLink' => 'Bağlantıyı Paylaş',
			'profile.share.subscriptionLinkCopied' => 'Abonelik bağlantısı kopyalandı',
			'profile.share.configCopied' => 'Yapılandırma kopyalandı',
			'profile.share.copyFailed' => 'Kopyalama başarısız',
			'profile.edit.buttonTxt' => 'Düzenle',
			'profile.edit.selectActiveTxt' => 'Etkin profili seçin',
			'profile.delete.buttonTxt' => 'Sil',
			'profile.delete.confirmationMsg' => 'Profil kalıcı olarak silinsin mi?',
			'profile.delete.successMsg' => 'Profil başarıyla silindi',
			'profile.delete.confirmTitle' => 'Profili sil',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => '"${name}" silinsin mi? Bu işlem geri alınamaz.',
			'profile.save.buttonText' => 'Kaydet',
			'profile.save.successMsg' => 'Profil başarıyla kaydedildi',
			'profile.save.failureMsg' => 'Profil kaydedilemedi',
			'profile.detailsForm.nameLabel' => 'İsim',
			'profile.detailsForm.nameHint' => 'Profil ismi',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'Tam yapılandırma URL\'i',
			'profile.detailsForm.emptyNameMsg' => 'İsim gerekli',
			'profile.detailsForm.invalidUrlMsg' => 'Geçersiz URL',
			'profile.detailsForm.lastUpdate' => 'Son Güncelleme',
			'profile.detailsForm.updateInterval' => 'Otomatik güncelleme',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Otomatik Güncelleme Aralığı (saat olarak)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Kapalı',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} sa',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} gün',
			'profile.actionButtons.add' => 'Ekle',
			'profile.actionButtons.updateAll' => 'Tümünü Güncelle',
			'profile.actionButtons.sort' => 'Sırala',
			'profile.actionButtons.copyConfigSuccess' => 'Yapılandırma kopyalandı',
			'profile.actionButtons.editConfig' => 'Yapılandırmayı Düzenle',
			'profile.details.basicInfo' => 'Temel Bilgiler',
			'profile.details.subscriptionStatus' => 'Abonelik Durumu',
			'profile.details.options' => 'Seçenekler',
			'profile.details.updateNow' => 'Şimdi Güncelle',
			'profile.details.updateNowDescription' => 'Sunucudan en güncel yapılandırmayı al',
			'profile.details.expireDate' => 'Son Kullanma Tarihi',
			'profile.details.unlimited' => 'Sınırsız',
			'profile.overview.currentlyUsing' => 'Şu Anda Kullanılıyor',
			'profile.overview.remainingDays' => ({required Object days}) => '${days} gün kaldı',
			'profile.remoteProfile' => 'Uzak Profil',
			'profile.defaultLocalName' => 'Yerel içe aktarma',
			'profile.defaultDeepLinkName' => 'Bağlantıdan içe aktarma',
			'profile.switchFailedMsg' => 'Profil değiştirilemedi',
			'proxies.pageTitle' => 'Proxyler',
			'proxies.emptyProxiesMsg' => 'Kullanılabilir proxy yok',
			'proxies.delayTestTooltip' => 'Test Gecikmesi',
			'proxies.sortTooltip' => 'Proxy\'leri Sırala',
			'proxies.sortOptions.unsorted' => 'Varsayılan',
			'proxies.sortOptions.name' => 'Alfabetik olarak',
			'proxies.sortOptions.delay' => 'Gecikmeyle',
			'proxies.checkIp' => 'IP\'yi Denetle',
			'proxies.unknownIp' => 'Bilinmeyen IP',
			'proxies.autoSelect' => 'Otomatik Seçim',
			'proxies.autoSelectDescription' => 'En hızlı sunucuya otomatik bağlan',
			'proxies.sortModalTitle' => 'Sıralama yöntemini seçin',
			'proxies.activeProxySemanticLabel' => 'Etkin Hat',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'Gecikme: ${delay} ms',
			'proxies.delaySemantics.timeout' => 'Gecikme Testi Zaman Aşımı',
			'proxies.delaySemantics.testing' => 'Gecikme: Test ediliyor...',
			'proxies.delaySemantics.untested' => 'Gecikme: Test edilmedi',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'Gecikme: ${delay} ms (önceki sonuç)',
			'proxies.ipInfoSemantics.address' => 'IP Adresi',
			'proxies.ipInfoSemantics.country' => 'Ülke',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Gecikme test ediliyor: ${name}',
			'proxies.switchedTo' => ({required Object name}) => '${name} olarak değiştirildi',
			'proxies.switchFailed' => 'Sunucu değiştirilemedi. Lütfen tekrar deneyin.',
			'proxies.testFailed' => 'Gecikme testi başarısız oldu. Lütfen tekrar deneyin.',
			'proxies.groupsLoading' => 'Sunucu listesi hâlâ yükleniyor. Lütfen birazdan tekrar deneyin.',
			'proxies.connectBeforeSwitch' => 'Hat değiştirmeden önce bağlanın',
			'proxies.startDelayTestForGroups' => ({required Object count}) => '${count} hat için gecikme testi başlatıldı',
			'proxies.delayTestBtn' => 'Gecikme',
			'proxies.delayTimeout' => 'Zaman aşımı',
			'proxies.connectBeforeTest' => 'Gecikmeyi test etmek için önce bağlanın',
			'proxies.lineCount' => ({required Object count}) => '${count} hat',
			'proxies.manualSelect' => 'Elle Seçim',
			'proxies.autoTest' => 'Otomatik Test',
			'logs.pageTitle' => 'Log',
			'logs.filterHint' => 'Filtre',
			'logs.allLevelsFilter' => 'Tüm',
			'logs.shareCoreLogs' => 'Çekirdek Loglarını Paylaş',
			'logs.shareAppLogs' => 'Uygulama Loglarını paylaş',
			'logs.pauseTooltip' => 'Duraklat',
			'logs.resumeTooltip' => 'Devam et',
			'logs.clearTooltip' => 'Temizle',
			'logs.logsCleared' => 'Günlükler temizlendi',
			'logs.logsCopied' => 'Günlükler kopyalandı',
			'logs.logsUnderDevelopment' => 'Günlük özelliği geliştirme aşamasında',
			'logs.noLogsWhenDisconnected' => 'Bağlı değil, günlük yok',
			'logs.loadFailed' => 'Günlükler yüklenemedi',
			'logs.empty' => 'Henüz günlük yok',
			'logs.clearFailed' => 'Günlükler temizlenemedi',
			'settings.pageTitle' => 'Ayarlar',
			'settings.requiresRestartMsg' => 'Bunun etkili olması için uygulamayı yeniden başlatın',
			'settings.experimental' => 'Deneysel',
			'settings.experimentalMsg' => 'Deneysel işaretli özellikler hâlâ geliştirilme aşamasındadır ve sorunlara neden olabilir.',
			'settings.general.sectionTitle' => 'Genel',
			'settings.general.locale' => 'Dil',
			'settings.general.region' => 'Bölge',
			'settings.general.regionMsg' => 'Yerel adresleri atlamak için varsayılan seçeneği seçebilirsin',
			'settings.general.regions.ir' => 'İran (ir)',
			'settings.general.regions.cn' => 'Çin (cn)',
			'settings.general.regions.ru' => 'Rusya (ru)',
			'settings.general.regions.af' => 'Afghanistan (af)',
			'settings.general.regions.id' => 'Endonezya (id)',
			'settings.general.regions.other' => 'Diğer',
			'settings.general.themeMode' => 'Tema Modu',
			'settings.general.themeModes.system' => 'Sistem temasını takip et',
			'settings.general.themeModes.dark' => 'Karanlık mod',
			'settings.general.themeModes.light' => 'Işık modu',
			'settings.general.themeModes.black' => 'Siyah mod',
			'settings.general.enableAnalytics' => 'Analitikleri Etkinleştir',
			'settings.general.enableAnalyticsMsg' => 'Uygulamayı iyileştirmek için analiz toplama ve kilitlenme raporları göndermeye izni verin',
			'settings.general.autoStart' => 'Önyüklemede Başlat',
			'settings.general.silentStart' => 'Sessiz Başlatma',
			'settings.general.openWorkingDir' => 'Çalışma Dizinini Aç',
			'settings.general.ignoreBatteryOptimizations' => 'Pil Optimizasyonunu Devre Dışı Bırak',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Optimum VPN performansı için kısıtlamaları kaldırın',
			'settings.general.dynamicNotification' => 'Bildirimde hızı göster',
			'settings.general.hapticFeedback' => 'Dokunsal Geri Bildirim',
			'settings.general.autoIpCheck' => 'Bağlantı IP’sini Otomatik Denetle',
			'settings.general.batteryOptimizationStatus.exempted' => 'Muaf',
			'settings.general.batteryOptimizationStatus.notExempted' => 'Muaf Değil',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Gelişmiş',
			'settings.advanced.debugMode' => 'Hata ayıklama modu',
			'settings.advanced.debugModeMsg' => 'Bu değişikliği uygulamak için uygulamayı yeniden başlatın',
			'settings.advanced.memoryLimit' => 'Bellek Sınırı',
			'settings.advanced.memoryLimitMsg' => 'Yetersiz bellek hataları veya sık sık uygulama çökmesi yaşıyorsanız etkinleştirin',
			'settings.advanced.resetTunnel' => 'VPN Profilini Sıfırla',
			'settings.advanced.resetTunnelSuccess' => 'VPN profili sıfırlandı',
			'settings.network.perAppProxyPageTitle' => 'Uygulama başına Proxy',
			'settings.network.perAppProxyModes.off' => 'Tümü',
			'settings.network.perAppProxyModes.offMsg' => 'Proxy tüm uygulamalar',
			'settings.network.perAppProxyModes.include' => 'Proxy',
			'settings.network.perAppProxyModes.includeMsg' => 'Yalnızca proxy seçilen uygulamalar',
			'settings.network.perAppProxyModes.exclude' => 'Atlatma',
			'settings.network.perAppProxyModes.excludeMsg' => 'Seçilen uygulamalara proxy uygulama',
			'settings.network.showSystemApps' => 'Sistem uygulamalarını göster',
			'settings.network.hideSystemApps' => 'Sistem uygulamalarını gizle',
			'settings.network.clearSelection' => 'Seçimi temizle',
			'settings.network.perAppProxyLoadFailedMsg' => 'Uygulama listesi yüklenemedi',
			'settings.network.perAppProxyRetry' => 'Yeniden Dene',
			'settings.network.perAppProxyEmptyMsg' => 'Sonuç bulunamadı',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'Uygulama başına hat modu yalnızca Android’de desteklenir',
			'settings.geoAssets.pageTitle' => 'Varlıkları Yönlendirme',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => 'Sürüm ${version}',
			'settings.geoAssets.fileMissing' => 'Eksik dosya',
			'settings.geoAssets.update' => 'Güncelleme',
			'settings.geoAssets.download' => 'İndirmek',
			'settings.geoAssets.failureMsg' => 'Öğe güncellenemedi',
			'settings.geoAssets.successMsg' => 'Öğe başarıyla güncellendi',
			'settings.geoAssets.addRecommended' => 'Önerilen Varlıkları Ekle',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Seçilen yönlendirme varlıklarının dosyaları eksik. Bunları indirin veya mevcut olanları seçin.',
			'settings.exportOptions' => 'Anonim Seçenekleri Panoya Kopyala',
			'settings.exportAllOptions' => 'Tüm Seçenekleri Panoya Kopyala',
			'settings.importOptions' => 'Seçenekleri Panodan İçe Aktar',
			'settings.importOptionsMsg' => 'Bu işlem tüm yapılandırma seçeneklerini verilen değerlerle değiştirir. Emin misiniz?',
			'settings.backup.importConfirmTitle' => 'Yedeği İçe Aktar',
			'settings.backup.importConfirmMsg' => 'Bu işlem aboneliklerinizi yedekteki aboneliklerle değiştirir ve yedekteki ayarları uygular. Önce mevcut verilerin bir anlık görüntüsü kaydedilir; içe aktarma başarısız olursa otomatik olarak geri yüklenir.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => 'Bu cihazdaki ${count} abonelik yedekte yok ve kaldırılacak.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '${profiles} abonelik ve ${settings} ayar içe aktarıldı.',
			'settings.backup.reportDropped' => ({required Object count}) => 'Yedekteki ${count} abonelik, verileri geçersiz olduğu için atlandı.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '${count} ayar atlandı; mevcut değerleriniz korundu.',
			'settings.backup.reportWarpOff' => 'İçe aktarma WARP\'ı kapattı. Bu cihazda yeniden etkinleştirin.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} abonelik arka planda indirilecek.',
			'settings.backup.errInvalidFile' => 'Bu geçerli bir ClashMiao yedek dosyası değil.',
			'settings.backup.errUnsupportedVersion' => 'Bu yedek biçimi desteklenmiyor.',
			'settings.backup.errNewerSchema' => 'Bu yedek uygulamanın daha yeni bir sürümüyle oluşturulmuş. Lütfen önce uygulamayı güncelleyin.',
			'settings.backup.errNoUsableProfiles' => 'Bu yedekteki aboneliklerin hiçbiri içe aktarılamıyor.',
			'settings.backup.errSnapshotFailed' => 'Mevcut verilerin anlık görüntüsü kaydedilemedi, bu yüzden hiçbir şey değiştirilmedi.',
			'settings.backup.errUnresolvedPrevious' => 'Önceki bir içe aktarma yarıda kaldı ve henüz geri alınamadı. Hiçbir şey değiştirilmedi. Uygulamayı yeniden başlatıp tekrar deneyin.',
			'settings.backup.errRolledBack' => 'İçe aktarma başarısız oldu. Önceki verileriniz geri yüklendi.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'İçe aktarma başarısız oldu ve otomatik geri yükleme tamamlanmadı. Yeniden denemek için uygulamayı yeniden başlatın. Bir anlık görüntü ${path} konumuna kaydedildi.',
			'settings.backup.errFailed' => 'İçe aktarma başarısız oldu.',
			'settings.backup.errBusy' => 'Başka bir içe aktarma zaten sürüyor. Bitmesini bekleyin.',
			'settings.backup.recoveryFailedTitle' => 'Otomatik geri yükleme tamamlanmadı',
			'settings.backup.recoveryFailedMsg' => 'Son yedek içe aktarma yarıda kesildi ve uygulama verilerinizi önceki durumuna döndüremedi. Bazı veriler yarım aktarılmış olabilir. Otomatik geri yüklemeyi şimdi yeniden deneyin.',
			'settings.backup.recoveryUnrecoverableTitle' => 'Yarıda kalan içe aktarma geri alınamadı',
			'settings.backup.recoveryUnrecoverableMsg' => 'Son yedek içe aktarma yarıda kesildi, ancak anlık görüntüsü eksik veya okunamıyor; bu yüzden geri alınamaz. Lütfen aboneliklerinizi ve ayarlarınızı kontrol edin.',
			'settings.backup.recoveryRetry' => 'Yeniden dene',
			'settings.backup.recoveryClose' => 'Kapat',
			'settings.backup.recoveryRetried' => 'Verileriniz yarıda kalan içe aktarmadan önceki duruma geri yüklendi.',
			'settings.backup.exportAction' => 'Yedeği dışa aktar',
			'settings.backup.importAction' => 'Yedeği içe aktar',
			'settings.backup.exportFailed' => 'Yedek dışa aktarılamadı',
			'settings.backup.shareText' => 'ClashMiao yedeği',
			'settings.systemProxyEnabled' => 'Sistem proxy’si etkin',
			'settings.systemProxyDisabled' => 'Sistem proxy’si devre dışı (uygulamak için yeniden bağlanın)',
			'settings.adminPrivilegesRequired' => 'macOS\'ta yönetici ayrıcalıkları gerekir',
			'settings.portChangeNotice' => 'Bağlantı noktası değişikliklerinin uygulanması için yeniden bağlanmak gerekir',
			'settings.groups.general' => 'Genel',
			'settings.groups.connection' => 'Bağlantı',
			'settings.groups.privacy' => 'Gizlilik',
			'settings.importOptionsInvalid' => 'Pano geçerli bir ayar JSON\'u içermiyor',
			'settings.importOptionsNothing' => 'İçe aktarılabilir ayar bulunamadı',
			'settings.importOptionsDone' => ({required Object count}) => '${count} ayar içe aktarıldı',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '${applied} ayar içe aktarıldı; ${skipped} ayar geçersiz olduğu için atlandı',
			'about.pageTitle' => 'Hakkında',
			'about.version' => 'Sürüm',
			'about.sourceCode' => 'Kaynak kodu',
			'about.telegramChannel' => 'Telegram Kanalı',
			'about.checkForUpdate' => 'Güncellemeleri kontrol et',
			'about.privacyPolicy' => 'Gizlilik Politikası',
			'about.termsAndConditions' => 'Şartlar ve koşullar',
			'about.appDescription' => 'sing-box çekirdeğine dayalı çok platformlu proxy istemcisi',
			'about.openSourceLicenses' => 'Açık kaynak lisansları',
			'appUpdate.notAvailableMsg' => ' En son sürümü kullanıyorsunuz',
			'appUpdate.dialogTitle' => 'Yeni Güncell',
			'appUpdate.updateMsg' => '${_root.general.appTitle}\'ın yeni bir sürümü mevcut. Şimdi güncellemek ister misiniz?',
			'appUpdate.currentVersionLbl' => 'Şimdiki versiyon',
			'appUpdate.newVersionLbl' => 'Yeni versiyon',
			'appUpdate.updateNowBtnTxt' => 'Şimdi güncelle',
			'appUpdate.laterBtnTxt' => 'Daha sonra',
			'appUpdate.ignoreBtnTxt' => 'Görmezden gel',
			'appUpdate.checkFailedMsg' => 'Güncellemeler denetlenemedi. Ağınızı kontrol edip tekrar deneyin.',
			'tray.dashboard' => 'Gösterge Paneli',
			'tray.quit' => 'Çıkış yap',
			'tray.open' => 'Açık',
			'tray.status.connect' => 'Bağlan',
			'tray.status.connecting' => 'Bağlanıyor',
			'tray.status.disconnect' => 'Bağlantıyı kes',
			'tray.status.disconnecting' => 'Bağlantı kesiliyor',
			'tray.hide' => 'Gizle',
			'tray.proxyModeMenu' => 'Proxy Modu',
			'failure.unexpected' => 'Beklenmeyen hata',
			'failure.clash.unexpected' => 'Beklenmeyen hata',
			'failure.clash.core' => ({required Object reason}) => 'Çakışma Hatası ${reason}',
			'failure.singbox.unexpected' => 'Beklenmedik Hizmet Hatası',
			'failure.singbox.serviceNotRunning' => 'Servis çalışmıyor',
			'failure.singbox.missingPrivilege' => 'Eksik Ayrıcalık',
			'failure.singbox.missingPrivilegeMsg' => 'VPN modu yönetici ayrıcalıkları gerektirir. Uygulamayı yönetici olarak yeniden başlatın veya hizmet modunu değiştirin.',
			'failure.singbox.missingGeoAssets' => 'Eksik Coğrafi Varlıklar',
			'failure.singbox.missingGeoAssetsMsg' => 'Coğrafi öğeler eksik. Aktif varlığı değiştirmeyi veya ayarlarda seçileni indirmeyi düşünün.',
			'failure.singbox.invalidConfigOptions' => 'Geçersiz yapılandırma seçenekleri',
			'failure.singbox.invalidConfig' => 'Geçersiz Yapılandırma',
			'failure.singbox.create' => 'Servis oluşturma hatası',
			'failure.singbox.start' => 'Servis başlatma hatası',
			'failure.singbox.coreLibraryMissing' => 'Çekirdek Kitaplığı Yüklü Değil',
			'failure.singbox.startTimeout' => 'Servis Başlatma Zaman Aşımı',
			'failure.singbox.kernelUnresponsive' => 'Çekirdek yanıt vermiyor. Lütfen tekrar deneyin veya uygulamayı yeniden başlatın.',
			'failure.singbox.kernelExited' => 'Çekirdek beklenmedik şekilde kapandı',
			'failure.connectivity.unexpected' => 'Beklenmedik Hata',
			'failure.connectivity.missingVpnPermission' => 'Eksik VPN İzni',
			'failure.connectivity.missingNotificationPermission' => 'Eksik Bildirim İzni',
			'failure.connectivity.core' => 'Temel Hata',
			'failure.connectivity.networkUnavailable' => 'Ağ Kullanılamıyor',
			'failure.connectivity.nativeUnresponsive' => 'Arka plan hizmetiyle bağlantı kesildi. Lütfen tekrar deneyin.',
			'failure.profiles.unexpected' => 'Beklenmedik hata',
			'failure.profiles.notFound' => 'Profil bulunamadı',
			'failure.profiles.invalidConfig' => 'Geçersiz Yapılandırmalar',
			'failure.profiles.invalidUrl' => 'Geçersiz URL',
			'failure.profiles.noActive' => 'Etkin Profil Yok',
			'failure.profiles.readOnlyUpgrade' => 'Abonelikleri değiştirmeden önce uygulamayı güncelleyin',
			'failure.connection.unexpected' => 'Beklenmeyen bağlantı hatası',
			'failure.connection.timeout' => 'Bağlantı zamanaşımına uğradı',
			'failure.connection.badResponse' => 'Kötü yanıt',
			'failure.connection.connectionError' => 'Bağlantı hatası',
			'failure.connection.badCertificate' => 'Kötü sertifika',
			'failure.geoAssets.unexpected' => 'Beklenmeyen hata',
			'failure.geoAssets.notUpdate' => 'Güncelleme mevcut değil',
			'failure.geoAssets.activeNotFound' => 'Etkin Coğrafi Varlık Bulunamadı',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Bağlanmak için dokunun',
			'connection.connecting' => 'Bağlanıyor',
			'connection.disconnecting' => 'Bağlantı kesiliyor',
			'connection.connected' => 'Bağlandı',
			'connection.experimentalNotice' => 'Kullanımdaki Deneysel Özellikler',
			'connection.experimentalNoticeMsg' => 'Bağlantı kalitesini etkileyebilecek ve beklenmeyen hatalara neden olabilecek bazı deneysel özellikleri etkinleştirdiniz. Bu seçenekleri istediğiniz zaman Yapılandırma seçenekleri sayfasından değiştirebilir veya sıfırlayabilirsiniz.',
			'connection.disableExperimentalNotice' => 'Bir daha gösterme',
			'connection.reconnect' => 'Yeniden Bağlan',
			'connection.connectAnyWay' => 'Yine de bağlan',
			'connection.reconnectMsg' => 'Değişiklikleri uygulamak için yeniden bağlanılıyor...',
			'connection.staleSystemProxyCleaned' => 'Önceki anormal çıkıştan kalan sistem proxy ayarları temizlendi',
			'config.resetBtn' => 'Ayarları sıfırla',
			'config.serviceMode' => 'Servis modu',
			'config.serviceModes.proxy' => 'Proxy',
			'config.serviceModes.systemProxy' => 'Sistem Proxy',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'VPN Servisi',
			'config.section.route' => 'Rota Seçenekleri',
			'config.section.dns' => 'DNS Seçenekleri',
			'config.section.inbound' => 'Gelen Seçenekler',
			'config.section.mux' => 'Multiplexer',
			'config.section.outbound' => 'Outbound Options',
			'config.section.tlsTricks' => 'TLS Tricks',
			'config.section.warp' => 'WARP Options',
			'config.section.misc' => 'Çeşitli Seçenekler',
			'config.warpConsent.title' => 'Cloudflare WARP Onayı',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP ücretsiz bir WireGuard VPN sağlayıcısıdır. Bu seçeneği etkinleştirerek Cloudflare WARP\'ın '), tos('Hizmet Şartları'), const TextSpan(text: ' ve '), privacy('Gizlilik Politikası'), const TextSpan(text: '\'nı kabul etmiş olursunuz.'), ]), 
			'config.pageTitle' => 'Yapılandırma Seçenekleri',
			'config.logLevel' => 'Log Seviyesi',
			'config.resolveDestination' => 'Hedefi Çöz',
			'config.ipv6Mode' => 'IPv6 Rotası',
			'config.ipv6Modes.disable' => 'Devre dışı bırak',
			'config.ipv6Modes.enable' => 'Etkinleştir',
			'config.ipv6Modes.prefer' => 'Tercih edilen',
			'config.ipv6Modes.only' => 'Özel',
			'config.remoteDnsAddress' => 'Uzak DNS',
			'config.remoteDnsDomainStrategy' => 'Uzak DNS Domain Stratejisi',
			'config.directDnsAddress' => 'Doğrudan DNS',
			'config.directDnsDomainStrategy' => 'Doğrudan DNS Domain Stratejisi',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'Uygulanmadı: IPv6 yönlendirme kapalı ancak "${field}" yalnızca IPv6, bu yüzden hiçbir alan adı çözümlenemez. Önce IPv6 yönlendirmeyi açın veya başka bir strateji seçin.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'Uygulanmadı: IPv6 yönlendirme yalnızca IPv6 ancak "${field}" yalnızca IPv4, bu yüzden hiçbir alan adı çözümlenemez. Önce birini değiştirin.',
			'config.dnsStrategyReset' => ({required Object field}) => '"${field}" IPv6 yönlendirme ayarıyla çakıştı (hiçbir alan adı çözümlenemezdi) ve otomatiğe sıfırlandı.',
			'config.mixedPort' => 'Mixed Port',
			'config.localDnsPort' => 'Yerel DNS Bağlantı Noktası',
			'config.allowConnectionFromLan' => 'Allow Connection from LAN',
			'config.tunImplementation' => 'TUN İmplementasyonu',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'Bağlantı Testi URL\'i',
			'config.urlTestInterval' => 'URL Test Aralığı',
			'config.enableClashApi' => 'Clash API\'yi etkinleştir',
			'config.clashApiPort' => 'Clash API Bağlantı Noktası',
			'config.enableTun' => 'TUN\'u etkinleştir',
			'config.setSystemProxy' => 'Sistem Proxy\'sini Ayarla',
			'config.enableDnsRouting' => 'Enable DNS Routing',
			'config.enableFakeDns' => 'Sahte DNS\'yi Etkinleştir',
			'config.bypassLan' => 'Lan\'ı Atla',
			'config.strictRoute' => 'Kesin Rota',
			'config.enableTlsFragment' => 'Enable TLS Fragment',
			'config.tlsFragmentSize' => 'TLS Fragment Size',
			'config.tlsFragmentSleep' => 'TLS Fragment Sleep',
			'config.enableTlsMixedSniCase' => 'Enable TLS Mixed SNI Case',
			'config.enableTlsPadding' => 'Enable TLS Padding',
			'config.tlsPaddingSize' => 'TLS Padding',
			'config.enableMux' => 'Enable Mux',
			'config.muxProtocol' => 'Mux Protocol',
			'config.muxMaxStreams' => 'Max Concurrent Streams',
			'config.enableWarp' => 'Enable WARP',
			'config.setUpWarp' => 'WARP\'ı ayarla',
			'config.warpNotConfigured' => 'Yapılandırılmadı',
			'config.warpDetourMode' => 'Detour Mode',
			'config.warpDetourModes.inbound' => 'Detour WARP through proxies',
			'config.warpDetourModes.outbound' => 'Detour proxies through WARP',
			'config.warpDetourModes.proxyOverWarp' => 'Hatları WARP Üzerinden Geçir',
			'config.warpDetourModes.warpOverProxy' => 'WARP\'ı Hatlar Üzerinden Geçir',
			'config.warpLicenseKey' => 'License Key',
			'config.warpCleanIp' => 'Clean IP',
			'config.warpPort' => 'Port',
			'config.warpNoise' => 'Noise',
			'config.quickSettings' => 'Hızlı Ayarlar',
			'config.quickSettingsSubtitle' => 'Bağlantı deneyiminizi özelleştirin',
			'config.setupWarp' => 'WARP Kurulumu',
			'config.allOptions' => 'Tüm Yapılandırma Seçenekleri',
			'config.allAdvancedOptions' => 'Tüm Gelişmiş Seçenekler',
			'config.shortServiceModes.proxy' => 'Yalnızca Hat',
			'config.shortServiceModes.systemProxy' => 'Sistem Hattı',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'VPN Servisi',
			'config.generateWarpConfig' => 'WARP Yapılandırması Oluştur',
			'config.missingWarpConfig' => 'WARP Yapılandırması Eksik',
			'config.warpConfigGenerated' => 'WARP Yapılandırması Oluşturuldu',
			'config.blockAds' => 'Reklamları Engelle',
			'config.tproxyPort' => 'Şeffaf Hat Bağlantı Noktası',
			'config.warpNoiseSize' => 'Gürültü Boyutu',
			'config.warpNoiseMode' => 'Gürültü Modu',
			'config.warpNoiseDelay' => 'Gürültü Gecikmesi',
			'config.desktopProxyScopeNotice' => 'Masaüstünde yalnızca sistem proxy ayarına uyan uygulamalar tünelden geçer. Buna uymayan yazılımlar (bazı oyunlar, komut satırı araçları, kendi proxy ayarı olan uygulamalar) doğrudan bağlanır ve gerçek IP adresinizi açığa çıkarır.',
			'config.serviceModeIosVpnOnly' => 'iOS yalnızca VPN modunu destekler',
			'config.warpGenerating' => 'WARP yapılandırması oluşturuluyor…',
			'config.warpConfigFailed' => 'WARP yapılandırması oluşturulamadı. Lütfen daha sonra tekrar deneyin.',
			'config.portRangeError' => 'Port 1024 ile 65535 arasında olmalıdır',
			'config.dnsEmptyError' => 'DNS adresi boş olamaz',
			'config.rangeFormatError' => 'Bir sayı veya aralık girin, örn. 10-30',
			'config.urlSchemeError' => 'URL http:// veya https:// ile başlamalıdır',
			'config.manageRuleAssets' => 'Kural setlerini yönet',
			_ => null,
		};
	}
}
