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
class TranslationsId extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsId({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.id,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <id>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsId _root = this; // ignore: unused_field

	@override 
	TranslationsId $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsId(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$id general = Translations$general$id._(_root);
	@override late final Translations$intro$id intro = Translations$intro$id._(_root);
	@override late final Translations$home$id home = Translations$home$id._(_root);
	@override late final Translations$stats$id stats = Translations$stats$id._(_root);
	@override late final Translations$profile$id profile = Translations$profile$id._(_root);
	@override late final Translations$proxies$id proxies = Translations$proxies$id._(_root);
	@override late final Translations$logs$id logs = Translations$logs$id._(_root);
	@override late final Translations$settings$id settings = Translations$settings$id._(_root);
	@override late final Translations$about$id about = Translations$about$id._(_root);
	@override late final Translations$appUpdate$id appUpdate = Translations$appUpdate$id._(_root);
	@override late final Translations$tray$id tray = Translations$tray$id._(_root);
	@override late final Translations$failure$id failure = Translations$failure$id._(_root);
	@override late final Translations$connection$id connection = Translations$connection$id._(_root);
	@override late final Translations$config$id config = Translations$config$id._(_root);
}

// Path: general
class Translations$general$id extends Translations$general$en {
	Translations$general$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'Set Ulang';
	@override late final Translations$general$toggle$id toggle = Translations$general$toggle$id._(_root);
	@override late final Translations$general$state$id state = Translations$general$state$id._(_root);
	@override String get sort => 'Urutkan';
	@override String get sortBy => 'Urut Berdasarkan';
	@override String get addToClipboard => 'Tambah ke Clipboard';
	@override String get notSet => 'Tidak Diatur';
	@override String get agree => 'Setuju';
	@override String get decline => 'Tolak';
	@override String get unknown => 'Tidak Dikenal';
	@override String get hidden => 'Tersembunyi';
	@override String get timeout => 'Waktu habis';
	@override String get clipboardExportSuccessMsg => 'Disalin ke papan klip';
	@override String get showMore => 'Tampilkan Lebih Banyak';
	@override String get showLess => 'Tampilkan Lebih Sedikit';
	@override String get openAppSettings => 'Buka Pengaturan Aplikasi';
	@override String get grantPermission => 'Berikan Izin';
	@override String get underDevelopment => 'Dalam Pengembangan';
	@override String get confirm => 'Konfirmasi';
	@override String get close => 'Tutup';
	@override String get cancel => 'Batal';
	@override String get clipboardEmpty => 'Papan klip kosong';
	@override String get clipboardReadFailed => 'Gagal membaca papan klip';
	@override String get moreOptions => 'Opsi lainnya';
}

// Path: intro
class Translations$intro$id extends Translations$intro$en {
	Translations$intro$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'lanjut berarti setuju dengan '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => 'Mulai';
}

// Path: home
class Translations$home$id extends Translations$home$en {
	Translations$home$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Utama';
	@override String get emptyProfilesMsg => 'Mulai menambahkan langganan profil';
	@override String get noActiveProfileMsg => 'Pilih profil';
	@override late final Translations$home$routingMode$id routingMode = Translations$home$routingMode$id._(_root);
	@override String failedToSwitchMode({required Object error}) => 'Gagal mengganti mode: ${error}';
	@override String get connectionFailedTitle => 'Koneksi Gagal';
	@override String get coreMissingTitle => 'Pustaka Inti Tidak Ditemukan';
	@override String get coreMissingMsg => 'Aplikasi tidak dapat memuat inti jaringannya. Koneksi tidak tersedia. Pasang ulang aplikasi, atau pastikan berkas pustaka inti berada di samping berkas eksekusi.';
	@override String get degradedTitle => 'Tersambung, tetapi tidak ada akses internet';
	@override String get degradedMsg => 'Terowongan aktif tetapi lalu lintas tidak tersalur. Node mungkin mati — coba node lain, atau putuskan koneksi.';
	@override String get degradedRetry => 'Periksa Lagi';
	@override late final Translations$home$egressIp$id egressIp = Translations$home$egressIp$id._(_root);
	@override String get emptyProfilesHint => 'Ketuk tombol di bawah untuk memulai';
	@override String get noActiveProfileTitle => 'Belum ada profil yang dipilih';
}

// Path: stats
class Translations$stats$id extends Translations$stats$en {
	Translations$stats$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Trafik Langsung';
	@override String get trafficTotal => 'Total Trafik';
	@override String get uplink => 'Uplink';
	@override String get downlink => 'Downlink';
	@override String get connection => 'Sambungan';
	@override String get trafficLive => 'Lalu Lintas Langsung';
	@override String get trafficUsage => 'Penggunaan Lalu Lintas';
	@override String get liveSpeed => 'Kecepatan Langsung';
	@override String get speed => 'Kecepatan';
	@override String get totalTransferred => 'Total Ditransfer';
	@override String get sessionTraffic => 'Lalu lintas sesi ini';
	@override String get downloadSpeed => 'Kecepatan unduh';
}

// Path: profile
class Translations$profile$id extends Translations$profile$en {
	Translations$profile$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'Beberapa Profil';
	@override String get detailsPageTitle => 'Profil';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'Nama profil aktif: "${name}".';
	@override String get activeProfileBtnSemanticLabel => 'Tampilkan semua profil.';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Pilih "${name}" sebagai profil aktif.';
	@override late final Translations$profile$subscription$id subscription = Translations$profile$subscription$id._(_root);
	@override late final Translations$profile$sortBy$id sortBy = Translations$profile$sortBy$id._(_root);
	@override late final Translations$profile$add$id add = Translations$profile$add$id._(_root);
	@override late final Translations$profile$update$id update = Translations$profile$update$id._(_root);
	@override late final Translations$profile$share$id share = Translations$profile$share$id._(_root);
	@override late final Translations$profile$edit$id edit = Translations$profile$edit$id._(_root);
	@override late final Translations$profile$delete$id delete = Translations$profile$delete$id._(_root);
	@override late final Translations$profile$save$id save = Translations$profile$save$id._(_root);
	@override late final Translations$profile$detailsForm$id detailsForm = Translations$profile$detailsForm$id._(_root);
	@override late final Translations$profile$actionButtons$id actionButtons = Translations$profile$actionButtons$id._(_root);
	@override late final Translations$profile$details$id details = Translations$profile$details$id._(_root);
	@override late final Translations$profile$overview$id overview = Translations$profile$overview$id._(_root);
	@override String get remoteProfile => 'Profil Jarak Jauh';
	@override String get defaultLocalName => 'Impor lokal';
	@override String get defaultDeepLinkName => 'Impor dari tautan';
	@override String get switchFailedMsg => 'Gagal mengganti profil';
}

// Path: proxies
class Translations$proxies$id extends Translations$proxies$en {
	Translations$proxies$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Proxy';
	@override String get emptyProxiesMsg => 'Tidak ada proxy';
	@override String get delayTestTooltip => 'Test delay';
	@override String get sortTooltip => 'Urut Proxy';
	@override late final Translations$proxies$sortOptions$id sortOptions = Translations$proxies$sortOptions$id._(_root);
	@override String get checkIp => 'Periksa IP';
	@override String get unknownIp => 'IP Tidak Diketahui';
	@override String get autoSelect => 'Pilih Otomatis';
	@override String get autoSelectDescription => 'Sambungkan otomatis ke node tercepat';
	@override String get sortModalTitle => 'Pilih metode pengurutan';
	@override String get activeProxySemanticLabel => 'Jalur Aktif';
	@override late final Translations$proxies$delaySemantics$id delaySemantics = Translations$proxies$delaySemantics$id._(_root);
	@override late final Translations$proxies$ipInfoSemantics$id ipInfoSemantics = Translations$proxies$ipInfoSemantics$id._(_root);
	@override String testingDelayInfo({required Object name}) => 'Menguji jeda untuk: ${name}';
	@override String switchedTo({required Object name}) => 'Beralih ke ${name}';
	@override String get switchFailed => 'Gagal mengganti server. Silakan coba lagi.';
	@override String get testFailed => 'Uji latensi gagal. Silakan coba lagi.';
	@override String get groupsLoading => 'Daftar server masih dimuat. Silakan coba lagi sebentar lagi.';
	@override String get connectBeforeSwitch => 'Sambungkan terlebih dahulu sebelum mengganti jalur';
	@override String startDelayTestForGroups({required Object count}) => 'Uji jeda dimulai untuk ${count} jalur';
	@override String get delayTestBtn => 'Jeda';
	@override String get delayTimeout => 'Habis waktu';
	@override String get connectBeforeTest => 'Sambungkan dulu untuk menguji jeda';
	@override String lineCount({required Object count}) => '${count} jalur';
	@override String get manualSelect => 'Pilih Manual';
	@override String get autoTest => 'Tes Otomatis';
}

// Path: logs
class Translations$logs$id extends Translations$logs$en {
	Translations$logs$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Log';
	@override String get filterHint => 'Filter';
	@override String get allLevelsFilter => 'Semua';
	@override String get shareCoreLogs => 'Bagikan Log Inti';
	@override String get shareAppLogs => 'Bagikan Log Aplikasi';
	@override String get pauseTooltip => 'Jeda';
	@override String get resumeTooltip => 'Lanjut';
	@override String get clearTooltip => 'Bersih';
	@override String get logsCleared => 'Log dihapus';
	@override String get logsCopied => 'Log disalin';
	@override String get logsUnderDevelopment => 'Fitur log sedang dikembangkan';
	@override String get noLogsWhenDisconnected => 'Tidak tersambung, tidak ada log';
	@override String get loadFailed => 'Gagal memuat log';
	@override String get empty => 'Belum ada log';
	@override String get clearFailed => 'Gagal menghapus log';
}

// Path: settings
class Translations$settings$id extends Translations$settings$en {
	Translations$settings$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Setting';
	@override String get requiresRestartMsg => 'Untuk mencoba restart aplikasi';
	@override String get experimental => 'Eksperimen';
	@override String get experimentalMsg => 'Fitur dengan tanda Eksperimen masih dalam pengembangan dan resiko bermasalah.';
	@override late final Translations$settings$general$id general = Translations$settings$general$id._(_root);
	@override late final Translations$settings$advanced$id advanced = Translations$settings$advanced$id._(_root);
	@override late final Translations$settings$network$id network = Translations$settings$network$id._(_root);
	@override late final Translations$settings$geoAssets$id geoAssets = Translations$settings$geoAssets$id._(_root);
	@override String get exportOptions => 'Salin Opsi Anonim ke Papan Klip';
	@override String get exportAllOptions => 'Salin Semua Opsi ke Papan Klip';
	@override String get importOptions => 'Impor Opsi dari Papan Klip';
	@override String get importOptionsMsg => 'Ini akan menimpa semua opsi konfigurasi dengan nilai yang diberikan. Anda yakin?';
	@override late final Translations$settings$backup$id backup = Translations$settings$backup$id._(_root);
	@override String get systemProxyEnabled => 'Proxy sistem diaktifkan';
	@override String get systemProxyDisabled => 'Proxy sistem dinonaktifkan (sambung ulang untuk menerapkan)';
	@override String get adminPrivilegesRequired => 'Memerlukan hak administrator di macOS';
	@override String get portChangeNotice => 'Perubahan port memerlukan sambung ulang agar berlaku';
	@override late final Translations$settings$groups$id groups = Translations$settings$groups$id._(_root);
	@override String get importOptionsInvalid => 'Papan klip tidak berisi JSON pengaturan yang valid';
	@override String get importOptionsNothing => 'Tidak ada pengaturan yang dapat diimpor';
	@override String importOptionsDone({required Object count}) => '${count} pengaturan diimpor';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '${applied} pengaturan diimpor; ${skipped} dilewati karena tidak valid';
}

// Path: about
class Translations$about$id extends Translations$about$en {
	Translations$about$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Tentang';
	@override String get version => 'Versi';
	@override String get sourceCode => 'Code Sumber';
	@override String get telegramChannel => 'Kanal Telegram';
	@override String get checkForUpdate => 'Periksa perbaruan';
	@override String get privacyPolicy => 'Kebijakan Privasi';
	@override String get termsAndConditions => 'Syarat dan Ketentuan Umum';
	@override String get appDescription => 'Klien proxy lintas platform berbasis inti sing-box';
	@override String get openSourceLicenses => 'Lisensi sumber terbuka';
}

// Path: appUpdate
class Translations$appUpdate$id extends Translations$appUpdate$en {
	Translations$appUpdate$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'Sudah menggunakan versi terakhir';
	@override String get dialogTitle => 'Perbaruan Tersedia';
	@override String get updateMsg => 'Versi terbaru ${_root.general.appTitle} tersedia. Ingin di perbarui sekarang?';
	@override String get currentVersionLbl => 'Versi Sekarang';
	@override String get newVersionLbl => 'Versi Baru';
	@override String get updateNowBtnTxt => 'Perbarui Sekarang';
	@override String get laterBtnTxt => 'Nanti';
	@override String get ignoreBtnTxt => 'Lewati';
	@override String get checkFailedMsg => 'Gagal memeriksa pembaruan. Periksa jaringan Anda lalu coba lagi.';
}

// Path: tray
class Translations$tray$id extends Translations$tray$en {
	Translations$tray$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'Dashboard';
	@override String get quit => 'Keluar';
	@override String get open => 'Buka';
	@override late final Translations$tray$status$id status = Translations$tray$status$id._(_root);
	@override String get hide => 'Sembunyikan';
	@override String get proxyModeMenu => 'Mode Proksi';
}

// Path: failure
class Translations$failure$id extends Translations$failure$en {
	Translations$failure$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error Tidak Terduga';
	@override late final Translations$failure$clash$id clash = Translations$failure$clash$id._(_root);
	@override late final Translations$failure$singbox$id singbox = Translations$failure$singbox$id._(_root);
	@override late final Translations$failure$connectivity$id connectivity = Translations$failure$connectivity$id._(_root);
	@override late final Translations$failure$profiles$id profiles = Translations$failure$profiles$id._(_root);
	@override late final Translations$failure$connection$id connection = Translations$failure$connection$id._(_root);
	@override late final Translations$failure$geoAssets$id geoAssets = Translations$failure$geoAssets$id._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$id extends Translations$connection$en {
	Translations$connection$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'Ketuk untuk Sambung';
	@override String get connecting => 'Sambungkan';
	@override String get disconnecting => 'Putus Sambungan';
	@override String get connected => 'Tersambung';
	@override String get experimentalNotice => 'Fitur Experimental digunakan';
	@override String get experimentalNoticeMsg => 'Kamu telah mengaktifkan fitur experimental yang mungkin mempengaruhi kualitas sambungan dan error tidak terduga. Kamu tetap bisa merubah atau set ulang opsi dari Halaman Konfigurasi';
	@override String get disableExperimentalNotice => 'Jangan tampil lagi';
	@override String get reconnect => 'Sambungkan Ulang';
	@override String get connectAnyWay => 'Tetap sambungkan';
	@override String get reconnectMsg => 'Menyambungkan ulang untuk menerapkan perubahan...';
	@override String get staleSystemProxyCleaned => 'Pengaturan proxy sistem yang tertinggal dari keluar tidak normal telah dibersihkan';
}

// Path: config
class Translations$config$id extends Translations$config$en {
	Translations$config$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'Set Ulang Opsi';
	@override String get serviceMode => 'Sambung ulang agar perubahan diterapkan';
	@override late final Translations$config$serviceModes$id serviceModes = Translations$config$serviceModes$id._(_root);
	@override late final Translations$config$section$id section = Translations$config$section$id._(_root);
	@override late final Translations$config$warpConsent$id warpConsent = Translations$config$warpConsent$id._(_root);
	@override String get pageTitle => 'Opsi Konfig';
	@override String get logLevel => 'Log Level';
	@override String get resolveDestination => 'Resolve Destination';
	@override String get ipv6Mode => 'IPv6 Route';
	@override late final Translations$config$ipv6Modes$id ipv6Modes = Translations$config$ipv6Modes$id._(_root);
	@override String get remoteDnsAddress => 'Remote DNS';
	@override String get remoteDnsDomainStrategy => 'Remote DNS Domain Strategy';
	@override String get directDnsAddress => 'Direct DNS';
	@override String get directDnsDomainStrategy => 'Direct DNS Domain Strategy';
	@override String get mixedPort => 'Mixed Port';
	@override String get localDnsPort => 'DNS Port Lokal';
	@override String get allowConnectionFromLan => 'Perbolehkan Sambungan LAN';
	@override String get tunImplementation => 'Implementasi TUN';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'URL Tes Sambungan';
	@override String get urlTestInterval => 'URL Test Interval';
	@override String get enableClashApi => 'Aktifkan Clash API';
	@override String get clashApiPort => 'Clash API Port';
	@override String get enableTun => 'Aktifkan TUN';
	@override String get setSystemProxy => 'Atur Sistem Proxy';
	@override String get enableDnsRouting => 'Aktifkan DNS Routing';
	@override String get enableFakeDns => 'Aktifkan DNS Palsu';
	@override String get bypassLan => 'Bypass LAN';
	@override String get strictRoute => 'Strict Route';
	@override String get enableTlsFragment => 'Aktifkan TLS Fragment';
	@override String get tlsFragmentSize => 'TLS Fragment Size';
	@override String get tlsFragmentSleep => 'TLS Fragment Sleep';
	@override String get enableTlsMixedSniCase => 'Aktifkan TLS Mixed SNI Case';
	@override String get enableTlsPadding => 'Aktifkan TLS Padding';
	@override String get tlsPaddingSize => 'TLS Padding';
	@override String get enableMux => 'Enable Mux';
	@override String get muxProtocol => 'Mux Protocol';
	@override String get muxMaxStreams => 'Max Concurrent Streams';
	@override String get enableWarp => 'Enable WARP';
	@override String get setUpWarp => 'Siapkan WARP';
	@override String get warpNotConfigured => 'Belum dikonfigurasi';
	@override String get warpDetourMode => 'Detour Mode';
	@override late final Translations$config$warpDetourModes$id warpDetourModes = Translations$config$warpDetourModes$id._(_root);
	@override String get warpLicenseKey => 'License Key';
	@override String get warpCleanIp => 'Clean IP';
	@override String get warpPort => 'Port';
	@override String get warpNoise => 'Noise';
	@override String get quickSettings => 'Pengaturan Cepat';
	@override String get quickSettingsSubtitle => 'Sesuaikan pengalaman koneksi Anda';
	@override String get setupWarp => 'Siapkan WARP';
	@override String get allOptions => 'Semua Opsi Konfigurasi';
	@override String get allAdvancedOptions => 'Semua Opsi Lanjutan';
	@override late final Translations$config$shortServiceModes$id shortServiceModes = Translations$config$shortServiceModes$id._(_root);
	@override String get generateWarpConfig => 'Buat Konfigurasi WARP';
	@override String get missingWarpConfig => 'Konfigurasi WARP Tidak Ada';
	@override String get warpConfigGenerated => 'Konfigurasi WARP Dibuat';
	@override String get blockAds => 'Blokir Iklan';
	@override String get tproxyPort => 'Port Jalur Transparan';
	@override String get warpNoiseSize => 'Ukuran Noise';
	@override String get warpNoiseMode => 'Mode Noise';
	@override String get warpNoiseDelay => 'Penundaan Noise';
	@override String get desktopProxyScopeNotice => 'Di desktop, hanya aplikasi yang mematuhi proxy sistem yang dialihkan melalui terowongan. Perangkat lunak yang mengabaikannya (beberapa game, alat baris perintah, aplikasi dengan pengaturan proxy sendiri) terhubung langsung dan membocorkan IP asli Anda.';
	@override String get serviceModeIosVpnOnly => 'iOS hanya mendukung mode VPN';
	@override String get warpGenerating => 'Membuat konfigurasi WARP…';
	@override String get warpConfigFailed => 'Gagal membuat konfigurasi WARP. Coba lagi nanti.';
	@override String get portRangeError => 'Port harus antara 1024 dan 65535';
	@override String get dnsEmptyError => 'Alamat DNS tidak boleh kosong';
	@override String get rangeFormatError => 'Masukkan angka atau rentang, mis. 10-30';
	@override String get urlSchemeError => 'URL harus diawali http:// atau https://';
	@override String get manageRuleAssets => 'Kelola set aturan';
}

// Path: general.toggle
class Translations$general$toggle$id extends Translations$general$toggle$en {
	Translations$general$toggle$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'Mengaktifkan';
	@override String get disabled => 'Menonaktifkan';
}

// Path: general.state
class Translations$general$state$id extends Translations$general$state$en {
	Translations$general$state$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Menonaktifkan';
}

// Path: home.routingMode
class Translations$home$routingMode$id extends Translations$home$routingMode$en {
	Translations$home$routingMode$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get global => 'Proxy Global';
	@override String get smart => 'Perutean Cerdas';
}

// Path: home.egressIp
class Translations$home$egressIp$id extends Translations$home$egressIp$en {
	Translations$home$egressIp$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get label => 'IP keluar';
	@override String get notConnected => 'Hubungkan untuk melihat IP keluar';
	@override String get tapToCheck => 'Ketuk untuk memeriksa IP keluar';
	@override String get checking => 'Memeriksa…';
	@override String get failedRetry => 'Pemeriksaan gagal, ketuk untuk mencoba lagi';
}

// Path: profile.subscription
class Translations$profile$subscription$id extends Translations$profile$subscription$en {
	Translations$profile$subscription$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Trafik';
	@override String updatedTimeAgo({required Object timeago}) => '${timeago} diperbarui';
	@override String remainingDuration({required Object duration}) => 'Tersisa ${duration} hari lagi';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed}/${total} trafik terpakai';
	@override String get expired => 'Kadaluarsa';
	@override String get noTraffic => 'Kuota Habis';
	@override String get upload => 'Unggah';
	@override String get download => 'Unduh';
	@override String get total => 'Total Lalu Lintas';
	@override String get expireDate => 'Tanggal Kedaluwarsa';
}

// Path: profile.sortBy
class Translations$profile$sortBy$id extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'Baru diperbaharui';
	@override String get name => 'Alphabetikal';
}

// Path: profile.add
class Translations$profile$add$id extends Translations$profile$add$en {
	Translations$profile$add$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Profil Baru';
	@override String get shortBtnTxt => 'Profil Baru';
	@override String get fromClipboard => 'Tambah dari Clipboard';
	@override String get scanQr => 'Pindai QR';
	@override late final Translations$profile$add$qrScanner$id qrScanner = Translations$profile$add$qrScanner$id._(_root);
	@override String get manually => 'Isian Manual';
	@override String get addingProfileMsg => 'Tambahkan Profil';
	@override String get failureMsg => 'Gagal tambahkan profil';
	@override String get modalSubtitle => 'Pilih cara menambahkan berkas konfigurasi';
	@override String get manuallyDescription => 'Masukkan konfigurasi server secara manual';
	@override String get addWarp => 'Tambah WARP';
	@override String get warpDescription => 'Akselerasi gratis dengan Cloudflare WARP';
	@override String get addingWarpMsg => 'Mohon tunggu, kami sedang mendaftarkan WARP.';
	@override String importedNamed({required Object name}) => 'Langganan diimpor: ${name}';
	@override String get clipboardEmpty => 'Papan klip kosong, tidak ada yang bisa diimpor';
	@override String get deepLinkMissingUrl => 'Tautan tidak berisi alamat langganan';
	@override String get successMsg => 'Profil ditambahkan';
	@override String get nameAutoHint => 'Terdeteksi otomatis (opsional)';
}

// Path: profile.update
class Translations$profile$update$id extends Translations$profile$update$en {
	Translations$profile$update$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Perbarui';
	@override String get tooltip => 'Profil terbaru';
	@override String get updateSubscriptions => 'Perbarui Langganan';
	@override String get failureMsg => 'Gagal perbarui profil';
	@override String get successMsg => 'Sukses perbarui profil';
	@override String namedFailureMsg({required Object name}) => 'Gagal perbarui "${name}"';
	@override String namedSuccessMsg({required Object name}) => 'Sukses perbarui "${name}"';
}

// Path: profile.share
class Translations$profile$share$id extends Translations$profile$share$en {
	Translations$profile$share$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Bagi';
	@override String get exportToClipboardSuccess => 'Taruh ke clipboard';
	@override String get exportSubLinkToClipboard => 'Taruh link langganan ke clipboard';
	@override String get subLinkQrCode => 'Link Langganan QR';
	@override String get exportConfigToClipboard => 'Taruh konfigurasi ke clipboard';
	@override String get exportConfigToClipboardSuccess => 'Salin konfigurasi ke clipboard';
	@override String get shareLink => 'Bagikan Tautan';
	@override String get subscriptionLinkCopied => 'Tautan langganan disalin';
	@override String get configCopied => 'Konfigurasi disalin';
	@override String get copyFailed => 'Gagal menyalin';
}

// Path: profile.edit
class Translations$profile$edit$id extends Translations$profile$edit$en {
	Translations$profile$edit$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Ubah';
	@override String get selectActiveTxt => 'Pilih profil aktif';
}

// Path: profile.delete
class Translations$profile$delete$id extends Translations$profile$delete$en {
	Translations$profile$delete$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Hapus';
	@override String get confirmationMsg => 'Hapus profil permanen?';
	@override String get successMsg => 'Sukses hapus profil';
	@override String get confirmTitle => 'Hapus profil';
	@override String namedConfirmMsg({required Object name}) => 'Hapus "${name}"? Tindakan ini tidak dapat dibatalkan.';
}

// Path: profile.save
class Translations$profile$save$id extends Translations$profile$save$en {
	Translations$profile$save$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Simpan';
	@override String get successMsg => 'Sukses simpan profil';
	@override String get failureMsg => 'Gagal simpan profil';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$id extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'Nama';
	@override String get nameHint => 'Nama Profil';
	@override String get urlLabel => 'URL';
	@override String get urlHint => 'URL Lengkap';
	@override String get emptyNameMsg => 'Nama diwajibkan';
	@override String get invalidUrlMsg => 'URL Salah';
	@override String get lastUpdate => 'Terakhir diperbarui';
	@override String get updateInterval => 'Perbarui otomatis';
	@override String get updateIntervalDialogTitle => 'Interval perbarui otomatis (dalam jam)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'Mati';
	@override String updateIntervalHours({required Object hours}) => '${hours} jam';
	@override String updateIntervalDays({required Object days}) => '${days} hari';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$id extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get add => 'Tambah';
	@override String get updateAll => 'Perbarui Semua';
	@override String get sort => 'Urutkan';
	@override String get copyConfigSuccess => 'Konfigurasi disalin';
	@override String get editConfig => 'Edit Konfigurasi';
}

// Path: profile.details
class Translations$profile$details$id extends Translations$profile$details$en {
	Translations$profile$details$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'Informasi Dasar';
	@override String get subscriptionStatus => 'Status Langganan';
	@override String get options => 'Opsi';
	@override String get updateNow => 'Perbarui Sekarang';
	@override String get updateNowDescription => 'Ambil konfigurasi terbaru dari server';
	@override String get expireDate => 'Tanggal Kedaluwarsa';
	@override String get unlimited => 'Tanpa Batas';
}

// Path: profile.overview
class Translations$profile$overview$id extends Translations$profile$overview$en {
	Translations$profile$overview$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'Sedang Digunakan';
	@override String remainingDays({required Object days}) => 'Sisa ${days} hari';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$id extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'Awal';
	@override String get name => 'Alfabetikal';
	@override String get delay => 'Berdasarkan Delay';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$id extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'Jeda: ${delay}ms';
	@override String get timeout => 'Waktu Uji Jeda Habis';
	@override String get testing => 'Jeda: Menguji...';
	@override String get untested => 'Jeda: Belum diuji';
	@override String stale({required Object delay}) => 'Jeda: ${delay}ms (hasil sebelumnya)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$id extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get address => 'Alamat IP';
	@override String get country => 'Negara';
}

// Path: settings.general
class Translations$settings$general$id extends Translations$settings$general$en {
	Translations$settings$general$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Umum';
	@override String get locale => 'Bahasa';
	@override String get region => 'Region';
	@override String get regionMsg => 'Bantu tetapkan opsi standar untuk melewati alamat lokal';
	@override late final Translations$settings$general$regions$id regions = Translations$settings$general$regions$id._(_root);
	@override String get themeMode => 'Jenis Tema';
	@override late final Translations$settings$general$themeModes$id themeModes = Translations$settings$general$themeModes$id._(_root);
	@override String get enableAnalytics => 'Mengaktifkan Analitik';
	@override String get enableAnalyticsMsg => 'Beri izin untuk mengumpulkan analisis dan mengirim laporan kegagalan untuk meningkatkan aplikasi';
	@override String get autoStart => 'Mulai saat Login';
	@override String get silentStart => 'Mulai Minimalkan';
	@override String get openWorkingDir => 'Buka Direktori Kerja';
	@override String get ignoreBatteryOptimizations => 'Menonaktifkan Optimisasi Baterai';
	@override String get ignoreBatteryOptimizationsMsg => 'Hapus batasan untuk performa VPN yang optimal';
	@override String get dynamicNotification => 'Tampilkan Kecepatan di notifikasi';
	@override String get hapticFeedback => 'Umpan Balik Haptik';
	@override String get autoIpCheck => 'Periksa IP Koneksi Otomatis';
	@override late final Translations$settings$general$batteryOptimizationStatus$id batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$id._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$id extends Translations$settings$advanced$en {
	Translations$settings$advanced$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Mode Lanjut';
	@override String get debugMode => 'Mode Debug';
	@override String get debugModeMsg => 'Restart aplikasi untuk menerapkan perubahan';
	@override String get memoryLimit => 'Limit Memori';
	@override String get memoryLimitMsg => 'Aktifkan jika kamu mendapatkan error habis memori atau error aplikasi yang sering';
	@override String get resetTunnel => 'Set ulang profil VPN';
	@override String get resetTunnelSuccess => 'Profil VPN telah direset';
}

// Path: settings.network
class Translations$settings$network$id extends Translations$settings$network$en {
	Translations$settings$network$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'Per-app Proxy';
	@override late final Translations$settings$network$perAppProxyModes$id perAppProxyModes = Translations$settings$network$perAppProxyModes$id._(_root);
	@override String get showSystemApps => 'Tampil aplikasi sistem';
	@override String get hideSystemApps => 'Sembunyikan aplikasi sistem';
	@override String get clearSelection => 'Bersihkan seleksi';
	@override String get perAppProxyLoadFailedMsg => 'Gagal memuat daftar aplikasi';
	@override String get perAppProxyRetry => 'Coba Lagi';
	@override String get perAppProxyEmptyMsg => 'Tidak ada hasil';
	@override String get perAppProxyAndroidOnlyMsg => 'Mode jalur per aplikasi hanya didukung di Android';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$id extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Rute Aset';
	@override String get geoip => 'Geoip';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => 'Versi ${version}';
	@override String get fileMissing => 'File Hilang';
	@override String get update => 'Perbarui';
	@override String get download => 'Unduh';
	@override String get failureMsg => 'Gagal perbarui aset';
	@override String get successMsg => 'Sukses perbarui aset';
	@override String get addRecommended => 'Tambah aset rekomendasi';
	@override String get missingGeoAssetsMsg => 'Routing aset terpilih filenya hilang. Silahkan unduh atau pilih dari yang ada';
}

// Path: settings.backup
class Translations$settings$backup$id extends Translations$settings$backup$en {
	Translations$settings$backup$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'Impor Cadangan';
	@override String get importConfirmMsg => 'Ini mengganti langganan Anda dengan langganan dari cadangan dan menerapkan pengaturannya. Snapshot data saat ini disimpan terlebih dahulu dan dipulihkan otomatis jika impor gagal.';
	@override String importRemovesMsg({required Object count}) => '${count} langganan di perangkat ini tidak ada di cadangan dan akan dihapus.';
	@override String reportImported({required Object profiles, required Object settings}) => '${profiles} langganan dan ${settings} pengaturan diimpor.';
	@override String reportDropped({required Object count}) => '${count} langganan dalam cadangan dilewati karena datanya tidak valid.';
	@override String reportSettingsSkipped({required Object count}) => '${count} pengaturan dilewati; nilai Anda saat ini dipertahankan.';
	@override String get reportWarpOff => 'Impor mematikan WARP. Aktifkan kembali di perangkat ini.';
	@override String reportBackfill({required Object count}) => '${count} langganan akan diunduh di latar belakang.';
	@override String get errInvalidFile => 'Ini bukan file cadangan ClashMiao yang valid.';
	@override String get errUnsupportedVersion => 'Format cadangan ini tidak didukung.';
	@override String get errNewerSchema => 'Cadangan ini dibuat oleh aplikasi versi yang lebih baru. Perbarui aplikasi terlebih dahulu.';
	@override String get errNoUsableProfiles => 'Tidak ada langganan dalam cadangan ini yang dapat diimpor.';
	@override String get errSnapshotFailed => 'Snapshot data saat ini tidak dapat disimpan, sehingga tidak ada yang diubah.';
	@override String get errUnresolvedPrevious => 'Impor sebelumnya terhenti dan belum dapat dibatalkan. Tidak ada yang diubah. Mulai ulang aplikasi lalu coba lagi.';
	@override String get errRolledBack => 'Impor gagal. Data Anda sebelumnya telah dipulihkan.';
	@override String errNotRolledBack({required Object path}) => 'Impor gagal dan pemulihan otomatis belum selesai. Mulai ulang aplikasi untuk mencobanya lagi. Snapshot disimpan di ${path}.';
	@override String get errFailed => 'Impor gagal.';
	@override String get errBusy => 'Impor lain sedang berjalan. Tunggu sampai selesai.';
	@override String get recoveryFailedTitle => 'Pemulihan otomatis belum selesai';
	@override String get recoveryFailedMsg => 'Impor cadangan terakhir terhenti dan aplikasi tidak dapat mengembalikan data Anda ke keadaan sebelumnya. Sebagian data mungkin hanya terimpor sebagian. Coba pemulihan otomatis lagi sekarang.';
	@override String get recoveryUnrecoverableTitle => 'Impor yang terhenti tidak dapat dibatalkan';
	@override String get recoveryUnrecoverableMsg => 'Impor cadangan terakhir terhenti, tetapi snapshot-nya hilang atau tidak dapat dibaca sehingga tidak dapat dibatalkan. Periksa langganan dan pengaturan Anda.';
	@override String get recoveryRetry => 'Coba lagi';
	@override String get recoveryClose => 'Tutup';
	@override String get recoveryRetried => 'Data Anda dipulihkan ke keadaan sebelum impor yang terhenti.';
	@override String get exportAction => 'Ekspor cadangan';
	@override String get importAction => 'Impor cadangan';
	@override String get exportFailed => 'Gagal mengekspor cadangan';
	@override String get shareText => 'Cadangan ClashMiao';
}

// Path: settings.groups
class Translations$settings$groups$id extends Translations$settings$groups$en {
	Translations$settings$groups$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get general => 'Umum';
	@override String get connection => 'Koneksi';
	@override String get privacy => 'Privasi';
}

// Path: tray.status
class Translations$tray$status$id extends Translations$tray$status$en {
	Translations$tray$status$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get connect => 'Sambung';
	@override String get connecting => 'Menyambungkan';
	@override String get disconnect => 'Putus';
	@override String get disconnecting => 'Memutuskan';
}

// Path: failure.clash
class Translations$failure$clash$id extends Translations$failure$clash$en {
	Translations$failure$clash$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error Tidak Terduga';
	@override String core({required Object reason}) => 'Clash Error ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$id extends Translations$failure$singbox$en {
	Translations$failure$singbox$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Servis Error Tidak Terduga';
	@override String get serviceNotRunning => 'Servis tidak berjalan';
	@override String get missingPrivilege => 'Hak Akses Hilang';
	@override String get missingPrivilegeMsg => 'Mode VPN membutuhkan hak akses administrator. Antara buka ulang aplikasi sebagai administrator atau rubah mode servis';
	@override String get missingGeoAssets => 'Geo Aset Hilang';
	@override String get missingGeoAssetsMsg => 'Geo aset hilang. Pertimbangkan merubah aset aktif atau unduh yang sudah dipilih di seting';
	@override String get invalidConfigOptions => 'Pilihan konfigurasi tidak valid';
	@override String get invalidConfig => 'Konfigurasi tidak valid';
	@override String get create => 'Pembuatan Servis Error';
	@override String get start => 'Jalankan Servis Error';
	@override String get coreLibraryMissing => 'Pustaka Inti Belum Terpasang';
	@override String get startTimeout => 'Waktu Mulai Layanan Habis';
	@override String get kernelUnresponsive => 'Inti tidak merespons. Coba lagi atau mulai ulang aplikasi.';
	@override String get kernelExited => 'Inti berhenti secara tak terduga';
}

// Path: failure.connectivity
class Translations$failure$connectivity$id extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Kegagalan tidak terduga';
	@override String get missingVpnPermission => 'Izin VPN Hilang';
	@override String get missingNotificationPermission => 'Izin Notifikasi Hilang';
	@override String get core => 'Error Inti';
	@override String get networkUnavailable => 'Jaringan Tidak Tersedia';
	@override String get nativeUnresponsive => 'Kehilangan kontak dengan layanan latar belakang. Coba lagi.';
}

// Path: failure.profiles
class Translations$failure$profiles$id extends Translations$failure$profiles$en {
	Translations$failure$profiles$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error Tidak Terduga';
	@override String get notFound => 'Profil tidak ditemukan';
	@override String get invalidConfig => 'Konfigurasi tidak valid';
	@override String get invalidUrl => 'URL tidak valid';
	@override String get noActive => 'Tidak Ada Profil Aktif';
	@override String get readOnlyUpgrade => 'Perbarui aplikasi sebelum mengubah langganan';
}

// Path: failure.connection
class Translations$failure$connection$id extends Translations$failure$connection$en {
	Translations$failure$connection$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Sambungan error tidak terduga';
	@override String get timeout => 'Waktu Sambungan Habis';
	@override String get badResponse => 'Response Rusak';
	@override String get connectionError => 'Sambungan Error';
	@override String get badCertificate => 'Sertifikat Rusak';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$id extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error Tidak Terduga';
	@override String get notUpdate => 'Perbaruan tidak tersedia';
	@override String get activeNotFound => 'Geo Aset Aktif tidak ditemukan';
}

// Path: config.serviceModes
class Translations$config$serviceModes$id extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Proxy';
	@override String get systemProxy => 'Sistem Proxy';
	@override String get tun => 'VPN';
	@override String get tunService => 'Layanan VPN';
}

// Path: config.section
class Translations$config$section$id extends Translations$config$section$en {
	Translations$config$section$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get route => 'Opsi Route';
	@override String get dns => 'Opsi DNS';
	@override String get inbound => 'Opsi Inbound';
	@override String get mux => 'Multiplexer';
	@override String get outbound => 'Opsi Outbound';
	@override String get tlsTricks => 'TLS Tricks';
	@override String get warp => 'Opsi WARP';
	@override String get misc => 'Opsi Misc';
}

// Path: config.warpConsent
class Translations$config$warpConsent$id extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get title => 'Persetujuan Cloudflare WARP';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP adalah WireGuard VPN Provider gratis. Dengan mengaktifkan opsi/pilihan ini berarti kamu setuju pada Cloudflare WARP\'s '),
		tos('Terms of Service'),
		const TextSpan(text: ' dan '),
		privacy('Privacy Policy'),
		const TextSpan(text: '.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$id extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Nonaktifkan';
	@override String get enable => 'Aktifkan';
	@override String get prefer => 'Prefer';
	@override String get only => 'Exclusive';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$id extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get inbound => 'Detour WARP through proxies';
	@override String get outbound => 'Detour proxies through WARP';
	@override String get proxyOverWarp => 'Alihkan Jalur Melalui WARP';
	@override String get warpOverProxy => 'Alihkan WARP Melalui Jalur';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$id extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Hanya Jalur';
	@override String get systemProxy => 'Jalur Sistem';
	@override String get tun => 'VPN';
	@override String get tunService => 'Layanan VPN';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$id extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'Izin ditolak';
	@override String get unexpectedError => 'Terjadi masalah';
	@override String get torchSemanticLabel => 'Lampu Flash';
	@override String get facingSemanticLabel => 'Hadap Kamera';
	@override String get permissionRequest => 'Izin kamera untuk memindai Kode QR';
}

// Path: settings.general.regions
class Translations$settings$general$regions$id extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get ir => 'İran (ir)';
	@override String get cn => 'Çin (cn)';
	@override String get ru => 'Russia (ru)';
	@override String get af => 'Afghanistan (af)';
	@override String get id => 'Indonesia (id)';
	@override String get other => 'Lainnya';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$id extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get system => 'Ikut Tema Sistem';
	@override String get dark => 'Tema Gelap';
	@override String get light => 'Tema Cerah';
	@override String get black => 'Tema Hitam';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$id extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'Dikecualikan';
	@override String get notExempted => 'Tidak Dikecualikan';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$id extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$id._(TranslationsId root) : this._root = root, super.internal(root);

	final TranslationsId _root; // ignore: unused_field

	// Translations
	@override String get off => 'Semua';
	@override String get offMsg => 'Proxy semua applikasi';
	@override String get include => 'Proxy';
	@override String get includeMsg => 'Proxy untuk aplikasi terpilih';
	@override String get exclude => 'Bypass';
	@override String get excludeMsg => 'Tidak proxy untuk aplikasi terpilih';
}

/// The flat map containing all translations for locale <id>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsId {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Set Ulang',
			'general.toggle.enabled' => 'Mengaktifkan',
			'general.toggle.disabled' => 'Menonaktifkan',
			'general.state.disable' => 'Menonaktifkan',
			'general.sort' => 'Urutkan',
			'general.sortBy' => 'Urut Berdasarkan',
			'general.addToClipboard' => 'Tambah ke Clipboard',
			'general.notSet' => 'Tidak Diatur',
			'general.agree' => 'Setuju',
			'general.decline' => 'Tolak',
			'general.unknown' => 'Tidak Dikenal',
			'general.hidden' => 'Tersembunyi',
			'general.timeout' => 'Waktu habis',
			'general.clipboardExportSuccessMsg' => 'Disalin ke papan klip',
			'general.showMore' => 'Tampilkan Lebih Banyak',
			'general.showLess' => 'Tampilkan Lebih Sedikit',
			'general.openAppSettings' => 'Buka Pengaturan Aplikasi',
			'general.grantPermission' => 'Berikan Izin',
			'general.underDevelopment' => 'Dalam Pengembangan',
			'general.confirm' => 'Konfirmasi',
			'general.close' => 'Tutup',
			'general.cancel' => 'Batal',
			'general.clipboardEmpty' => 'Papan klip kosong',
			'general.clipboardReadFailed' => 'Gagal membaca papan klip',
			'general.moreOptions' => 'Opsi lainnya',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'lanjut berarti setuju dengan '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => 'Mulai',
			'home.pageTitle' => 'Utama',
			'home.emptyProfilesMsg' => 'Mulai menambahkan langganan profil',
			'home.noActiveProfileMsg' => 'Pilih profil',
			'home.routingMode.global' => 'Proxy Global',
			'home.routingMode.smart' => 'Perutean Cerdas',
			'home.failedToSwitchMode' => ({required Object error}) => 'Gagal mengganti mode: ${error}',
			'home.connectionFailedTitle' => 'Koneksi Gagal',
			'home.coreMissingTitle' => 'Pustaka Inti Tidak Ditemukan',
			'home.coreMissingMsg' => 'Aplikasi tidak dapat memuat inti jaringannya. Koneksi tidak tersedia. Pasang ulang aplikasi, atau pastikan berkas pustaka inti berada di samping berkas eksekusi.',
			'home.degradedTitle' => 'Tersambung, tetapi tidak ada akses internet',
			'home.degradedMsg' => 'Terowongan aktif tetapi lalu lintas tidak tersalur. Node mungkin mati — coba node lain, atau putuskan koneksi.',
			'home.degradedRetry' => 'Periksa Lagi',
			'home.egressIp.label' => 'IP keluar',
			'home.egressIp.notConnected' => 'Hubungkan untuk melihat IP keluar',
			'home.egressIp.tapToCheck' => 'Ketuk untuk memeriksa IP keluar',
			'home.egressIp.checking' => 'Memeriksa…',
			'home.egressIp.failedRetry' => 'Pemeriksaan gagal, ketuk untuk mencoba lagi',
			'home.emptyProfilesHint' => 'Ketuk tombol di bawah untuk memulai',
			'home.noActiveProfileTitle' => 'Belum ada profil yang dipilih',
			'stats.traffic' => 'Trafik Langsung',
			'stats.trafficTotal' => 'Total Trafik',
			'stats.uplink' => 'Uplink',
			'stats.downlink' => 'Downlink',
			'stats.connection' => 'Sambungan',
			'stats.trafficLive' => 'Lalu Lintas Langsung',
			'stats.trafficUsage' => 'Penggunaan Lalu Lintas',
			'stats.liveSpeed' => 'Kecepatan Langsung',
			'stats.speed' => 'Kecepatan',
			'stats.totalTransferred' => 'Total Ditransfer',
			'stats.sessionTraffic' => 'Lalu lintas sesi ini',
			'stats.downloadSpeed' => 'Kecepatan unduh',
			'profile.overviewPageTitle' => 'Beberapa Profil',
			'profile.detailsPageTitle' => 'Profil',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Nama profil aktif: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'Tampilkan semua profil.',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Pilih "${name}" sebagai profil aktif.',
			'profile.subscription.traffic' => 'Trafik',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => '${timeago} diperbarui',
			'profile.subscription.remainingDuration' => ({required Object duration}) => 'Tersisa ${duration} hari lagi',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed}/${total} trafik terpakai',
			'profile.subscription.expired' => 'Kadaluarsa',
			'profile.subscription.noTraffic' => 'Kuota Habis',
			'profile.subscription.upload' => 'Unggah',
			'profile.subscription.download' => 'Unduh',
			'profile.subscription.total' => 'Total Lalu Lintas',
			'profile.subscription.expireDate' => 'Tanggal Kedaluwarsa',
			'profile.sortBy.lastUpdate' => 'Baru diperbaharui',
			'profile.sortBy.name' => 'Alphabetikal',
			'profile.add.buttonText' => 'Profil Baru',
			'profile.add.shortBtnTxt' => 'Profil Baru',
			'profile.add.fromClipboard' => 'Tambah dari Clipboard',
			'profile.add.scanQr' => 'Pindai QR',
			'profile.add.qrScanner.permissionDeniedError' => 'Izin ditolak',
			'profile.add.qrScanner.unexpectedError' => 'Terjadi masalah',
			'profile.add.qrScanner.torchSemanticLabel' => 'Lampu Flash',
			'profile.add.qrScanner.facingSemanticLabel' => 'Hadap Kamera',
			'profile.add.qrScanner.permissionRequest' => 'Izin kamera untuk memindai Kode QR',
			'profile.add.manually' => 'Isian Manual',
			'profile.add.addingProfileMsg' => 'Tambahkan Profil',
			'profile.add.failureMsg' => 'Gagal tambahkan profil',
			'profile.add.modalSubtitle' => 'Pilih cara menambahkan berkas konfigurasi',
			'profile.add.manuallyDescription' => 'Masukkan konfigurasi server secara manual',
			'profile.add.addWarp' => 'Tambah WARP',
			'profile.add.warpDescription' => 'Akselerasi gratis dengan Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'Mohon tunggu, kami sedang mendaftarkan WARP.',
			'profile.add.importedNamed' => ({required Object name}) => 'Langganan diimpor: ${name}',
			'profile.add.clipboardEmpty' => 'Papan klip kosong, tidak ada yang bisa diimpor',
			'profile.add.deepLinkMissingUrl' => 'Tautan tidak berisi alamat langganan',
			'profile.add.successMsg' => 'Profil ditambahkan',
			'profile.add.nameAutoHint' => 'Terdeteksi otomatis (opsional)',
			'profile.update.buttonTxt' => 'Perbarui',
			'profile.update.tooltip' => 'Profil terbaru',
			'profile.update.updateSubscriptions' => 'Perbarui Langganan',
			'profile.update.failureMsg' => 'Gagal perbarui profil',
			'profile.update.successMsg' => 'Sukses perbarui profil',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'Gagal perbarui "${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => 'Sukses perbarui "${name}"',
			'profile.share.buttonText' => 'Bagi',
			'profile.share.exportToClipboardSuccess' => 'Taruh ke clipboard',
			'profile.share.exportSubLinkToClipboard' => 'Taruh link langganan ke clipboard',
			'profile.share.subLinkQrCode' => 'Link Langganan QR',
			'profile.share.exportConfigToClipboard' => 'Taruh konfigurasi ke clipboard',
			'profile.share.exportConfigToClipboardSuccess' => 'Salin konfigurasi ke clipboard',
			'profile.share.shareLink' => 'Bagikan Tautan',
			'profile.share.subscriptionLinkCopied' => 'Tautan langganan disalin',
			'profile.share.configCopied' => 'Konfigurasi disalin',
			'profile.share.copyFailed' => 'Gagal menyalin',
			'profile.edit.buttonTxt' => 'Ubah',
			'profile.edit.selectActiveTxt' => 'Pilih profil aktif',
			'profile.delete.buttonTxt' => 'Hapus',
			'profile.delete.confirmationMsg' => 'Hapus profil permanen?',
			'profile.delete.successMsg' => 'Sukses hapus profil',
			'profile.delete.confirmTitle' => 'Hapus profil',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => 'Hapus "${name}"? Tindakan ini tidak dapat dibatalkan.',
			'profile.save.buttonText' => 'Simpan',
			'profile.save.successMsg' => 'Sukses simpan profil',
			'profile.save.failureMsg' => 'Gagal simpan profil',
			'profile.detailsForm.nameLabel' => 'Nama',
			'profile.detailsForm.nameHint' => 'Nama Profil',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'URL Lengkap',
			'profile.detailsForm.emptyNameMsg' => 'Nama diwajibkan',
			'profile.detailsForm.invalidUrlMsg' => 'URL Salah',
			'profile.detailsForm.lastUpdate' => 'Terakhir diperbarui',
			'profile.detailsForm.updateInterval' => 'Perbarui otomatis',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Interval perbarui otomatis (dalam jam)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Mati',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} jam',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} hari',
			'profile.actionButtons.add' => 'Tambah',
			'profile.actionButtons.updateAll' => 'Perbarui Semua',
			'profile.actionButtons.sort' => 'Urutkan',
			'profile.actionButtons.copyConfigSuccess' => 'Konfigurasi disalin',
			'profile.actionButtons.editConfig' => 'Edit Konfigurasi',
			'profile.details.basicInfo' => 'Informasi Dasar',
			'profile.details.subscriptionStatus' => 'Status Langganan',
			'profile.details.options' => 'Opsi',
			'profile.details.updateNow' => 'Perbarui Sekarang',
			'profile.details.updateNowDescription' => 'Ambil konfigurasi terbaru dari server',
			'profile.details.expireDate' => 'Tanggal Kedaluwarsa',
			'profile.details.unlimited' => 'Tanpa Batas',
			'profile.overview.currentlyUsing' => 'Sedang Digunakan',
			'profile.overview.remainingDays' => ({required Object days}) => 'Sisa ${days} hari',
			'profile.remoteProfile' => 'Profil Jarak Jauh',
			'profile.defaultLocalName' => 'Impor lokal',
			'profile.defaultDeepLinkName' => 'Impor dari tautan',
			'profile.switchFailedMsg' => 'Gagal mengganti profil',
			'proxies.pageTitle' => 'Proxy',
			'proxies.emptyProxiesMsg' => 'Tidak ada proxy',
			'proxies.delayTestTooltip' => 'Test delay',
			'proxies.sortTooltip' => 'Urut Proxy',
			'proxies.sortOptions.unsorted' => 'Awal',
			'proxies.sortOptions.name' => 'Alfabetikal',
			'proxies.sortOptions.delay' => 'Berdasarkan Delay',
			'proxies.checkIp' => 'Periksa IP',
			'proxies.unknownIp' => 'IP Tidak Diketahui',
			'proxies.autoSelect' => 'Pilih Otomatis',
			'proxies.autoSelectDescription' => 'Sambungkan otomatis ke node tercepat',
			'proxies.sortModalTitle' => 'Pilih metode pengurutan',
			'proxies.activeProxySemanticLabel' => 'Jalur Aktif',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'Jeda: ${delay}ms',
			'proxies.delaySemantics.timeout' => 'Waktu Uji Jeda Habis',
			'proxies.delaySemantics.testing' => 'Jeda: Menguji...',
			'proxies.delaySemantics.untested' => 'Jeda: Belum diuji',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'Jeda: ${delay}ms (hasil sebelumnya)',
			'proxies.ipInfoSemantics.address' => 'Alamat IP',
			'proxies.ipInfoSemantics.country' => 'Negara',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Menguji jeda untuk: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'Beralih ke ${name}',
			'proxies.switchFailed' => 'Gagal mengganti server. Silakan coba lagi.',
			'proxies.testFailed' => 'Uji latensi gagal. Silakan coba lagi.',
			'proxies.groupsLoading' => 'Daftar server masih dimuat. Silakan coba lagi sebentar lagi.',
			'proxies.connectBeforeSwitch' => 'Sambungkan terlebih dahulu sebelum mengganti jalur',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'Uji jeda dimulai untuk ${count} jalur',
			'proxies.delayTestBtn' => 'Jeda',
			'proxies.delayTimeout' => 'Habis waktu',
			'proxies.connectBeforeTest' => 'Sambungkan dulu untuk menguji jeda',
			'proxies.lineCount' => ({required Object count}) => '${count} jalur',
			'proxies.manualSelect' => 'Pilih Manual',
			'proxies.autoTest' => 'Tes Otomatis',
			'logs.pageTitle' => 'Log',
			'logs.filterHint' => 'Filter',
			'logs.allLevelsFilter' => 'Semua',
			'logs.shareCoreLogs' => 'Bagikan Log Inti',
			'logs.shareAppLogs' => 'Bagikan Log Aplikasi',
			'logs.pauseTooltip' => 'Jeda',
			'logs.resumeTooltip' => 'Lanjut',
			'logs.clearTooltip' => 'Bersih',
			'logs.logsCleared' => 'Log dihapus',
			'logs.logsCopied' => 'Log disalin',
			'logs.logsUnderDevelopment' => 'Fitur log sedang dikembangkan',
			'logs.noLogsWhenDisconnected' => 'Tidak tersambung, tidak ada log',
			'logs.loadFailed' => 'Gagal memuat log',
			'logs.empty' => 'Belum ada log',
			'logs.clearFailed' => 'Gagal menghapus log',
			'settings.pageTitle' => 'Setting',
			'settings.requiresRestartMsg' => 'Untuk mencoba restart aplikasi',
			'settings.experimental' => 'Eksperimen',
			'settings.experimentalMsg' => 'Fitur dengan tanda Eksperimen masih dalam pengembangan dan resiko bermasalah.',
			'settings.general.sectionTitle' => 'Umum',
			'settings.general.locale' => 'Bahasa',
			'settings.general.region' => 'Region',
			'settings.general.regionMsg' => 'Bantu tetapkan opsi standar untuk melewati alamat lokal',
			'settings.general.regions.ir' => 'İran (ir)',
			'settings.general.regions.cn' => 'Çin (cn)',
			'settings.general.regions.ru' => 'Russia (ru)',
			'settings.general.regions.af' => 'Afghanistan (af)',
			'settings.general.regions.id' => 'Indonesia (id)',
			'settings.general.regions.other' => 'Lainnya',
			'settings.general.themeMode' => 'Jenis Tema',
			'settings.general.themeModes.system' => 'Ikut Tema Sistem',
			'settings.general.themeModes.dark' => 'Tema Gelap',
			'settings.general.themeModes.light' => 'Tema Cerah',
			'settings.general.themeModes.black' => 'Tema Hitam',
			'settings.general.enableAnalytics' => 'Mengaktifkan Analitik',
			'settings.general.enableAnalyticsMsg' => 'Beri izin untuk mengumpulkan analisis dan mengirim laporan kegagalan untuk meningkatkan aplikasi',
			'settings.general.autoStart' => 'Mulai saat Login',
			'settings.general.silentStart' => 'Mulai Minimalkan',
			'settings.general.openWorkingDir' => 'Buka Direktori Kerja',
			'settings.general.ignoreBatteryOptimizations' => 'Menonaktifkan Optimisasi Baterai',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Hapus batasan untuk performa VPN yang optimal',
			'settings.general.dynamicNotification' => 'Tampilkan Kecepatan di notifikasi',
			'settings.general.hapticFeedback' => 'Umpan Balik Haptik',
			'settings.general.autoIpCheck' => 'Periksa IP Koneksi Otomatis',
			'settings.general.batteryOptimizationStatus.exempted' => 'Dikecualikan',
			'settings.general.batteryOptimizationStatus.notExempted' => 'Tidak Dikecualikan',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Mode Lanjut',
			'settings.advanced.debugMode' => 'Mode Debug',
			'settings.advanced.debugModeMsg' => 'Restart aplikasi untuk menerapkan perubahan',
			'settings.advanced.memoryLimit' => 'Limit Memori',
			'settings.advanced.memoryLimitMsg' => 'Aktifkan jika kamu mendapatkan error habis memori atau error aplikasi yang sering',
			'settings.advanced.resetTunnel' => 'Set ulang profil VPN',
			'settings.advanced.resetTunnelSuccess' => 'Profil VPN telah direset',
			'settings.network.perAppProxyPageTitle' => 'Per-app Proxy',
			'settings.network.perAppProxyModes.off' => 'Semua',
			'settings.network.perAppProxyModes.offMsg' => 'Proxy semua applikasi',
			'settings.network.perAppProxyModes.include' => 'Proxy',
			'settings.network.perAppProxyModes.includeMsg' => 'Proxy untuk aplikasi terpilih',
			'settings.network.perAppProxyModes.exclude' => 'Bypass',
			'settings.network.perAppProxyModes.excludeMsg' => 'Tidak proxy untuk aplikasi terpilih',
			'settings.network.showSystemApps' => 'Tampil aplikasi sistem',
			'settings.network.hideSystemApps' => 'Sembunyikan aplikasi sistem',
			'settings.network.clearSelection' => 'Bersihkan seleksi',
			'settings.network.perAppProxyLoadFailedMsg' => 'Gagal memuat daftar aplikasi',
			'settings.network.perAppProxyRetry' => 'Coba Lagi',
			'settings.network.perAppProxyEmptyMsg' => 'Tidak ada hasil',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'Mode jalur per aplikasi hanya didukung di Android',
			'settings.geoAssets.pageTitle' => 'Rute Aset',
			'settings.geoAssets.geoip' => 'Geoip',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => 'Versi ${version}',
			'settings.geoAssets.fileMissing' => 'File Hilang',
			'settings.geoAssets.update' => 'Perbarui',
			'settings.geoAssets.download' => 'Unduh',
			'settings.geoAssets.failureMsg' => 'Gagal perbarui aset',
			'settings.geoAssets.successMsg' => 'Sukses perbarui aset',
			'settings.geoAssets.addRecommended' => 'Tambah aset rekomendasi',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Routing aset terpilih filenya hilang. Silahkan unduh atau pilih dari yang ada',
			'settings.exportOptions' => 'Salin Opsi Anonim ke Papan Klip',
			'settings.exportAllOptions' => 'Salin Semua Opsi ke Papan Klip',
			'settings.importOptions' => 'Impor Opsi dari Papan Klip',
			'settings.importOptionsMsg' => 'Ini akan menimpa semua opsi konfigurasi dengan nilai yang diberikan. Anda yakin?',
			'settings.backup.importConfirmTitle' => 'Impor Cadangan',
			'settings.backup.importConfirmMsg' => 'Ini mengganti langganan Anda dengan langganan dari cadangan dan menerapkan pengaturannya. Snapshot data saat ini disimpan terlebih dahulu dan dipulihkan otomatis jika impor gagal.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '${count} langganan di perangkat ini tidak ada di cadangan dan akan dihapus.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '${profiles} langganan dan ${settings} pengaturan diimpor.',
			'settings.backup.reportDropped' => ({required Object count}) => '${count} langganan dalam cadangan dilewati karena datanya tidak valid.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '${count} pengaturan dilewati; nilai Anda saat ini dipertahankan.',
			'settings.backup.reportWarpOff' => 'Impor mematikan WARP. Aktifkan kembali di perangkat ini.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} langganan akan diunduh di latar belakang.',
			'settings.backup.errInvalidFile' => 'Ini bukan file cadangan ClashMiao yang valid.',
			'settings.backup.errUnsupportedVersion' => 'Format cadangan ini tidak didukung.',
			'settings.backup.errNewerSchema' => 'Cadangan ini dibuat oleh aplikasi versi yang lebih baru. Perbarui aplikasi terlebih dahulu.',
			'settings.backup.errNoUsableProfiles' => 'Tidak ada langganan dalam cadangan ini yang dapat diimpor.',
			'settings.backup.errSnapshotFailed' => 'Snapshot data saat ini tidak dapat disimpan, sehingga tidak ada yang diubah.',
			'settings.backup.errUnresolvedPrevious' => 'Impor sebelumnya terhenti dan belum dapat dibatalkan. Tidak ada yang diubah. Mulai ulang aplikasi lalu coba lagi.',
			'settings.backup.errRolledBack' => 'Impor gagal. Data Anda sebelumnya telah dipulihkan.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'Impor gagal dan pemulihan otomatis belum selesai. Mulai ulang aplikasi untuk mencobanya lagi. Snapshot disimpan di ${path}.',
			'settings.backup.errFailed' => 'Impor gagal.',
			'settings.backup.errBusy' => 'Impor lain sedang berjalan. Tunggu sampai selesai.',
			'settings.backup.recoveryFailedTitle' => 'Pemulihan otomatis belum selesai',
			'settings.backup.recoveryFailedMsg' => 'Impor cadangan terakhir terhenti dan aplikasi tidak dapat mengembalikan data Anda ke keadaan sebelumnya. Sebagian data mungkin hanya terimpor sebagian. Coba pemulihan otomatis lagi sekarang.',
			'settings.backup.recoveryUnrecoverableTitle' => 'Impor yang terhenti tidak dapat dibatalkan',
			'settings.backup.recoveryUnrecoverableMsg' => 'Impor cadangan terakhir terhenti, tetapi snapshot-nya hilang atau tidak dapat dibaca sehingga tidak dapat dibatalkan. Periksa langganan dan pengaturan Anda.',
			'settings.backup.recoveryRetry' => 'Coba lagi',
			'settings.backup.recoveryClose' => 'Tutup',
			'settings.backup.recoveryRetried' => 'Data Anda dipulihkan ke keadaan sebelum impor yang terhenti.',
			'settings.backup.exportAction' => 'Ekspor cadangan',
			'settings.backup.importAction' => 'Impor cadangan',
			'settings.backup.exportFailed' => 'Gagal mengekspor cadangan',
			'settings.backup.shareText' => 'Cadangan ClashMiao',
			'settings.systemProxyEnabled' => 'Proxy sistem diaktifkan',
			'settings.systemProxyDisabled' => 'Proxy sistem dinonaktifkan (sambung ulang untuk menerapkan)',
			'settings.adminPrivilegesRequired' => 'Memerlukan hak administrator di macOS',
			'settings.portChangeNotice' => 'Perubahan port memerlukan sambung ulang agar berlaku',
			'settings.groups.general' => 'Umum',
			'settings.groups.connection' => 'Koneksi',
			'settings.groups.privacy' => 'Privasi',
			'settings.importOptionsInvalid' => 'Papan klip tidak berisi JSON pengaturan yang valid',
			'settings.importOptionsNothing' => 'Tidak ada pengaturan yang dapat diimpor',
			'settings.importOptionsDone' => ({required Object count}) => '${count} pengaturan diimpor',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '${applied} pengaturan diimpor; ${skipped} dilewati karena tidak valid',
			'about.pageTitle' => 'Tentang',
			'about.version' => 'Versi',
			'about.sourceCode' => 'Code Sumber',
			'about.telegramChannel' => 'Kanal Telegram',
			'about.checkForUpdate' => 'Periksa perbaruan',
			'about.privacyPolicy' => 'Kebijakan Privasi',
			'about.termsAndConditions' => 'Syarat dan Ketentuan Umum',
			'about.appDescription' => 'Klien proxy lintas platform berbasis inti sing-box',
			'about.openSourceLicenses' => 'Lisensi sumber terbuka',
			'appUpdate.notAvailableMsg' => 'Sudah menggunakan versi terakhir',
			'appUpdate.dialogTitle' => 'Perbaruan Tersedia',
			'appUpdate.updateMsg' => 'Versi terbaru ${_root.general.appTitle} tersedia. Ingin di perbarui sekarang?',
			'appUpdate.currentVersionLbl' => 'Versi Sekarang',
			'appUpdate.newVersionLbl' => 'Versi Baru',
			'appUpdate.updateNowBtnTxt' => 'Perbarui Sekarang',
			'appUpdate.laterBtnTxt' => 'Nanti',
			'appUpdate.ignoreBtnTxt' => 'Lewati',
			'appUpdate.checkFailedMsg' => 'Gagal memeriksa pembaruan. Periksa jaringan Anda lalu coba lagi.',
			'tray.dashboard' => 'Dashboard',
			'tray.quit' => 'Keluar',
			'tray.open' => 'Buka',
			'tray.status.connect' => 'Sambung',
			'tray.status.connecting' => 'Menyambungkan',
			'tray.status.disconnect' => 'Putus',
			'tray.status.disconnecting' => 'Memutuskan',
			'tray.hide' => 'Sembunyikan',
			'tray.proxyModeMenu' => 'Mode Proksi',
			'failure.unexpected' => 'Error Tidak Terduga',
			'failure.clash.unexpected' => 'Error Tidak Terduga',
			'failure.clash.core' => ({required Object reason}) => 'Clash Error ${reason}',
			'failure.singbox.unexpected' => 'Servis Error Tidak Terduga',
			'failure.singbox.serviceNotRunning' => 'Servis tidak berjalan',
			'failure.singbox.missingPrivilege' => 'Hak Akses Hilang',
			'failure.singbox.missingPrivilegeMsg' => 'Mode VPN membutuhkan hak akses administrator. Antara buka ulang aplikasi sebagai administrator atau rubah mode servis',
			'failure.singbox.missingGeoAssets' => 'Geo Aset Hilang',
			'failure.singbox.missingGeoAssetsMsg' => 'Geo aset hilang. Pertimbangkan merubah aset aktif atau unduh yang sudah dipilih di seting',
			'failure.singbox.invalidConfigOptions' => 'Pilihan konfigurasi tidak valid',
			'failure.singbox.invalidConfig' => 'Konfigurasi tidak valid',
			'failure.singbox.create' => 'Pembuatan Servis Error',
			'failure.singbox.start' => 'Jalankan Servis Error',
			'failure.singbox.coreLibraryMissing' => 'Pustaka Inti Belum Terpasang',
			'failure.singbox.startTimeout' => 'Waktu Mulai Layanan Habis',
			'failure.singbox.kernelUnresponsive' => 'Inti tidak merespons. Coba lagi atau mulai ulang aplikasi.',
			'failure.singbox.kernelExited' => 'Inti berhenti secara tak terduga',
			'failure.connectivity.unexpected' => 'Kegagalan tidak terduga',
			'failure.connectivity.missingVpnPermission' => 'Izin VPN Hilang',
			'failure.connectivity.missingNotificationPermission' => 'Izin Notifikasi Hilang',
			'failure.connectivity.core' => 'Error Inti',
			'failure.connectivity.networkUnavailable' => 'Jaringan Tidak Tersedia',
			'failure.connectivity.nativeUnresponsive' => 'Kehilangan kontak dengan layanan latar belakang. Coba lagi.',
			'failure.profiles.unexpected' => 'Error Tidak Terduga',
			'failure.profiles.notFound' => 'Profil tidak ditemukan',
			'failure.profiles.invalidConfig' => 'Konfigurasi tidak valid',
			'failure.profiles.invalidUrl' => 'URL tidak valid',
			'failure.profiles.noActive' => 'Tidak Ada Profil Aktif',
			'failure.profiles.readOnlyUpgrade' => 'Perbarui aplikasi sebelum mengubah langganan',
			'failure.connection.unexpected' => 'Sambungan error tidak terduga',
			'failure.connection.timeout' => 'Waktu Sambungan Habis',
			'failure.connection.badResponse' => 'Response Rusak',
			'failure.connection.connectionError' => 'Sambungan Error',
			'failure.connection.badCertificate' => 'Sertifikat Rusak',
			'failure.geoAssets.unexpected' => 'Error Tidak Terduga',
			'failure.geoAssets.notUpdate' => 'Perbaruan tidak tersedia',
			'failure.geoAssets.activeNotFound' => 'Geo Aset Aktif tidak ditemukan',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Ketuk untuk Sambung',
			'connection.connecting' => 'Sambungkan',
			'connection.disconnecting' => 'Putus Sambungan',
			'connection.connected' => 'Tersambung',
			'connection.experimentalNotice' => 'Fitur Experimental digunakan',
			'connection.experimentalNoticeMsg' => 'Kamu telah mengaktifkan fitur experimental yang mungkin mempengaruhi kualitas sambungan dan error tidak terduga. Kamu tetap bisa merubah atau set ulang opsi dari Halaman Konfigurasi',
			'connection.disableExperimentalNotice' => 'Jangan tampil lagi',
			'connection.reconnect' => 'Sambungkan Ulang',
			'connection.connectAnyWay' => 'Tetap sambungkan',
			'connection.reconnectMsg' => 'Menyambungkan ulang untuk menerapkan perubahan...',
			'connection.staleSystemProxyCleaned' => 'Pengaturan proxy sistem yang tertinggal dari keluar tidak normal telah dibersihkan',
			'config.resetBtn' => 'Set Ulang Opsi',
			'config.serviceMode' => 'Sambung ulang agar perubahan diterapkan',
			'config.serviceModes.proxy' => 'Proxy',
			'config.serviceModes.systemProxy' => 'Sistem Proxy',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'Layanan VPN',
			'config.section.route' => 'Opsi Route',
			'config.section.dns' => 'Opsi DNS',
			'config.section.inbound' => 'Opsi Inbound',
			'config.section.mux' => 'Multiplexer',
			'config.section.outbound' => 'Opsi Outbound',
			'config.section.tlsTricks' => 'TLS Tricks',
			'config.section.warp' => 'Opsi WARP',
			'config.section.misc' => 'Opsi Misc',
			'config.warpConsent.title' => 'Persetujuan Cloudflare WARP',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP adalah WireGuard VPN Provider gratis. Dengan mengaktifkan opsi/pilihan ini berarti kamu setuju pada Cloudflare WARP\'s '), tos('Terms of Service'), const TextSpan(text: ' dan '), privacy('Privacy Policy'), const TextSpan(text: '.'), ]), 
			'config.pageTitle' => 'Opsi Konfig',
			'config.logLevel' => 'Log Level',
			'config.resolveDestination' => 'Resolve Destination',
			'config.ipv6Mode' => 'IPv6 Route',
			'config.ipv6Modes.disable' => 'Nonaktifkan',
			'config.ipv6Modes.enable' => 'Aktifkan',
			'config.ipv6Modes.prefer' => 'Prefer',
			'config.ipv6Modes.only' => 'Exclusive',
			'config.remoteDnsAddress' => 'Remote DNS',
			'config.remoteDnsDomainStrategy' => 'Remote DNS Domain Strategy',
			'config.directDnsAddress' => 'Direct DNS',
			'config.directDnsDomainStrategy' => 'Direct DNS Domain Strategy',
			'config.mixedPort' => 'Mixed Port',
			'config.localDnsPort' => 'DNS Port Lokal',
			'config.allowConnectionFromLan' => 'Perbolehkan Sambungan LAN',
			'config.tunImplementation' => 'Implementasi TUN',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'URL Tes Sambungan',
			'config.urlTestInterval' => 'URL Test Interval',
			'config.enableClashApi' => 'Aktifkan Clash API',
			'config.clashApiPort' => 'Clash API Port',
			'config.enableTun' => 'Aktifkan TUN',
			'config.setSystemProxy' => 'Atur Sistem Proxy',
			'config.enableDnsRouting' => 'Aktifkan DNS Routing',
			'config.enableFakeDns' => 'Aktifkan DNS Palsu',
			'config.bypassLan' => 'Bypass LAN',
			'config.strictRoute' => 'Strict Route',
			'config.enableTlsFragment' => 'Aktifkan TLS Fragment',
			'config.tlsFragmentSize' => 'TLS Fragment Size',
			'config.tlsFragmentSleep' => 'TLS Fragment Sleep',
			'config.enableTlsMixedSniCase' => 'Aktifkan TLS Mixed SNI Case',
			'config.enableTlsPadding' => 'Aktifkan TLS Padding',
			'config.tlsPaddingSize' => 'TLS Padding',
			'config.enableMux' => 'Enable Mux',
			'config.muxProtocol' => 'Mux Protocol',
			'config.muxMaxStreams' => 'Max Concurrent Streams',
			'config.enableWarp' => 'Enable WARP',
			'config.setUpWarp' => 'Siapkan WARP',
			'config.warpNotConfigured' => 'Belum dikonfigurasi',
			'config.warpDetourMode' => 'Detour Mode',
			'config.warpDetourModes.inbound' => 'Detour WARP through proxies',
			'config.warpDetourModes.outbound' => 'Detour proxies through WARP',
			'config.warpDetourModes.proxyOverWarp' => 'Alihkan Jalur Melalui WARP',
			'config.warpDetourModes.warpOverProxy' => 'Alihkan WARP Melalui Jalur',
			'config.warpLicenseKey' => 'License Key',
			'config.warpCleanIp' => 'Clean IP',
			'config.warpPort' => 'Port',
			'config.warpNoise' => 'Noise',
			'config.quickSettings' => 'Pengaturan Cepat',
			'config.quickSettingsSubtitle' => 'Sesuaikan pengalaman koneksi Anda',
			'config.setupWarp' => 'Siapkan WARP',
			'config.allOptions' => 'Semua Opsi Konfigurasi',
			'config.allAdvancedOptions' => 'Semua Opsi Lanjutan',
			'config.shortServiceModes.proxy' => 'Hanya Jalur',
			'config.shortServiceModes.systemProxy' => 'Jalur Sistem',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'Layanan VPN',
			'config.generateWarpConfig' => 'Buat Konfigurasi WARP',
			'config.missingWarpConfig' => 'Konfigurasi WARP Tidak Ada',
			'config.warpConfigGenerated' => 'Konfigurasi WARP Dibuat',
			'config.blockAds' => 'Blokir Iklan',
			'config.tproxyPort' => 'Port Jalur Transparan',
			'config.warpNoiseSize' => 'Ukuran Noise',
			'config.warpNoiseMode' => 'Mode Noise',
			'config.warpNoiseDelay' => 'Penundaan Noise',
			'config.desktopProxyScopeNotice' => 'Di desktop, hanya aplikasi yang mematuhi proxy sistem yang dialihkan melalui terowongan. Perangkat lunak yang mengabaikannya (beberapa game, alat baris perintah, aplikasi dengan pengaturan proxy sendiri) terhubung langsung dan membocorkan IP asli Anda.',
			'config.serviceModeIosVpnOnly' => 'iOS hanya mendukung mode VPN',
			'config.warpGenerating' => 'Membuat konfigurasi WARP…',
			'config.warpConfigFailed' => 'Gagal membuat konfigurasi WARP. Coba lagi nanti.',
			'config.portRangeError' => 'Port harus antara 1024 dan 65535',
			'config.dnsEmptyError' => 'Alamat DNS tidak boleh kosong',
			'config.rangeFormatError' => 'Masukkan angka atau rentang, mis. 10-30',
			'config.urlSchemeError' => 'URL harus diawali http:// atau https://',
			'config.manageRuleAssets' => 'Kelola set aturan',
			_ => null,
		};
	}
}
