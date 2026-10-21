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
class TranslationsFa extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsFa({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.fa,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <fa>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsFa _root = this; // ignore: unused_field

	@override 
	TranslationsFa $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsFa(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$fa general = Translations$general$fa._(_root);
	@override late final Translations$intro$fa intro = Translations$intro$fa._(_root);
	@override late final Translations$home$fa home = Translations$home$fa._(_root);
	@override late final Translations$stats$fa stats = Translations$stats$fa._(_root);
	@override late final Translations$profile$fa profile = Translations$profile$fa._(_root);
	@override late final Translations$proxies$fa proxies = Translations$proxies$fa._(_root);
	@override late final Translations$logs$fa logs = Translations$logs$fa._(_root);
	@override late final Translations$settings$fa settings = Translations$settings$fa._(_root);
	@override late final Translations$about$fa about = Translations$about$fa._(_root);
	@override late final Translations$appUpdate$fa appUpdate = Translations$appUpdate$fa._(_root);
	@override late final Translations$tray$fa tray = Translations$tray$fa._(_root);
	@override late final Translations$failure$fa failure = Translations$failure$fa._(_root);
	@override late final Translations$connection$fa connection = Translations$connection$fa._(_root);
	@override late final Translations$config$fa config = Translations$config$fa._(_root);
}

// Path: general
class Translations$general$fa extends Translations$general$en {
	Translations$general$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'بازنشانی';
	@override late final Translations$general$toggle$fa toggle = Translations$general$toggle$fa._(_root);
	@override late final Translations$general$state$fa state = Translations$general$state$fa._(_root);
	@override String get sort => 'مرتب‌سازی';
	@override String get sortBy => 'مرتب‌سازی براساس';
	@override String get addToClipboard => 'افزودن به کلیپ‌بورد';
	@override String get notSet => 'تنظیم نشده است';
	@override String get agree => 'پذیرفتن';
	@override String get decline => 'صرف‌نظر کردن';
	@override String get unknown => 'ناشناخته';
	@override String get hidden => 'پنهان';
	@override String get timeout => 'عدم ارتباط';
	@override String get clipboardExportSuccessMsg => 'به کلیپ‌بورد افزوده شد';
	@override String get showMore => 'نمایش بیشتر';
	@override String get showLess => 'نمایش کمتر';
	@override String get openAppSettings => 'باز کردن تنظیمات برنامه';
	@override String get grantPermission => 'اجازه دادن';
	@override String get underDevelopment => 'در حال توسعه';
	@override String get confirm => 'تأیید';
	@override String get close => 'بستن';
	@override String get cancel => 'لغو';
	@override String get clipboardEmpty => 'کلیپ‌بورد خالی است';
	@override String get clipboardReadFailed => 'خواندن کلیپ‌بورد ناموفق بود';
	@override String get moreOptions => 'گزینه‌های بیشتر';
}

// Path: intro
class Translations$intro$fa extends Translations$intro$en {
	Translations$intro$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'در صورت ادامه با '),
		tap(_root.about.termsAndConditions),
		const TextSpan(text: ' موافقت می‌کنید'),
	]);
	@override String get start => 'آغاز';
}

// Path: home
class Translations$home$fa extends Translations$home$en {
	Translations$home$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'خانه';
	@override String get emptyProfilesMsg => 'با افزودن یک پروفایل اشتراک شروع کنید';
	@override String get noActiveProfileMsg => 'یک پروفایل انتخاب کنید';
	@override late final Translations$home$routingMode$fa routingMode = Translations$home$routingMode$fa._(_root);
	@override String failedToSwitchMode({required Object error}) => 'تغییر حالت ناموفق بود: ${error}';
	@override String get connectionFailedTitle => 'اتصال ناموفق';
	@override String get coreMissingTitle => 'کتابخانهٔ هسته پیدا نشد';
	@override String get coreMissingMsg => 'برنامه نتوانست هستهٔ شبکهٔ خود را بارگذاری کند. اتصال در دسترس نیست. برنامه را دوباره نصب کنید یا مطمئن شوید فایل کتابخانهٔ هسته کنار فایل اجرایی قرار دارد.';
	@override String get degradedTitle => 'متصل است، اما دسترسی به اینترنت وجود ندارد';
	@override String get degradedMsg => 'تونل برقرار است اما ترافیک عبور نمی‌کند. ممکن است نود از کار افتاده باشد — نود دیگری را امتحان کنید یا قطع کنید.';
	@override String get degradedRetry => 'بررسی مجدد';
	@override late final Translations$home$egressIp$fa egressIp = Translations$home$egressIp$fa._(_root);
	@override String get emptyProfilesHint => 'برای شروع، دکمهٔ زیر را بزنید';
	@override String get noActiveProfileTitle => 'هیچ پروفایلی انتخاب نشده است';
}

// Path: stats
class Translations$stats$fa extends Translations$stats$en {
	Translations$stats$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'مصرف';
	@override String get trafficLive => 'مصرف لحظه‌ای';
	@override String get trafficTotal => 'مصرف کل';
	@override String get uplink => 'ارسال';
	@override String get downlink => 'دریافت';
	@override String get connection => 'اتصال';
	@override String get speed => 'سرعت';
	@override String get totalTransferred => 'کل تبادل';
	@override String get trafficUsage => 'مصرف ترافیک';
	@override String get liveSpeed => 'سرعت لحظه‌ای';
	@override String get sessionTraffic => 'ترافیک این نشست';
	@override String get downloadSpeed => 'سرعت دانلود';
}

// Path: profile
class Translations$profile$fa extends Translations$profile$en {
	Translations$profile$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'پروفایل‌ها';
	@override String get detailsPageTitle => 'پروفایل';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'نام پروفایل فعال: ${name}';
	@override String get activeProfileBtnSemanticLabel => 'نمایش همه‌ی پروفایل‌ها';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'انتخاب ${name} به‌عنوان پروفایل فعال';
	@override late final Translations$profile$subscription$fa subscription = Translations$profile$subscription$fa._(_root);
	@override late final Translations$profile$sortBy$fa sortBy = Translations$profile$sortBy$fa._(_root);
	@override late final Translations$profile$add$fa add = Translations$profile$add$fa._(_root);
	@override late final Translations$profile$update$fa update = Translations$profile$update$fa._(_root);
	@override late final Translations$profile$share$fa share = Translations$profile$share$fa._(_root);
	@override late final Translations$profile$edit$fa edit = Translations$profile$edit$fa._(_root);
	@override late final Translations$profile$delete$fa delete = Translations$profile$delete$fa._(_root);
	@override late final Translations$profile$save$fa save = Translations$profile$save$fa._(_root);
	@override late final Translations$profile$detailsForm$fa detailsForm = Translations$profile$detailsForm$fa._(_root);
	@override late final Translations$profile$actionButtons$fa actionButtons = Translations$profile$actionButtons$fa._(_root);
	@override late final Translations$profile$details$fa details = Translations$profile$details$fa._(_root);
	@override late final Translations$profile$overview$fa overview = Translations$profile$overview$fa._(_root);
	@override String get remoteProfile => 'پروفایل راه دور';
	@override String get defaultLocalName => 'درون‌ریزی محلی';
	@override String get defaultDeepLinkName => 'درون‌ریزی از پیوند';
	@override String get switchFailedMsg => 'تغییر پروفایل ناموفق بود';
}

// Path: proxies
class Translations$proxies$fa extends Translations$proxies$en {
	Translations$proxies$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'پروکسی‌ها';
	@override String get emptyProxiesMsg => 'هیچ پروکسی موجود نیست';
	@override String get delayTestTooltip => 'تست تأخیر';
	@override String get sortTooltip => 'مرتب‌سازی پروکسی‌ها';
	@override String get checkIp => 'بررسی آی‌پی';
	@override String get unknownIp => 'آی‌پی ناشناخته';
	@override late final Translations$proxies$sortOptions$fa sortOptions = Translations$proxies$sortOptions$fa._(_root);
	@override String get activeProxySemanticLabel => 'پروکسی فعال';
	@override late final Translations$proxies$delaySemantics$fa delaySemantics = Translations$proxies$delaySemantics$fa._(_root);
	@override late final Translations$proxies$ipInfoSemantics$fa ipInfoSemantics = Translations$proxies$ipInfoSemantics$fa._(_root);
	@override String get autoSelect => 'انتخاب خودکار';
	@override String get autoSelectDescription => 'اتصال خودکار به سریع‌ترین نود';
	@override String get sortModalTitle => 'روش مرتب‌سازی را انتخاب کنید';
	@override String testingDelayInfo({required Object name}) => 'در حال آزمایش تأخیر: ${name}';
	@override String switchedTo({required Object name}) => 'به ${name} تغییر یافت';
	@override String get switchFailed => 'تغییر سرور انجام نشد. لطفاً دوباره تلاش کنید.';
	@override String get testFailed => 'آزمون تأخیر ناموفق بود. لطفاً دوباره تلاش کنید.';
	@override String get groupsLoading => 'فهرست سرورها هنوز در حال بارگذاری است. لطفاً کمی بعد دوباره تلاش کنید.';
	@override String get connectBeforeSwitch => 'پیش از تعویض خط، متصل شوید';
	@override String startDelayTestForGroups({required Object count}) => 'آزمایش تأخیر برای ${count} خط آغاز شد';
	@override String get delayTestBtn => 'تأخیر';
	@override String get delayTimeout => 'مهلت تمام';
	@override String get connectBeforeTest => 'برای تست تأخیر ابتدا متصل شوید';
	@override String lineCount({required Object count}) => '${count} خط';
	@override String get manualSelect => 'انتخاب دستی';
	@override String get autoTest => 'تست خودکار';
}

// Path: logs
class Translations$logs$fa extends Translations$logs$en {
	Translations$logs$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'گزارش‌ها';
	@override String get filterHint => 'فیلتر';
	@override String get allLevelsFilter => 'همه';
	@override String get shareCoreLogs => 'اشتراک‌گذاری گزارش‌های هسته';
	@override String get shareAppLogs => 'اشتراک‌گذاری گزارش‌های برنامه';
	@override String get pauseTooltip => 'مکث';
	@override String get resumeTooltip => 'ادامه دادن';
	@override String get clearTooltip => 'پاک‌سازی';
	@override String get logsCleared => 'گزارش‌ها پاک شد';
	@override String get logsCopied => 'گزارش‌ها کپی شد';
	@override String get logsUnderDevelopment => 'قابلیت گزارش‌گیری در حال توسعه است';
	@override String get noLogsWhenDisconnected => 'متصل نیست، گزارشی وجود ندارد';
	@override String get loadFailed => 'بارگیری گزارش‌ها ناموفق بود';
	@override String get empty => 'هنوز گزارشی وجود ندارد';
	@override String get clearFailed => 'پاک کردن گزارش‌ها ناموفق بود';
}

// Path: settings
class Translations$settings$fa extends Translations$settings$en {
	Translations$settings$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'تنظیمات';
	@override String get requiresRestartMsg => 'برای اعمال این تنظیم، برنامه را دوباره راه‌اندازی کنید';
	@override String get experimental => 'آزمایشی';
	@override String get experimentalMsg => 'تنظیماتی که عنوان آزمایشی دارند، هم‌چنان در دست توسعه هستند و فعال‌سازی آن‌ها می‌تواند باعث بروز مشکلاتی شود. ';
	@override String get exportOptions => 'کپی تنظیمات ساده به کلیپ‌بورد';
	@override String get exportAllOptions => 'کپی همه تنظیمات به کلیپ‌بورد';
	@override String get importOptions => 'وارد کردن تنظیمات از کلیپ‌بورد';
	@override String get importOptionsMsg => 'این اقدام همه‌ی تنظیمات پیکربندی را با مقادیر اولیه بازنویسی می‌کند. آیا مطمئن هستید؟';
	@override late final Translations$settings$backup$fa backup = Translations$settings$backup$fa._(_root);
	@override late final Translations$settings$general$fa general = Translations$settings$general$fa._(_root);
	@override late final Translations$settings$advanced$fa advanced = Translations$settings$advanced$fa._(_root);
	@override late final Translations$settings$network$fa network = Translations$settings$network$fa._(_root);
	@override late final Translations$settings$geoAssets$fa geoAssets = Translations$settings$geoAssets$fa._(_root);
	@override String get systemProxyEnabled => 'پروکسی سیستم فعال شد';
	@override String get systemProxyDisabled => 'پروکسی سیستم غیرفعال شد (برای اعمال، دوباره وصل شوید)';
	@override String get adminPrivilegesRequired => 'در macOS به دسترسی مدیر نیاز است';
	@override String get portChangeNotice => 'تغییر پورت برای اعمال شدن نیاز به اتصال مجدد دارد';
	@override late final Translations$settings$groups$fa groups = Translations$settings$groups$fa._(_root);
	@override String get importOptionsInvalid => 'محتوای کلیپ‌بورد JSON تنظیمات معتبری نیست';
	@override String get importOptionsNothing => 'هیچ تنظیم قابل درون‌ریزی پیدا نشد';
	@override String importOptionsDone({required Object count}) => '${count} تنظیم درون‌ریزی شد';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '${applied} تنظیم درون‌ریزی شد؛ ${skipped} مورد به دلیل نامعتبر بودن رد شد';
}

// Path: about
class Translations$about$fa extends Translations$about$en {
	Translations$about$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'درباره';
	@override String get version => 'نسخه';
	@override String get sourceCode => 'کد منبع';
	@override String get telegramChannel => 'کانال تلگرام';
	@override String get checkForUpdate => 'بررسی برای به‌روزرسانی';
	@override String get privacyPolicy => 'سیاست‌های حفظ حریم خصوصی';
	@override String get termsAndConditions => 'شرایط و ضوابط استفاده';
	@override String get appDescription => 'یک کلاینت پروکسی چندسکویی مبتنی بر هستهٔ sing-box';
	@override String get openSourceLicenses => 'مجوزهای متن‌باز';
}

// Path: appUpdate
class Translations$appUpdate$fa extends Translations$appUpdate$en {
	Translations$appUpdate$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'در حال استفاده از آخرین نسخه هستید';
	@override String get dialogTitle => 'به‌روزرسانی موجود است';
	@override String get updateMsg => 'نسخه‌ی جدیدی از general.appTitle در دسترس است. آیا می‌خواهید آن را به‌روزرسانی کنید؟';
	@override String get currentVersionLbl => 'نسخه‌ی فعلی';
	@override String get newVersionLbl => 'نسخه‌ی جدید';
	@override String get updateNowBtnTxt => 'هم‌اکنون به‌روزرسانی شود';
	@override String get laterBtnTxt => 'بعداً';
	@override String get ignoreBtnTxt => 'نادیده‌گرفتن';
	@override String get checkFailedMsg => 'بررسی به‌روزرسانی ناموفق بود. شبکه خود را بررسی کنید و دوباره تلاش کنید.';
}

// Path: tray
class Translations$tray$fa extends Translations$tray$en {
	Translations$tray$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'داشبورد';
	@override String get quit => 'خروج';
	@override String get open => 'باز کردن';
	@override late final Translations$tray$status$fa status = Translations$tray$status$fa._(_root);
	@override String get hide => 'پنهان کردن';
	@override String get proxyModeMenu => 'حالت پروکسی';
}

// Path: failure
class Translations$failure$fa extends Translations$failure$en {
	Translations$failure$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره';
	@override late final Translations$failure$clash$fa clash = Translations$failure$clash$fa._(_root);
	@override late final Translations$failure$singbox$fa singbox = Translations$failure$singbox$fa._(_root);
	@override late final Translations$failure$connectivity$fa connectivity = Translations$failure$connectivity$fa._(_root);
	@override late final Translations$failure$profiles$fa profiles = Translations$failure$profiles$fa._(_root);
	@override late final Translations$failure$connection$fa connection = Translations$failure$connection$fa._(_root);
	@override late final Translations$failure$geoAssets$fa geoAssets = Translations$failure$geoAssets$fa._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$fa extends Translations$connection$en {
	Translations$connection$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'برای اتصال ضربه بزنید';
	@override String get connecting => 'در حال اتصال';
	@override String get disconnecting => 'در حال قطع اتصال';
	@override String get connected => 'متصل شد';
	@override String get reconnect => 'اتصال دوباره';
	@override String get connectAnyWay => 'در هر صورت متصل شو';
	@override String get experimentalNotice => 'ویژگی‌های آزمایشی در حال استفاده';
	@override String get experimentalNoticeMsg => 'شما برخی از ویژگی‌های آزمایشی را فعال کرده‌اید که ممکن است بر کیفیت اتصال تأثیر گذاشته و باعث بروز خطاهای غیرمنتظره شود. شما همیشه می‌توانید این گزینه‌ها را از صفحه‌ی تنظیمات پیکربندی تغییر دهید یا بازنشانی کنید.';
	@override String get disableExperimentalNotice => 'دیگر نشان نده';
	@override String get reconnectMsg => 'در حال اتصال مجدد برای اعمال تغییرات...';
	@override String get staleSystemProxyCleaned => 'تنظیمات پروکسی سیستم که از خروج غیرعادی قبلی باقی مانده بود پاک شد';
}

// Path: config
class Translations$config$fa extends Translations$config$en {
	Translations$config$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'بازنشانی تنظیمات';
	@override String get serviceMode => 'حالت سرویس';
	@override String get quickSettings => 'تنظیمات سریع';
	@override String get setupWarp => 'راه‌اندازی WARP';
	@override String get allOptions => 'همه‌ی تنظیمات پیکربندی';
	@override late final Translations$config$serviceModes$fa serviceModes = Translations$config$serviceModes$fa._(_root);
	@override late final Translations$config$shortServiceModes$fa shortServiceModes = Translations$config$shortServiceModes$fa._(_root);
	@override late final Translations$config$section$fa section = Translations$config$section$fa._(_root);
	@override late final Translations$config$warpConsent$fa warpConsent = Translations$config$warpConsent$fa._(_root);
	@override String get generateWarpConfig => 'ایجاد پیکربندی WARP';
	@override String get missingWarpConfig => 'پیکربندی WARP موجود نیست';
	@override String get warpConfigGenerated => 'پیکربندی WARP ایجاد شد';
	@override String get pageTitle => 'تنظیمات پیکربندی';
	@override String get logLevel => 'سطح گزارش';
	@override String get blockAds => 'مسدود سازی تبلیغات';
	@override String get resolveDestination => 'جایگذاری مقصد';
	@override String get ipv6Mode => 'مسیریابی IPv6';
	@override late final Translations$config$ipv6Modes$fa ipv6Modes = Translations$config$ipv6Modes$fa._(_root);
	@override String get remoteDnsAddress => 'DNS خارجی';
	@override String get remoteDnsDomainStrategy => 'استراتژی دامنه DNS خارجی';
	@override String get directDnsAddress => 'DNS مستقیم';
	@override String get directDnsDomainStrategy => 'استراتژی دامنه DNS مستقیم';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'اعمال نشد: مسیریابی IPv6 غیرفعال است اما «${field}» فقط IPv6 است، پس هیچ دامنه‌ای حل نمی‌شود. ابتدا مسیریابی IPv6 را فعال کنید یا راهبرد دیگری انتخاب کنید.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'اعمال نشد: مسیریابی IPv6 فقط IPv6 است اما «${field}» فقط IPv4 است، پس هیچ دامنه‌ای حل نمی‌شود. ابتدا یکی از آن‌ها را تغییر دهید.';
	@override String dnsStrategyReset({required Object field}) => '«${field}» با تنظیم مسیریابی IPv6 تعارض داشت (هیچ دامنه‌ای حل نمی‌شد) و به خودکار بازنشانی شد.';
	@override String get mixedPort => 'پورت چندمنظوره';
	@override String get tproxyPort => 'پورت پروکسی نامرئی';
	@override String get localDnsPort => 'پورت DNS داخلی';
	@override String get allowConnectionFromLan => 'اشتراک VPN در شبکه داخلی';
	@override String get tunImplementation => 'پیاده‌سازی TUN';
	@override String get mtu => 'سایز بسته‌ها (MTU) ';
	@override String get connectionTestUrl => 'لینک بررسی اتصال';
	@override String get urlTestInterval => 'فاصله‌ی زمانی بررسی لینک';
	@override String get enableClashApi => 'فعال‌سازی Clash API';
	@override String get clashApiPort => 'پورت Clash API';
	@override String get enableTun => 'فعال‌سازی TUN';
	@override String get setSystemProxy => 'تنظیم پروکسی سیستم';
	@override String get enableDnsRouting => 'فعال‌سازی مسیریابی DNS';
	@override String get enableFakeDns => 'فعال‌سازی DNS جعلی';
	@override String get bypassLan => 'دور زدن LAN';
	@override String get strictRoute => 'مسیر دقیق';
	@override String get enableTlsFragment => 'فعال‌سازی TLS Fragment';
	@override String get tlsFragmentSize => 'اندازه‌ی TLS Fragment ';
	@override String get tlsFragmentSleep => 'کنار گذاشتن TLS Fragment';
	@override String get enableTlsMixedSniCase => 'فعال‌سازی TLS Mixed SNI Case';
	@override String get enableTlsPadding => 'فعال‌سازی TLS Padding';
	@override String get tlsPaddingSize => 'اندازه‌ی TLS Padding';
	@override String get enableMux => 'فعال‌سازی Mux';
	@override String get muxProtocol => 'پروتکل Mux';
	@override String get muxMaxStreams => 'حداکثر جریان‌های هم‌زمان';
	@override String get enableWarp => 'فعال‌سازی WARP';
	@override String get setUpWarp => 'راه‌اندازی WARP';
	@override String get warpNotConfigured => 'پیکربندی نشده';
	@override String get warpDetourMode => 'حالت وارپ';
	@override late final Translations$config$warpDetourModes$fa warpDetourModes = Translations$config$warpDetourModes$fa._(_root);
	@override String get warpLicenseKey => 'کلید لایسنس';
	@override String get warpCleanIp => 'آی‌پی تمیز';
	@override String get warpPort => 'پورت';
	@override String get warpNoise => 'تعداد نویز';
	@override String get warpNoiseSize => 'اندازه نویز';
	@override String get warpNoiseMode => 'حالت نویز';
	@override String get warpNoiseDelay => 'تأخیر نویز';
	@override String get quickSettingsSubtitle => 'تجربهٔ اتصال خود را سفارشی کنید';
	@override String get allAdvancedOptions => 'همهٔ گزینه‌های پیشرفته';
	@override String get desktopProxyScopeNotice => 'در دسکتاپ، فقط برنامه‌هایی که پروکسی سیستم را رعایت می‌کنند از تونل عبور می‌کنند. نرم‌افزارهایی که آن را نادیده می‌گیرند (برخی بازی‌ها، ابزارهای خط فرمان، برنامه‌های دارای تنظیمات پروکسی مستقل) مستقیم وصل می‌شوند و IP واقعی شما را افشا می‌کنند.';
	@override String get serviceModeIosVpnOnly => 'iOS فقط از حالت VPN پشتیبانی می‌کند';
	@override String get warpGenerating => 'در حال ساخت پیکربندی WARP…';
	@override String get warpConfigFailed => 'ساخت پیکربندی WARP ناموفق بود. لطفاً بعداً دوباره تلاش کنید.';
	@override String get portRangeError => 'پورت باید بین 1024 و 65535 باشد';
	@override String get dnsEmptyError => 'نشانی DNS نمی‌تواند خالی باشد';
	@override String get rangeFormatError => 'یک عدد یا بازه وارد کنید، مثلاً 10-30';
	@override String get urlSchemeError => 'نشانی باید با http:// یا https:// شروع شود';
	@override String get manageRuleAssets => 'مدیریت مجموعه‌قواعد';
}

// Path: general.toggle
class Translations$general$toggle$fa extends Translations$general$toggle$en {
	Translations$general$toggle$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'فعال';
	@override String get disabled => 'غیرفعال';
}

// Path: general.state
class Translations$general$state$fa extends Translations$general$state$en {
	Translations$general$state$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get disable => 'غیرفعال';
}

// Path: home.routingMode
class Translations$home$routingMode$fa extends Translations$home$routingMode$en {
	Translations$home$routingMode$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get global => 'پروکسی سراسری';
	@override String get smart => 'مسیریابی هوشمند';
}

// Path: home.egressIp
class Translations$home$egressIp$fa extends Translations$home$egressIp$en {
	Translations$home$egressIp$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get label => 'آی‌پی خروجی';
	@override String get notConnected => 'برای نمایش آی‌پی خروجی متصل شوید';
	@override String get tapToCheck => 'برای بررسی آی‌پی خروجی ضربه بزنید';
	@override String get checking => 'در حال بررسی…';
	@override String get failedRetry => 'بررسی ناموفق بود، برای تلاش دوباره ضربه بزنید';
}

// Path: profile.subscription
class Translations$profile$subscription$fa extends Translations$profile$subscription$en {
	Translations$profile$subscription$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'ترافیک';
	@override String updatedTimeAgo({required Object timeago}) => '${timeago} به‌روزرسانی شد';
	@override String remainingDuration({required Object duration}) => '${duration} روز باقی مانده';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed} از ${total} ترافیک مصرف شده';
	@override String get expired => 'پایان زمان مجاز';
	@override String get noTraffic => 'پایان حجم مجاز';
	@override String get upload => 'آپلود';
	@override String get download => 'دانلود';
	@override String get total => 'کل ترافیک';
	@override String get expireDate => 'تاریخ پایان';
}

// Path: profile.sortBy
class Translations$profile$sortBy$fa extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'اخیراً به‌روز شده';
	@override String get name => 'بر اساس نام';
}

// Path: profile.add
class Translations$profile$add$fa extends Translations$profile$add$en {
	Translations$profile$add$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'افزودن پروفایل جدید';
	@override String get shortBtnTxt => 'پروفایل جدید';
	@override String get fromClipboard => 'افزودن از کلیپ‌بورد';
	@override String get scanQr => 'اسکن کد QR';
	@override late final Translations$profile$add$qrScanner$fa qrScanner = Translations$profile$add$qrScanner$fa._(_root);
	@override String get manually => 'افزودن دستی';
	@override String get addWarp => 'افزودن وارپ';
	@override String get addingWarpMsg => 'لطفا صبر کنید تا وارپ ثبت شود';
	@override String get addingProfileMsg => 'در حال افزودن پروفایل';
	@override String get failureMsg => 'افزودن پروفایل ناموفق بود';
	@override String get modalSubtitle => 'نحوهٔ افزودن فایل پیکربندی را انتخاب کنید';
	@override String get manuallyDescription => 'پیکربندی سرور را دستی وارد کنید';
	@override String get warpDescription => 'شتاب‌دهی رایگان با Cloudflare WARP';
	@override String importedNamed({required Object name}) => 'اشتراک درون‌ریزی شد: ${name}';
	@override String get clipboardEmpty => 'کلیپ‌بورد خالی است و چیزی برای درون‌ریزی وجود ندارد';
	@override String get deepLinkMissingUrl => 'پیوند نشانی اشتراک ندارد';
	@override String get successMsg => 'پروفایل افزوده شد';
	@override String get nameAutoHint => 'به‌طور خودکار تشخیص داده می‌شود (اختیاری)';
}

// Path: profile.update
class Translations$profile$update$fa extends Translations$profile$update$en {
	Translations$profile$update$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'به‌روزرسانی';
	@override String get tooltip => 'به‌روزرسانی پروفایل';
	@override String get updateSubscriptions => 'به‌روزرسانی اشتراک‌ها';
	@override String get failureMsg => 'به‌روزرسانی پروفایل ناموفق بود';
	@override String get successMsg => 'پروفایل با موفقیت به‌روزرسانی شد';
	@override String namedFailureMsg({required Object name}) => 'به‌روزرسانی "${name}" ناموفق بود';
	@override String namedSuccessMsg({required Object name}) => '"${name}" با موفقیت به‌روز شد';
}

// Path: profile.share
class Translations$profile$share$fa extends Translations$profile$share$en {
	Translations$profile$share$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'اشتراک‌گذاری';
	@override String get exportToClipboardSuccess => 'به کلیپ‌بورد اضافه شد';
	@override String get exportSubLinkToClipboard => 'صادر کردن لینک اشتراک به کلیپ‌بورد';
	@override String get subLinkQrCode => 'کد QR لینک اشتراک';
	@override String get exportConfigToClipboard => 'افزودن پیکربندی به کلیپ‌بورد';
	@override String get exportConfigToClipboardSuccess => 'پیکربندی در کلیپ‌بورد کپی شد';
	@override String get shareLink => 'اشتراک‌گذاری پیوند';
	@override String get subscriptionLinkCopied => 'پیوند اشتراک کپی شد';
	@override String get configCopied => 'پیکربندی کپی شد';
	@override String get copyFailed => 'کپی ناموفق بود';
}

// Path: profile.edit
class Translations$profile$edit$fa extends Translations$profile$edit$en {
	Translations$profile$edit$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'ویرایش';
	@override String get selectActiveTxt => 'انتخاب پروفایل فعال';
}

// Path: profile.delete
class Translations$profile$delete$fa extends Translations$profile$delete$en {
	Translations$profile$delete$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'حذف';
	@override String get confirmationMsg => 'پروفایل برای همیشه حذف شود؟';
	@override String get successMsg => 'پروفایل با موفقیت حذف شد';
	@override String get confirmTitle => 'حذف پروفایل';
	@override String namedConfirmMsg({required Object name}) => '«${name}» حذف شود؟ این کار برگشت‌پذیر نیست.';
}

// Path: profile.save
class Translations$profile$save$fa extends Translations$profile$save$en {
	Translations$profile$save$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'ذخیره';
	@override String get successMsg => 'پروفایل با موفقیت ذخیره شد';
	@override String get failureMsg => 'خطا در ذخیره‌ی پروفایل';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$fa extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'نام';
	@override String get nameHint => 'نام پروفایل';
	@override String get urlLabel => 'لینک';
	@override String get urlHint => 'لینک کامل پیکربندی';
	@override String get emptyNameMsg => 'نام نمی‌تواند خالی باشد';
	@override String get invalidUrlMsg => 'لینک نامعتبر است';
	@override String get lastUpdate => 'آخرین به‌روزرسانی';
	@override String get updateInterval => 'به‌روزرسانی خودکار';
	@override String get updateIntervalDialogTitle => 'فاصله‌ی زمانی به‌روزرسانی خودکار (ساعت)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'خاموش';
	@override String updateIntervalHours({required Object hours}) => '${hours} ساعت';
	@override String updateIntervalDays({required Object days}) => '${days} روز';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$fa extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get add => 'افزودن';
	@override String get updateAll => 'به‌روزرسانی همه';
	@override String get sort => 'مرتب‌سازی';
	@override String get copyConfigSuccess => 'پیکربندی کپی شد';
	@override String get editConfig => 'ویرایش پیکربندی';
}

// Path: profile.details
class Translations$profile$details$fa extends Translations$profile$details$en {
	Translations$profile$details$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'اطلاعات پایه';
	@override String get subscriptionStatus => 'وضعیت اشتراک';
	@override String get options => 'گزینه‌ها';
	@override String get updateNow => 'اکنون به‌روزرسانی کن';
	@override String get updateNowDescription => 'دریافت آخرین پیکربندی از سرور';
	@override String get expireDate => 'تاریخ انقضا';
	@override String get unlimited => 'نامحدود';
}

// Path: profile.overview
class Translations$profile$overview$fa extends Translations$profile$overview$en {
	Translations$profile$overview$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'در حال استفاده';
	@override String remainingDays({required Object days}) => '${days} روز باقی مانده';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$fa extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'پیش‌فرض';
	@override String get name => 'براساس نام';
	@override String get delay => 'براساس تأخیر';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$fa extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'تأخیر: ${delay}ms';
	@override String get timeout => 'مهلت تست تأخیر به اتمام رسید';
	@override String get testing => 'تأخیر: در حال آزمایش...';
	@override String get untested => 'تأخیر: آزمایش نشده';
	@override String stale({required Object delay}) => 'تأخیر: ${delay}ms (نتیجه قبلی)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$fa extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get address => 'آدرس آی‌پی';
	@override String get country => 'کشور';
}

// Path: settings.backup
class Translations$settings$backup$fa extends Translations$settings$backup$en {
	Translations$settings$backup$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'درون‌ریزی پشتیبان';
	@override String get importConfirmMsg => 'این کار اشتراک‌های شما را با اشتراک‌های موجود در پشتیبان جایگزین می‌کند و تنظیمات آن را اعمال می‌کند. ابتدا یک نسخهٔ لحظه‌ای از داده‌های فعلی ذخیره می‌شود و اگر درون‌ریزی ناموفق باشد، خودکار بازیابی می‌شود.';
	@override String importRemovesMsg({required Object count}) => '${count} اشتراک روی این دستگاه در پشتیبان نیست و حذف خواهد شد.';
	@override String reportImported({required Object profiles, required Object settings}) => '${profiles} اشتراک و ${settings} تنظیم درون‌ریزی شد.';
	@override String reportDropped({required Object count}) => '${count} اشتراک در پشتیبان به دلیل نامعتبر بودن داده‌ها نادیده گرفته شد.';
	@override String reportSettingsSkipped({required Object count}) => '${count} تنظیم نادیده گرفته شد؛ مقدارهای فعلی شما حفظ شدند.';
	@override String get reportWarpOff => 'درون‌ریزی WARP را خاموش کرد. آن را دوباره روی این دستگاه فعال کنید.';
	@override String reportBackfill({required Object count}) => '${count} اشتراک در پس‌زمینه دانلود خواهد شد.';
	@override String get errInvalidFile => 'این یک فایل پشتیبان معتبر ClashMiao نیست.';
	@override String get errUnsupportedVersion => 'این قالب پشتیبان پشتیبانی نمی‌شود.';
	@override String get errNewerSchema => 'این پشتیبان با نسخهٔ جدیدتری از برنامه ساخته شده است. لطفاً ابتدا برنامه را به‌روزرسانی کنید.';
	@override String get errNoUsableProfiles => 'هیچ‌یک از اشتراک‌های این پشتیبان قابل درون‌ریزی نیست.';
	@override String get errSnapshotFailed => 'ذخیرهٔ نسخهٔ لحظه‌ای داده‌های فعلی ممکن نشد، بنابراین چیزی تغییر نکرد.';
	@override String get errUnresolvedPrevious => 'درون‌ریزی قبلی نیمه‌کاره ماند و هنوز بازگردانی نشده است. چیزی تغییر نکرد. برنامه را دوباره راه‌اندازی کنید و دوباره تلاش کنید.';
	@override String get errRolledBack => 'درون‌ریزی ناموفق بود. داده‌های قبلی شما بازیابی شد.';
	@override String errNotRolledBack({required Object path}) => 'درون‌ریزی ناموفق بود و بازیابی خودکار کامل نشد. برای تلاش دوباره برنامه را راه‌اندازی مجدد کنید. یک نسخهٔ لحظه‌ای در ${path} ذخیره شده است.';
	@override String get errFailed => 'درون‌ریزی ناموفق بود.';
	@override String get errBusy => 'درون‌ریزی دیگری در حال اجراست. لطفاً تا پایان آن صبر کنید.';
	@override String get recoveryFailedTitle => 'بازیابی خودکار کامل نشد';
	@override String get recoveryFailedMsg => 'آخرین درون‌ریزی پشتیبان نیمه‌کاره ماند و برنامه نتوانست داده‌های شما را به حالت قبل برگرداند. ممکن است بخشی از داده‌ها نیمه‌کاره درون‌ریزی شده باشد. اکنون بازیابی خودکار را دوباره امتحان کنید.';
	@override String get recoveryUnrecoverableTitle => 'بازگردانی درون‌ریزی نیمه‌کاره ممکن نشد';
	@override String get recoveryUnrecoverableMsg => 'آخرین درون‌ریزی پشتیبان نیمه‌کاره ماند، اما نسخهٔ لحظه‌ای آن گم شده یا خوانده نمی‌شود و بنابراین نمی‌توان آن را بازگرداند. لطفاً اشتراک‌ها و تنظیمات خود را بررسی کنید.';
	@override String get recoveryRetry => 'تلاش دوباره';
	@override String get recoveryClose => 'بستن';
	@override String get recoveryRetried => 'داده‌های شما به پیش از درون‌ریزی نیمه‌کاره بازیابی شد.';
	@override String get exportAction => 'برون‌بری پشتیبان';
	@override String get importAction => 'درون‌ریزی پشتیبان';
	@override String get exportFailed => 'برون‌بری پشتیبان ناموفق بود';
	@override String get shareText => 'پشتیبان ClashMiao';
}

// Path: settings.general
class Translations$settings$general$fa extends Translations$settings$general$en {
	Translations$settings$general$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'عمومی';
	@override String get locale => 'زبان';
	@override String get region => 'منطقه';
	@override String get regionMsg => 'به انتخاب تنظیمات پیش‌فرض برای دور زدن آدرس‌های داخلی کمک می‌کند';
	@override late final Translations$settings$general$regions$fa regions = Translations$settings$general$regions$fa._(_root);
	@override String get themeMode => 'حالت پوسته';
	@override late final Translations$settings$general$themeModes$fa themeModes = Translations$settings$general$themeModes$fa._(_root);
	@override String get enableAnalytics => 'فعال‌سازی تجزیه و تحلیل‌ها';
	@override String get enableAnalyticsMsg => 'ارائه‌ی دسترسی جمع‌آوری تجزیه و تحلیل‌ها و ارسال گزارش‌های خطا برای بهبود عملکرد برنامه';
	@override String get autoStart => 'راه‌اندازی هنگام شروع سیستم';
	@override String get silentStart => 'اجرای ساکت';
	@override String get openWorkingDir => 'باز کردن دایرکتوری فعال';
	@override String get ignoreBatteryOptimizations => 'غیرفعال کردن بهینه‌سازی باتری';
	@override String get ignoreBatteryOptimizationsMsg => 'برطرف کردن محدودیت‌ها برای عملکرد بهینه‌ی VPN';
	@override String get dynamicNotification => 'نمایش سرعت در نوار اعلان';
	@override String get hapticFeedback => 'بازخورد لمسی';
	@override String get autoIpCheck => 'بررسی خودکار آی‌پی اتصال';
	@override String get autoStartPermission => 'اجازه به اجرای خودکار';
	@override String get autoStartPermissionMsg => 'در صورت فعال بودن، اتصال پس از راه‌اندازی مجدد گوشی یا به‌روزرسانی برنامه به‌طور خودکار برقرار می‌شود';
	@override late final Translations$settings$general$autoStartPermissionStatus$fa autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$fa._(_root);
	@override late final Translations$settings$general$batteryOptimizationStatus$fa batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$fa._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$fa extends Translations$settings$advanced$en {
	Translations$settings$advanced$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'پیشرفته';
	@override String get debugMode => 'حالت اشکال‌زدایی';
	@override String get debugModeMsg => 'برنامه را برای اعمال این تغییر دوباره راه‌اندازی کنید';
	@override String get memoryLimit => 'محدودیت حافظه';
	@override String get memoryLimitMsg => 'اگر با خطاهای کمبود حافظه یا خرابی مکرر برنامه مواجه می‌شوید، این گزینه را فعال کنید';
	@override String get resetTunnel => '‌بازنشانی پروفایل VPN';
	@override String get resetTunnelSuccess => 'پروفایل VPN بازنشانی شد';
}

// Path: settings.network
class Translations$settings$network$fa extends Translations$settings$network$en {
	Translations$settings$network$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'پروکسی براساس برنامه';
	@override late final Translations$settings$network$perAppProxyModes$fa perAppProxyModes = Translations$settings$network$perAppProxyModes$fa._(_root);
	@override String get showSystemApps => 'نمایش برنامه‌های سیستمی';
	@override String get hideSystemApps => 'پنهان کردن برنامه‌های سیستمی';
	@override String get clearSelection => 'پاک کردن انتخاب‌ها';
	@override String get perAppProxyLoadFailedMsg => 'بارگذاری فهرست برنامه‌ها ناموفق بود';
	@override String get perAppProxyRetry => 'تلاش مجدد';
	@override String get perAppProxyEmptyMsg => 'نتیجه‌ای یافت نشد';
	@override String get perAppProxyAndroidOnlyMsg => 'حالت خط برای هر برنامه فقط در Android پشتیبانی می‌شود';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$fa extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'فایل‌های مسیریابی';
	@override String get geoip => 'ژئو آی‌پی';
	@override String get geosite => 'ژئو سایت';
	@override String version({required Object version}) => 'نسخه ${version}';
	@override String get fileMissing => 'فایل موجود نیست';
	@override String get update => 'به‌روزرسانی';
	@override String get download => 'دانلود';
	@override String get failureMsg => 'به‌روزرسانی فایل ناموفق بود';
	@override String get successMsg => 'فایل‌ با موفقیت به‌روزرسانی شد';
	@override String get addRecommended => 'افزودن فایل‌های توصیه‌شده';
	@override String get missingGeoAssetsMsg => 'فایل‌های مسیریابی انتخاب شده وجود ندارند. یا آن‌ها را دانلود کنید و یا یکی از موارد موجود را انتخاب کنید';
}

// Path: settings.groups
class Translations$settings$groups$fa extends Translations$settings$groups$en {
	Translations$settings$groups$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get general => 'عمومی';
	@override String get connection => 'اتصال';
	@override String get privacy => 'حریم خصوصی';
}

// Path: tray.status
class Translations$tray$status$fa extends Translations$tray$status$en {
	Translations$tray$status$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get connect => 'اتصال';
	@override String get connecting => 'در حال اتصال';
	@override String get disconnect => 'قطع اتصال';
	@override String get disconnecting => 'در حال قطع اتصال';
}

// Path: failure.clash
class Translations$failure$clash$fa extends Translations$failure$clash$en {
	Translations$failure$clash$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره';
	@override String core({required Object reason}) => 'خطای Clash ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$fa extends Translations$failure$singbox$en {
	Translations$failure$singbox$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره در سرویس';
	@override String get serviceNotRunning => 'سرویس در حال اجرا نیست';
	@override String get missingPrivilege => 'نیازمند دسترسی';
	@override String get missingPrivilegeMsg => 'حالت VPN به دسترسی ادمین نیاز دارد. یا برنامه را دوباره به‌عنوان ادمین راه‌اندازی کنید یا حالت سرویس را تغییر دهید.';
	@override String get missingGeoAssets => 'فایل‌های جغرافیایی وجود ندارد';
	@override String get missingGeoAssetsMsg => 'فایل‌های جغرافیایی وجود ندارند. یا فایل فعال را تغییر دهید و یا فایل های انتخاب شده را دانلود کنید. ';
	@override String get invalidConfigOptions => 'تنظیمات پیکربندی نامعتبر';
	@override String get invalidConfig => 'پیکربندی نامعتبر';
	@override String get create => 'خطای ایجاد سرویس';
	@override String get start => 'خطای راه‌اندازی سرویس';
	@override String get coreLibraryMissing => 'کتابخانهٔ هسته نصب نشده است';
	@override String get startTimeout => 'زمان راه‌اندازی سرویس به پایان رسید';
	@override String get kernelUnresponsive => 'هسته پاسخ نمی‌دهد. دوباره تلاش کنید یا برنامه را دوباره راه‌اندازی کنید.';
	@override String get kernelExited => 'هسته به‌طور غیرمنتظره متوقف شد';
}

// Path: failure.connectivity
class Translations$failure$connectivity$fa extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره';
	@override String get missingVpnPermission => 'مجوز VPN وجود ندارد';
	@override String get missingNotificationPermission => 'مجوز اعلان وجود ندارد';
	@override String get core => 'خطای هسته';
	@override String get networkUnavailable => 'شبکه در دسترس نیست';
	@override String get nativeUnresponsive => 'ارتباط با سرویس پس‌زمینه قطع شد. دوباره تلاش کنید.';
}

// Path: failure.profiles
class Translations$failure$profiles$fa extends Translations$failure$profiles$en {
	Translations$failure$profiles$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره';
	@override String get notFound => 'پروفایل یافت نشد';
	@override String get invalidConfig => 'پیکربندی‌ها نامعتبر هستند';
	@override String get invalidUrl => 'لینک نامعتبر است';
	@override String get noActive => 'هیچ پروفایل فعالی وجود ندارد';
	@override String get readOnlyUpgrade => 'لطفاً پیش از تغییر اشتراک‌ها برنامه را به‌روزرسانی کنید';
}

// Path: failure.connection
class Translations$failure$connection$fa extends Translations$failure$connection$en {
	Translations$failure$connection$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => ' خطای غیرمنتظره در اتصال';
	@override String get timeout => 'مهلت اتصال به پایان رسید';
	@override String get badResponse => 'پاسخ نامعتبر';
	@override String get connectionError => 'خطای اتصال';
	@override String get badCertificate => 'خطای اعتبارسنجی';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$fa extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطای غیرمنتظره';
	@override String get notUpdate => 'هیچ به‌روزرسانی موجود نیست';
	@override String get activeNotFound => 'فایل جغرافیایی فعال یافت نشد';
}

// Path: config.serviceModes
class Translations$config$serviceModes$fa extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'تنها سرویس پروکسی';
	@override String get systemProxy => 'تنظیم پروکسی سیستم';
	@override String get tun => 'VPN';
	@override String get tunService => 'سرویس VPN';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$fa extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'پروکسی';
	@override String get systemProxy => 'پروکسی سیستم';
	@override String get tun => 'VPN';
	@override String get tunService => 'سرویس VPN';
}

// Path: config.section
class Translations$config$section$fa extends Translations$config$section$en {
	Translations$config$section$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get route => 'تنظیمات مسیریابی';
	@override String get dns => 'تنظیمات DNS';
	@override String get inbound => 'تنظیمات ورودی';
	@override String get mux => 'مالتی پلکسر';
	@override String get outbound => 'تنظیمات خروجی';
	@override String get tlsTricks => 'ترفندهای TLS';
	@override String get warp => 'تنظیمات WARP';
	@override String get misc => 'تنظیمات متفرقه';
}

// Path: config.warpConsent
class Translations$config$warpConsent$fa extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get title => 'توافق‌نامه‌ی Cloudflare WARP';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP یک ارائه‌دهنده‌ی رایگان WireGuard VPN است. با فعال کردن این گزینه، با '),
		tos('شرایط خدمات'),
		const TextSpan(text: ' و '),
		privacy('خط‌ مشی رازداری'),
		const TextSpan(text: ' Cloudflare WARP موافقت می‌کنید.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$fa extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get disable => 'غیرفعال';
	@override String get enable => 'فعال';
	@override String get prefer => 'ترجیح داده شده';
	@override String get only => 'اختصاصی';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$fa extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get proxyOverWarp => 'عبور پروکسی‌ها از طریق WARP';
	@override String get warpOverProxy => 'عبور WARP از طریق پروکسی‌ها';
	@override String get inbound => 'عبور WARP از طریق پروکسی‌ها';
	@override String get outbound => 'عبور پروکسی‌ها از طریق WARP';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$fa extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'دسترسی داده نشد';
	@override String get unexpectedError => 'خطایی رخ داده است';
	@override String get torchSemanticLabel => 'نور فلاش';
	@override String get facingSemanticLabel => 'جهت دوربین';
	@override String get permissionRequest => 'دسترسی به دوربین برای اسکن کد QR';
}

// Path: settings.general.regions
class Translations$settings$general$regions$fa extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get ir => 'ایران (ir)';
	@override String get cn => 'چین (cn)';
	@override String get ru => 'روسیه (ru)';
	@override String get af => 'افغانستان (af)';
	@override String get id => 'إندونيسيا (id)';
	@override String get other => 'سایر';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$fa extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get system => 'پیروی از پوسته‌ی دستگاه';
	@override String get dark => 'حالت تیره';
	@override String get light => 'حالت روشن';
	@override String get black => 'حالت سیاه';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$fa extends Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'فعال';
	@override String get denied => 'غیرفعال';
	@override String get unknown => 'نامشخص';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$fa extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'مستثنی';
	@override String get notExempted => 'مستثنی نشده';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$fa extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$fa._(TranslationsFa root) : this._root = root, super.internal(root);

	final TranslationsFa _root; // ignore: unused_field

	// Translations
	@override String get off => 'همه';
	@override String get offMsg => 'همه‌ی برنامه‌ها پروکسی شوند';
	@override String get include => 'پروکسی';
	@override String get includeMsg => 'تنها برنامه‌های انتخاب‌شده پروکسی شوند';
	@override String get exclude => 'کنار گذاشتن';
	@override String get excludeMsg => 'برنامه‌های انتخاب‌شده پروکسی نشوند';
}

/// The flat map containing all translations for locale <fa>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsFa {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'بازنشانی',
			'general.toggle.enabled' => 'فعال',
			'general.toggle.disabled' => 'غیرفعال',
			'general.state.disable' => 'غیرفعال',
			'general.sort' => 'مرتب‌سازی',
			'general.sortBy' => 'مرتب‌سازی براساس',
			'general.addToClipboard' => 'افزودن به کلیپ‌بورد',
			'general.notSet' => 'تنظیم نشده است',
			'general.agree' => 'پذیرفتن',
			'general.decline' => 'صرف‌نظر کردن',
			'general.unknown' => 'ناشناخته',
			'general.hidden' => 'پنهان',
			'general.timeout' => 'عدم ارتباط',
			'general.clipboardExportSuccessMsg' => 'به کلیپ‌بورد افزوده شد',
			'general.showMore' => 'نمایش بیشتر',
			'general.showLess' => 'نمایش کمتر',
			'general.openAppSettings' => 'باز کردن تنظیمات برنامه',
			'general.grantPermission' => 'اجازه دادن',
			'general.underDevelopment' => 'در حال توسعه',
			'general.confirm' => 'تأیید',
			'general.close' => 'بستن',
			'general.cancel' => 'لغو',
			'general.clipboardEmpty' => 'کلیپ‌بورد خالی است',
			'general.clipboardReadFailed' => 'خواندن کلیپ‌بورد ناموفق بود',
			'general.moreOptions' => 'گزینه‌های بیشتر',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'در صورت ادامه با '), tap(_root.about.termsAndConditions), const TextSpan(text: ' موافقت می‌کنید'), ]), 
			'intro.start' => 'آغاز',
			'home.pageTitle' => 'خانه',
			'home.emptyProfilesMsg' => 'با افزودن یک پروفایل اشتراک شروع کنید',
			'home.noActiveProfileMsg' => 'یک پروفایل انتخاب کنید',
			'home.routingMode.global' => 'پروکسی سراسری',
			'home.routingMode.smart' => 'مسیریابی هوشمند',
			'home.failedToSwitchMode' => ({required Object error}) => 'تغییر حالت ناموفق بود: ${error}',
			'home.connectionFailedTitle' => 'اتصال ناموفق',
			'home.coreMissingTitle' => 'کتابخانهٔ هسته پیدا نشد',
			'home.coreMissingMsg' => 'برنامه نتوانست هستهٔ شبکهٔ خود را بارگذاری کند. اتصال در دسترس نیست. برنامه را دوباره نصب کنید یا مطمئن شوید فایل کتابخانهٔ هسته کنار فایل اجرایی قرار دارد.',
			'home.degradedTitle' => 'متصل است، اما دسترسی به اینترنت وجود ندارد',
			'home.degradedMsg' => 'تونل برقرار است اما ترافیک عبور نمی‌کند. ممکن است نود از کار افتاده باشد — نود دیگری را امتحان کنید یا قطع کنید.',
			'home.degradedRetry' => 'بررسی مجدد',
			'home.egressIp.label' => 'آی‌پی خروجی',
			'home.egressIp.notConnected' => 'برای نمایش آی‌پی خروجی متصل شوید',
			'home.egressIp.tapToCheck' => 'برای بررسی آی‌پی خروجی ضربه بزنید',
			'home.egressIp.checking' => 'در حال بررسی…',
			'home.egressIp.failedRetry' => 'بررسی ناموفق بود، برای تلاش دوباره ضربه بزنید',
			'home.emptyProfilesHint' => 'برای شروع، دکمهٔ زیر را بزنید',
			'home.noActiveProfileTitle' => 'هیچ پروفایلی انتخاب نشده است',
			'stats.traffic' => 'مصرف',
			'stats.trafficLive' => 'مصرف لحظه‌ای',
			'stats.trafficTotal' => 'مصرف کل',
			'stats.uplink' => 'ارسال',
			'stats.downlink' => 'دریافت',
			'stats.connection' => 'اتصال',
			'stats.speed' => 'سرعت',
			'stats.totalTransferred' => 'کل تبادل',
			'stats.trafficUsage' => 'مصرف ترافیک',
			'stats.liveSpeed' => 'سرعت لحظه‌ای',
			'stats.sessionTraffic' => 'ترافیک این نشست',
			'stats.downloadSpeed' => 'سرعت دانلود',
			'profile.overviewPageTitle' => 'پروفایل‌ها',
			'profile.detailsPageTitle' => 'پروفایل',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'نام پروفایل فعال: ${name}',
			'profile.activeProfileBtnSemanticLabel' => 'نمایش همه‌ی پروفایل‌ها',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'انتخاب ${name} به‌عنوان پروفایل فعال',
			'profile.subscription.traffic' => 'ترافیک',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => '${timeago} به‌روزرسانی شد',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '${duration} روز باقی مانده',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed} از ${total} ترافیک مصرف شده',
			'profile.subscription.expired' => 'پایان زمان مجاز',
			'profile.subscription.noTraffic' => 'پایان حجم مجاز',
			'profile.subscription.upload' => 'آپلود',
			'profile.subscription.download' => 'دانلود',
			'profile.subscription.total' => 'کل ترافیک',
			'profile.subscription.expireDate' => 'تاریخ پایان',
			'profile.sortBy.lastUpdate' => 'اخیراً به‌روز شده',
			'profile.sortBy.name' => 'بر اساس نام',
			'profile.add.buttonText' => 'افزودن پروفایل جدید',
			'profile.add.shortBtnTxt' => 'پروفایل جدید',
			'profile.add.fromClipboard' => 'افزودن از کلیپ‌بورد',
			'profile.add.scanQr' => 'اسکن کد QR',
			'profile.add.qrScanner.permissionDeniedError' => 'دسترسی داده نشد',
			'profile.add.qrScanner.unexpectedError' => 'خطایی رخ داده است',
			'profile.add.qrScanner.torchSemanticLabel' => 'نور فلاش',
			'profile.add.qrScanner.facingSemanticLabel' => 'جهت دوربین',
			'profile.add.qrScanner.permissionRequest' => 'دسترسی به دوربین برای اسکن کد QR',
			'profile.add.manually' => 'افزودن دستی',
			'profile.add.addWarp' => 'افزودن وارپ',
			'profile.add.addingWarpMsg' => 'لطفا صبر کنید تا وارپ ثبت شود',
			'profile.add.addingProfileMsg' => 'در حال افزودن پروفایل',
			'profile.add.failureMsg' => 'افزودن پروفایل ناموفق بود',
			'profile.add.modalSubtitle' => 'نحوهٔ افزودن فایل پیکربندی را انتخاب کنید',
			'profile.add.manuallyDescription' => 'پیکربندی سرور را دستی وارد کنید',
			'profile.add.warpDescription' => 'شتاب‌دهی رایگان با Cloudflare WARP',
			'profile.add.importedNamed' => ({required Object name}) => 'اشتراک درون‌ریزی شد: ${name}',
			'profile.add.clipboardEmpty' => 'کلیپ‌بورد خالی است و چیزی برای درون‌ریزی وجود ندارد',
			'profile.add.deepLinkMissingUrl' => 'پیوند نشانی اشتراک ندارد',
			'profile.add.successMsg' => 'پروفایل افزوده شد',
			'profile.add.nameAutoHint' => 'به‌طور خودکار تشخیص داده می‌شود (اختیاری)',
			'profile.update.buttonTxt' => 'به‌روزرسانی',
			'profile.update.tooltip' => 'به‌روزرسانی پروفایل',
			'profile.update.updateSubscriptions' => 'به‌روزرسانی اشتراک‌ها',
			'profile.update.failureMsg' => 'به‌روزرسانی پروفایل ناموفق بود',
			'profile.update.successMsg' => 'پروفایل با موفقیت به‌روزرسانی شد',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'به‌روزرسانی "${name}" ناموفق بود',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" با موفقیت به‌روز شد',
			'profile.share.buttonText' => 'اشتراک‌گذاری',
			'profile.share.exportToClipboardSuccess' => 'به کلیپ‌بورد اضافه شد',
			'profile.share.exportSubLinkToClipboard' => 'صادر کردن لینک اشتراک به کلیپ‌بورد',
			'profile.share.subLinkQrCode' => 'کد QR لینک اشتراک',
			'profile.share.exportConfigToClipboard' => 'افزودن پیکربندی به کلیپ‌بورد',
			'profile.share.exportConfigToClipboardSuccess' => 'پیکربندی در کلیپ‌بورد کپی شد',
			'profile.share.shareLink' => 'اشتراک‌گذاری پیوند',
			'profile.share.subscriptionLinkCopied' => 'پیوند اشتراک کپی شد',
			'profile.share.configCopied' => 'پیکربندی کپی شد',
			'profile.share.copyFailed' => 'کپی ناموفق بود',
			'profile.edit.buttonTxt' => 'ویرایش',
			'profile.edit.selectActiveTxt' => 'انتخاب پروفایل فعال',
			'profile.delete.buttonTxt' => 'حذف',
			'profile.delete.confirmationMsg' => 'پروفایل برای همیشه حذف شود؟',
			'profile.delete.successMsg' => 'پروفایل با موفقیت حذف شد',
			'profile.delete.confirmTitle' => 'حذف پروفایل',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => '«${name}» حذف شود؟ این کار برگشت‌پذیر نیست.',
			'profile.save.buttonText' => 'ذخیره',
			'profile.save.successMsg' => 'پروفایل با موفقیت ذخیره شد',
			'profile.save.failureMsg' => 'خطا در ذخیره‌ی پروفایل',
			'profile.detailsForm.nameLabel' => 'نام',
			'profile.detailsForm.nameHint' => 'نام پروفایل',
			'profile.detailsForm.urlLabel' => 'لینک',
			'profile.detailsForm.urlHint' => 'لینک کامل پیکربندی',
			'profile.detailsForm.emptyNameMsg' => 'نام نمی‌تواند خالی باشد',
			'profile.detailsForm.invalidUrlMsg' => 'لینک نامعتبر است',
			'profile.detailsForm.lastUpdate' => 'آخرین به‌روزرسانی',
			'profile.detailsForm.updateInterval' => 'به‌روزرسانی خودکار',
			'profile.detailsForm.updateIntervalDialogTitle' => 'فاصله‌ی زمانی به‌روزرسانی خودکار (ساعت)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'خاموش',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} ساعت',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} روز',
			'profile.actionButtons.add' => 'افزودن',
			'profile.actionButtons.updateAll' => 'به‌روزرسانی همه',
			'profile.actionButtons.sort' => 'مرتب‌سازی',
			'profile.actionButtons.copyConfigSuccess' => 'پیکربندی کپی شد',
			'profile.actionButtons.editConfig' => 'ویرایش پیکربندی',
			'profile.details.basicInfo' => 'اطلاعات پایه',
			'profile.details.subscriptionStatus' => 'وضعیت اشتراک',
			'profile.details.options' => 'گزینه‌ها',
			'profile.details.updateNow' => 'اکنون به‌روزرسانی کن',
			'profile.details.updateNowDescription' => 'دریافت آخرین پیکربندی از سرور',
			'profile.details.expireDate' => 'تاریخ انقضا',
			'profile.details.unlimited' => 'نامحدود',
			'profile.overview.currentlyUsing' => 'در حال استفاده',
			'profile.overview.remainingDays' => ({required Object days}) => '${days} روز باقی مانده',
			'profile.remoteProfile' => 'پروفایل راه دور',
			'profile.defaultLocalName' => 'درون‌ریزی محلی',
			'profile.defaultDeepLinkName' => 'درون‌ریزی از پیوند',
			'profile.switchFailedMsg' => 'تغییر پروفایل ناموفق بود',
			'proxies.pageTitle' => 'پروکسی‌ها',
			'proxies.emptyProxiesMsg' => 'هیچ پروکسی موجود نیست',
			'proxies.delayTestTooltip' => 'تست تأخیر',
			'proxies.sortTooltip' => 'مرتب‌سازی پروکسی‌ها',
			'proxies.checkIp' => 'بررسی آی‌پی',
			'proxies.unknownIp' => 'آی‌پی ناشناخته',
			'proxies.sortOptions.unsorted' => 'پیش‌فرض',
			'proxies.sortOptions.name' => 'براساس نام',
			'proxies.sortOptions.delay' => 'براساس تأخیر',
			'proxies.activeProxySemanticLabel' => 'پروکسی فعال',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'تأخیر: ${delay}ms',
			'proxies.delaySemantics.timeout' => 'مهلت تست تأخیر به اتمام رسید',
			'proxies.delaySemantics.testing' => 'تأخیر: در حال آزمایش...',
			'proxies.delaySemantics.untested' => 'تأخیر: آزمایش نشده',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'تأخیر: ${delay}ms (نتیجه قبلی)',
			'proxies.ipInfoSemantics.address' => 'آدرس آی‌پی',
			'proxies.ipInfoSemantics.country' => 'کشور',
			'proxies.autoSelect' => 'انتخاب خودکار',
			'proxies.autoSelectDescription' => 'اتصال خودکار به سریع‌ترین نود',
			'proxies.sortModalTitle' => 'روش مرتب‌سازی را انتخاب کنید',
			'proxies.testingDelayInfo' => ({required Object name}) => 'در حال آزمایش تأخیر: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'به ${name} تغییر یافت',
			'proxies.switchFailed' => 'تغییر سرور انجام نشد. لطفاً دوباره تلاش کنید.',
			'proxies.testFailed' => 'آزمون تأخیر ناموفق بود. لطفاً دوباره تلاش کنید.',
			'proxies.groupsLoading' => 'فهرست سرورها هنوز در حال بارگذاری است. لطفاً کمی بعد دوباره تلاش کنید.',
			'proxies.connectBeforeSwitch' => 'پیش از تعویض خط، متصل شوید',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'آزمایش تأخیر برای ${count} خط آغاز شد',
			'proxies.delayTestBtn' => 'تأخیر',
			'proxies.delayTimeout' => 'مهلت تمام',
			'proxies.connectBeforeTest' => 'برای تست تأخیر ابتدا متصل شوید',
			'proxies.lineCount' => ({required Object count}) => '${count} خط',
			'proxies.manualSelect' => 'انتخاب دستی',
			'proxies.autoTest' => 'تست خودکار',
			'logs.pageTitle' => 'گزارش‌ها',
			'logs.filterHint' => 'فیلتر',
			'logs.allLevelsFilter' => 'همه',
			'logs.shareCoreLogs' => 'اشتراک‌گذاری گزارش‌های هسته',
			'logs.shareAppLogs' => 'اشتراک‌گذاری گزارش‌های برنامه',
			'logs.pauseTooltip' => 'مکث',
			'logs.resumeTooltip' => 'ادامه دادن',
			'logs.clearTooltip' => 'پاک‌سازی',
			'logs.logsCleared' => 'گزارش‌ها پاک شد',
			'logs.logsCopied' => 'گزارش‌ها کپی شد',
			'logs.logsUnderDevelopment' => 'قابلیت گزارش‌گیری در حال توسعه است',
			'logs.noLogsWhenDisconnected' => 'متصل نیست، گزارشی وجود ندارد',
			'logs.loadFailed' => 'بارگیری گزارش‌ها ناموفق بود',
			'logs.empty' => 'هنوز گزارشی وجود ندارد',
			'logs.clearFailed' => 'پاک کردن گزارش‌ها ناموفق بود',
			'settings.pageTitle' => 'تنظیمات',
			'settings.requiresRestartMsg' => 'برای اعمال این تنظیم، برنامه را دوباره راه‌اندازی کنید',
			'settings.experimental' => 'آزمایشی',
			'settings.experimentalMsg' => 'تنظیماتی که عنوان آزمایشی دارند، هم‌چنان در دست توسعه هستند و فعال‌سازی آن‌ها می‌تواند باعث بروز مشکلاتی شود. ',
			'settings.exportOptions' => 'کپی تنظیمات ساده به کلیپ‌بورد',
			'settings.exportAllOptions' => 'کپی همه تنظیمات به کلیپ‌بورد',
			'settings.importOptions' => 'وارد کردن تنظیمات از کلیپ‌بورد',
			'settings.importOptionsMsg' => 'این اقدام همه‌ی تنظیمات پیکربندی را با مقادیر اولیه بازنویسی می‌کند. آیا مطمئن هستید؟',
			'settings.backup.importConfirmTitle' => 'درون‌ریزی پشتیبان',
			'settings.backup.importConfirmMsg' => 'این کار اشتراک‌های شما را با اشتراک‌های موجود در پشتیبان جایگزین می‌کند و تنظیمات آن را اعمال می‌کند. ابتدا یک نسخهٔ لحظه‌ای از داده‌های فعلی ذخیره می‌شود و اگر درون‌ریزی ناموفق باشد، خودکار بازیابی می‌شود.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '${count} اشتراک روی این دستگاه در پشتیبان نیست و حذف خواهد شد.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '${profiles} اشتراک و ${settings} تنظیم درون‌ریزی شد.',
			'settings.backup.reportDropped' => ({required Object count}) => '${count} اشتراک در پشتیبان به دلیل نامعتبر بودن داده‌ها نادیده گرفته شد.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '${count} تنظیم نادیده گرفته شد؛ مقدارهای فعلی شما حفظ شدند.',
			'settings.backup.reportWarpOff' => 'درون‌ریزی WARP را خاموش کرد. آن را دوباره روی این دستگاه فعال کنید.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} اشتراک در پس‌زمینه دانلود خواهد شد.',
			'settings.backup.errInvalidFile' => 'این یک فایل پشتیبان معتبر ClashMiao نیست.',
			'settings.backup.errUnsupportedVersion' => 'این قالب پشتیبان پشتیبانی نمی‌شود.',
			'settings.backup.errNewerSchema' => 'این پشتیبان با نسخهٔ جدیدتری از برنامه ساخته شده است. لطفاً ابتدا برنامه را به‌روزرسانی کنید.',
			'settings.backup.errNoUsableProfiles' => 'هیچ‌یک از اشتراک‌های این پشتیبان قابل درون‌ریزی نیست.',
			'settings.backup.errSnapshotFailed' => 'ذخیرهٔ نسخهٔ لحظه‌ای داده‌های فعلی ممکن نشد، بنابراین چیزی تغییر نکرد.',
			'settings.backup.errUnresolvedPrevious' => 'درون‌ریزی قبلی نیمه‌کاره ماند و هنوز بازگردانی نشده است. چیزی تغییر نکرد. برنامه را دوباره راه‌اندازی کنید و دوباره تلاش کنید.',
			'settings.backup.errRolledBack' => 'درون‌ریزی ناموفق بود. داده‌های قبلی شما بازیابی شد.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'درون‌ریزی ناموفق بود و بازیابی خودکار کامل نشد. برای تلاش دوباره برنامه را راه‌اندازی مجدد کنید. یک نسخهٔ لحظه‌ای در ${path} ذخیره شده است.',
			'settings.backup.errFailed' => 'درون‌ریزی ناموفق بود.',
			'settings.backup.errBusy' => 'درون‌ریزی دیگری در حال اجراست. لطفاً تا پایان آن صبر کنید.',
			'settings.backup.recoveryFailedTitle' => 'بازیابی خودکار کامل نشد',
			'settings.backup.recoveryFailedMsg' => 'آخرین درون‌ریزی پشتیبان نیمه‌کاره ماند و برنامه نتوانست داده‌های شما را به حالت قبل برگرداند. ممکن است بخشی از داده‌ها نیمه‌کاره درون‌ریزی شده باشد. اکنون بازیابی خودکار را دوباره امتحان کنید.',
			'settings.backup.recoveryUnrecoverableTitle' => 'بازگردانی درون‌ریزی نیمه‌کاره ممکن نشد',
			'settings.backup.recoveryUnrecoverableMsg' => 'آخرین درون‌ریزی پشتیبان نیمه‌کاره ماند، اما نسخهٔ لحظه‌ای آن گم شده یا خوانده نمی‌شود و بنابراین نمی‌توان آن را بازگرداند. لطفاً اشتراک‌ها و تنظیمات خود را بررسی کنید.',
			'settings.backup.recoveryRetry' => 'تلاش دوباره',
			'settings.backup.recoveryClose' => 'بستن',
			'settings.backup.recoveryRetried' => 'داده‌های شما به پیش از درون‌ریزی نیمه‌کاره بازیابی شد.',
			'settings.backup.exportAction' => 'برون‌بری پشتیبان',
			'settings.backup.importAction' => 'درون‌ریزی پشتیبان',
			'settings.backup.exportFailed' => 'برون‌بری پشتیبان ناموفق بود',
			'settings.backup.shareText' => 'پشتیبان ClashMiao',
			'settings.general.sectionTitle' => 'عمومی',
			'settings.general.locale' => 'زبان',
			'settings.general.region' => 'منطقه',
			'settings.general.regionMsg' => 'به انتخاب تنظیمات پیش‌فرض برای دور زدن آدرس‌های داخلی کمک می‌کند',
			'settings.general.regions.ir' => 'ایران (ir)',
			'settings.general.regions.cn' => 'چین (cn)',
			'settings.general.regions.ru' => 'روسیه (ru)',
			'settings.general.regions.af' => 'افغانستان (af)',
			'settings.general.regions.id' => 'إندونيسيا (id)',
			'settings.general.regions.other' => 'سایر',
			'settings.general.themeMode' => 'حالت پوسته',
			'settings.general.themeModes.system' => 'پیروی از پوسته‌ی دستگاه',
			'settings.general.themeModes.dark' => 'حالت تیره',
			'settings.general.themeModes.light' => 'حالت روشن',
			'settings.general.themeModes.black' => 'حالت سیاه',
			'settings.general.enableAnalytics' => 'فعال‌سازی تجزیه و تحلیل‌ها',
			'settings.general.enableAnalyticsMsg' => 'ارائه‌ی دسترسی جمع‌آوری تجزیه و تحلیل‌ها و ارسال گزارش‌های خطا برای بهبود عملکرد برنامه',
			'settings.general.autoStart' => 'راه‌اندازی هنگام شروع سیستم',
			'settings.general.silentStart' => 'اجرای ساکت',
			'settings.general.openWorkingDir' => 'باز کردن دایرکتوری فعال',
			'settings.general.ignoreBatteryOptimizations' => 'غیرفعال کردن بهینه‌سازی باتری',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'برطرف کردن محدودیت‌ها برای عملکرد بهینه‌ی VPN',
			'settings.general.dynamicNotification' => 'نمایش سرعت در نوار اعلان',
			'settings.general.hapticFeedback' => 'بازخورد لمسی',
			'settings.general.autoIpCheck' => 'بررسی خودکار آی‌پی اتصال',
			'settings.general.autoStartPermission' => 'اجازه به اجرای خودکار',
			'settings.general.autoStartPermissionMsg' => 'در صورت فعال بودن، اتصال پس از راه‌اندازی مجدد گوشی یا به‌روزرسانی برنامه به‌طور خودکار برقرار می‌شود',
			'settings.general.autoStartPermissionStatus.allowed' => 'فعال',
			'settings.general.autoStartPermissionStatus.denied' => 'غیرفعال',
			'settings.general.autoStartPermissionStatus.unknown' => 'نامشخص',
			'settings.general.batteryOptimizationStatus.exempted' => 'مستثنی',
			'settings.general.batteryOptimizationStatus.notExempted' => 'مستثنی نشده',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'پیشرفته',
			'settings.advanced.debugMode' => 'حالت اشکال‌زدایی',
			'settings.advanced.debugModeMsg' => 'برنامه را برای اعمال این تغییر دوباره راه‌اندازی کنید',
			'settings.advanced.memoryLimit' => 'محدودیت حافظه',
			'settings.advanced.memoryLimitMsg' => 'اگر با خطاهای کمبود حافظه یا خرابی مکرر برنامه مواجه می‌شوید، این گزینه را فعال کنید',
			'settings.advanced.resetTunnel' => '‌بازنشانی پروفایل VPN',
			'settings.advanced.resetTunnelSuccess' => 'پروفایل VPN بازنشانی شد',
			'settings.network.perAppProxyPageTitle' => 'پروکسی براساس برنامه',
			'settings.network.perAppProxyModes.off' => 'همه',
			'settings.network.perAppProxyModes.offMsg' => 'همه‌ی برنامه‌ها پروکسی شوند',
			'settings.network.perAppProxyModes.include' => 'پروکسی',
			'settings.network.perAppProxyModes.includeMsg' => 'تنها برنامه‌های انتخاب‌شده پروکسی شوند',
			'settings.network.perAppProxyModes.exclude' => 'کنار گذاشتن',
			'settings.network.perAppProxyModes.excludeMsg' => 'برنامه‌های انتخاب‌شده پروکسی نشوند',
			'settings.network.showSystemApps' => 'نمایش برنامه‌های سیستمی',
			'settings.network.hideSystemApps' => 'پنهان کردن برنامه‌های سیستمی',
			'settings.network.clearSelection' => 'پاک کردن انتخاب‌ها',
			'settings.network.perAppProxyLoadFailedMsg' => 'بارگذاری فهرست برنامه‌ها ناموفق بود',
			'settings.network.perAppProxyRetry' => 'تلاش مجدد',
			'settings.network.perAppProxyEmptyMsg' => 'نتیجه‌ای یافت نشد',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'حالت خط برای هر برنامه فقط در Android پشتیبانی می‌شود',
			'settings.geoAssets.pageTitle' => 'فایل‌های مسیریابی',
			'settings.geoAssets.geoip' => 'ژئو آی‌پی',
			'settings.geoAssets.geosite' => 'ژئو سایت',
			'settings.geoAssets.version' => ({required Object version}) => 'نسخه ${version}',
			'settings.geoAssets.fileMissing' => 'فایل موجود نیست',
			'settings.geoAssets.update' => 'به‌روزرسانی',
			'settings.geoAssets.download' => 'دانلود',
			'settings.geoAssets.failureMsg' => 'به‌روزرسانی فایل ناموفق بود',
			'settings.geoAssets.successMsg' => 'فایل‌ با موفقیت به‌روزرسانی شد',
			'settings.geoAssets.addRecommended' => 'افزودن فایل‌های توصیه‌شده',
			'settings.geoAssets.missingGeoAssetsMsg' => 'فایل‌های مسیریابی انتخاب شده وجود ندارند. یا آن‌ها را دانلود کنید و یا یکی از موارد موجود را انتخاب کنید',
			'settings.systemProxyEnabled' => 'پروکسی سیستم فعال شد',
			'settings.systemProxyDisabled' => 'پروکسی سیستم غیرفعال شد (برای اعمال، دوباره وصل شوید)',
			'settings.adminPrivilegesRequired' => 'در macOS به دسترسی مدیر نیاز است',
			'settings.portChangeNotice' => 'تغییر پورت برای اعمال شدن نیاز به اتصال مجدد دارد',
			'settings.groups.general' => 'عمومی',
			'settings.groups.connection' => 'اتصال',
			'settings.groups.privacy' => 'حریم خصوصی',
			'settings.importOptionsInvalid' => 'محتوای کلیپ‌بورد JSON تنظیمات معتبری نیست',
			'settings.importOptionsNothing' => 'هیچ تنظیم قابل درون‌ریزی پیدا نشد',
			'settings.importOptionsDone' => ({required Object count}) => '${count} تنظیم درون‌ریزی شد',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '${applied} تنظیم درون‌ریزی شد؛ ${skipped} مورد به دلیل نامعتبر بودن رد شد',
			'about.pageTitle' => 'درباره',
			'about.version' => 'نسخه',
			'about.sourceCode' => 'کد منبع',
			'about.telegramChannel' => 'کانال تلگرام',
			'about.checkForUpdate' => 'بررسی برای به‌روزرسانی',
			'about.privacyPolicy' => 'سیاست‌های حفظ حریم خصوصی',
			'about.termsAndConditions' => 'شرایط و ضوابط استفاده',
			'about.appDescription' => 'یک کلاینت پروکسی چندسکویی مبتنی بر هستهٔ sing-box',
			'about.openSourceLicenses' => 'مجوزهای متن‌باز',
			'appUpdate.notAvailableMsg' => 'در حال استفاده از آخرین نسخه هستید',
			'appUpdate.dialogTitle' => 'به‌روزرسانی موجود است',
			'appUpdate.updateMsg' => 'نسخه‌ی جدیدی از general.appTitle در دسترس است. آیا می‌خواهید آن را به‌روزرسانی کنید؟',
			'appUpdate.currentVersionLbl' => 'نسخه‌ی فعلی',
			'appUpdate.newVersionLbl' => 'نسخه‌ی جدید',
			'appUpdate.updateNowBtnTxt' => 'هم‌اکنون به‌روزرسانی شود',
			'appUpdate.laterBtnTxt' => 'بعداً',
			'appUpdate.ignoreBtnTxt' => 'نادیده‌گرفتن',
			'appUpdate.checkFailedMsg' => 'بررسی به‌روزرسانی ناموفق بود. شبکه خود را بررسی کنید و دوباره تلاش کنید.',
			'tray.dashboard' => 'داشبورد',
			'tray.quit' => 'خروج',
			'tray.open' => 'باز کردن',
			'tray.status.connect' => 'اتصال',
			'tray.status.connecting' => 'در حال اتصال',
			'tray.status.disconnect' => 'قطع اتصال',
			'tray.status.disconnecting' => 'در حال قطع اتصال',
			'tray.hide' => 'پنهان کردن',
			'tray.proxyModeMenu' => 'حالت پروکسی',
			'failure.unexpected' => 'خطای غیرمنتظره',
			'failure.clash.unexpected' => 'خطای غیرمنتظره',
			'failure.clash.core' => ({required Object reason}) => 'خطای Clash ${reason}',
			'failure.singbox.unexpected' => 'خطای غیرمنتظره در سرویس',
			'failure.singbox.serviceNotRunning' => 'سرویس در حال اجرا نیست',
			'failure.singbox.missingPrivilege' => 'نیازمند دسترسی',
			'failure.singbox.missingPrivilegeMsg' => 'حالت VPN به دسترسی ادمین نیاز دارد. یا برنامه را دوباره به‌عنوان ادمین راه‌اندازی کنید یا حالت سرویس را تغییر دهید.',
			'failure.singbox.missingGeoAssets' => 'فایل‌های جغرافیایی وجود ندارد',
			'failure.singbox.missingGeoAssetsMsg' => 'فایل‌های جغرافیایی وجود ندارند. یا فایل فعال را تغییر دهید و یا فایل های انتخاب شده را دانلود کنید. ',
			'failure.singbox.invalidConfigOptions' => 'تنظیمات پیکربندی نامعتبر',
			'failure.singbox.invalidConfig' => 'پیکربندی نامعتبر',
			'failure.singbox.create' => 'خطای ایجاد سرویس',
			'failure.singbox.start' => 'خطای راه‌اندازی سرویس',
			'failure.singbox.coreLibraryMissing' => 'کتابخانهٔ هسته نصب نشده است',
			'failure.singbox.startTimeout' => 'زمان راه‌اندازی سرویس به پایان رسید',
			'failure.singbox.kernelUnresponsive' => 'هسته پاسخ نمی‌دهد. دوباره تلاش کنید یا برنامه را دوباره راه‌اندازی کنید.',
			'failure.singbox.kernelExited' => 'هسته به‌طور غیرمنتظره متوقف شد',
			'failure.connectivity.unexpected' => 'خطای غیرمنتظره',
			'failure.connectivity.missingVpnPermission' => 'مجوز VPN وجود ندارد',
			'failure.connectivity.missingNotificationPermission' => 'مجوز اعلان وجود ندارد',
			'failure.connectivity.core' => 'خطای هسته',
			'failure.connectivity.networkUnavailable' => 'شبکه در دسترس نیست',
			'failure.connectivity.nativeUnresponsive' => 'ارتباط با سرویس پس‌زمینه قطع شد. دوباره تلاش کنید.',
			'failure.profiles.unexpected' => 'خطای غیرمنتظره',
			'failure.profiles.notFound' => 'پروفایل یافت نشد',
			'failure.profiles.invalidConfig' => 'پیکربندی‌ها نامعتبر هستند',
			'failure.profiles.invalidUrl' => 'لینک نامعتبر است',
			'failure.profiles.noActive' => 'هیچ پروفایل فعالی وجود ندارد',
			'failure.profiles.readOnlyUpgrade' => 'لطفاً پیش از تغییر اشتراک‌ها برنامه را به‌روزرسانی کنید',
			'failure.connection.unexpected' => ' خطای غیرمنتظره در اتصال',
			'failure.connection.timeout' => 'مهلت اتصال به پایان رسید',
			'failure.connection.badResponse' => 'پاسخ نامعتبر',
			'failure.connection.connectionError' => 'خطای اتصال',
			'failure.connection.badCertificate' => 'خطای اعتبارسنجی',
			'failure.geoAssets.unexpected' => 'خطای غیرمنتظره',
			'failure.geoAssets.notUpdate' => 'هیچ به‌روزرسانی موجود نیست',
			'failure.geoAssets.activeNotFound' => 'فایل جغرافیایی فعال یافت نشد',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'برای اتصال ضربه بزنید',
			'connection.connecting' => 'در حال اتصال',
			'connection.disconnecting' => 'در حال قطع اتصال',
			'connection.connected' => 'متصل شد',
			'connection.reconnect' => 'اتصال دوباره',
			'connection.connectAnyWay' => 'در هر صورت متصل شو',
			'connection.experimentalNotice' => 'ویژگی‌های آزمایشی در حال استفاده',
			'connection.experimentalNoticeMsg' => 'شما برخی از ویژگی‌های آزمایشی را فعال کرده‌اید که ممکن است بر کیفیت اتصال تأثیر گذاشته و باعث بروز خطاهای غیرمنتظره شود. شما همیشه می‌توانید این گزینه‌ها را از صفحه‌ی تنظیمات پیکربندی تغییر دهید یا بازنشانی کنید.',
			'connection.disableExperimentalNotice' => 'دیگر نشان نده',
			'connection.reconnectMsg' => 'در حال اتصال مجدد برای اعمال تغییرات...',
			'connection.staleSystemProxyCleaned' => 'تنظیمات پروکسی سیستم که از خروج غیرعادی قبلی باقی مانده بود پاک شد',
			'config.resetBtn' => 'بازنشانی تنظیمات',
			'config.serviceMode' => 'حالت سرویس',
			'config.quickSettings' => 'تنظیمات سریع',
			'config.setupWarp' => 'راه‌اندازی WARP',
			'config.allOptions' => 'همه‌ی تنظیمات پیکربندی',
			'config.serviceModes.proxy' => 'تنها سرویس پروکسی',
			'config.serviceModes.systemProxy' => 'تنظیم پروکسی سیستم',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'سرویس VPN',
			'config.shortServiceModes.proxy' => 'پروکسی',
			'config.shortServiceModes.systemProxy' => 'پروکسی سیستم',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'سرویس VPN',
			'config.section.route' => 'تنظیمات مسیریابی',
			'config.section.dns' => 'تنظیمات DNS',
			'config.section.inbound' => 'تنظیمات ورودی',
			'config.section.mux' => 'مالتی پلکسر',
			'config.section.outbound' => 'تنظیمات خروجی',
			'config.section.tlsTricks' => 'ترفندهای TLS',
			'config.section.warp' => 'تنظیمات WARP',
			'config.section.misc' => 'تنظیمات متفرقه',
			'config.warpConsent.title' => 'توافق‌نامه‌ی Cloudflare WARP',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP یک ارائه‌دهنده‌ی رایگان WireGuard VPN است. با فعال کردن این گزینه، با '), tos('شرایط خدمات'), const TextSpan(text: ' و '), privacy('خط‌ مشی رازداری'), const TextSpan(text: ' Cloudflare WARP موافقت می‌کنید.'), ]), 
			'config.generateWarpConfig' => 'ایجاد پیکربندی WARP',
			'config.missingWarpConfig' => 'پیکربندی WARP موجود نیست',
			'config.warpConfigGenerated' => 'پیکربندی WARP ایجاد شد',
			'config.pageTitle' => 'تنظیمات پیکربندی',
			'config.logLevel' => 'سطح گزارش',
			'config.blockAds' => 'مسدود سازی تبلیغات',
			'config.resolveDestination' => 'جایگذاری مقصد',
			'config.ipv6Mode' => 'مسیریابی IPv6',
			'config.ipv6Modes.disable' => 'غیرفعال',
			'config.ipv6Modes.enable' => 'فعال',
			'config.ipv6Modes.prefer' => 'ترجیح داده شده',
			'config.ipv6Modes.only' => 'اختصاصی',
			'config.remoteDnsAddress' => 'DNS خارجی',
			'config.remoteDnsDomainStrategy' => 'استراتژی دامنه DNS خارجی',
			'config.directDnsAddress' => 'DNS مستقیم',
			'config.directDnsDomainStrategy' => 'استراتژی دامنه DNS مستقیم',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'اعمال نشد: مسیریابی IPv6 غیرفعال است اما «${field}» فقط IPv6 است، پس هیچ دامنه‌ای حل نمی‌شود. ابتدا مسیریابی IPv6 را فعال کنید یا راهبرد دیگری انتخاب کنید.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'اعمال نشد: مسیریابی IPv6 فقط IPv6 است اما «${field}» فقط IPv4 است، پس هیچ دامنه‌ای حل نمی‌شود. ابتدا یکی از آن‌ها را تغییر دهید.',
			'config.dnsStrategyReset' => ({required Object field}) => '«${field}» با تنظیم مسیریابی IPv6 تعارض داشت (هیچ دامنه‌ای حل نمی‌شد) و به خودکار بازنشانی شد.',
			'config.mixedPort' => 'پورت چندمنظوره',
			'config.tproxyPort' => 'پورت پروکسی نامرئی',
			'config.localDnsPort' => 'پورت DNS داخلی',
			'config.allowConnectionFromLan' => 'اشتراک VPN در شبکه داخلی',
			'config.tunImplementation' => 'پیاده‌سازی TUN',
			'config.mtu' => 'سایز بسته‌ها (MTU) ',
			'config.connectionTestUrl' => 'لینک بررسی اتصال',
			'config.urlTestInterval' => 'فاصله‌ی زمانی بررسی لینک',
			'config.enableClashApi' => 'فعال‌سازی Clash API',
			'config.clashApiPort' => 'پورت Clash API',
			'config.enableTun' => 'فعال‌سازی TUN',
			'config.setSystemProxy' => 'تنظیم پروکسی سیستم',
			'config.enableDnsRouting' => 'فعال‌سازی مسیریابی DNS',
			'config.enableFakeDns' => 'فعال‌سازی DNS جعلی',
			'config.bypassLan' => 'دور زدن LAN',
			'config.strictRoute' => 'مسیر دقیق',
			'config.enableTlsFragment' => 'فعال‌سازی TLS Fragment',
			'config.tlsFragmentSize' => 'اندازه‌ی TLS Fragment ',
			'config.tlsFragmentSleep' => 'کنار گذاشتن TLS Fragment',
			'config.enableTlsMixedSniCase' => 'فعال‌سازی TLS Mixed SNI Case',
			'config.enableTlsPadding' => 'فعال‌سازی TLS Padding',
			'config.tlsPaddingSize' => 'اندازه‌ی TLS Padding',
			'config.enableMux' => 'فعال‌سازی Mux',
			'config.muxProtocol' => 'پروتکل Mux',
			'config.muxMaxStreams' => 'حداکثر جریان‌های هم‌زمان',
			'config.enableWarp' => 'فعال‌سازی WARP',
			'config.setUpWarp' => 'راه‌اندازی WARP',
			'config.warpNotConfigured' => 'پیکربندی نشده',
			'config.warpDetourMode' => 'حالت وارپ',
			'config.warpDetourModes.proxyOverWarp' => 'عبور پروکسی‌ها از طریق WARP',
			'config.warpDetourModes.warpOverProxy' => 'عبور WARP از طریق پروکسی‌ها',
			'config.warpDetourModes.inbound' => 'عبور WARP از طریق پروکسی‌ها',
			'config.warpDetourModes.outbound' => 'عبور پروکسی‌ها از طریق WARP',
			'config.warpLicenseKey' => 'کلید لایسنس',
			'config.warpCleanIp' => 'آی‌پی تمیز',
			'config.warpPort' => 'پورت',
			'config.warpNoise' => 'تعداد نویز',
			'config.warpNoiseSize' => 'اندازه نویز',
			'config.warpNoiseMode' => 'حالت نویز',
			'config.warpNoiseDelay' => 'تأخیر نویز',
			'config.quickSettingsSubtitle' => 'تجربهٔ اتصال خود را سفارشی کنید',
			'config.allAdvancedOptions' => 'همهٔ گزینه‌های پیشرفته',
			'config.desktopProxyScopeNotice' => 'در دسکتاپ، فقط برنامه‌هایی که پروکسی سیستم را رعایت می‌کنند از تونل عبور می‌کنند. نرم‌افزارهایی که آن را نادیده می‌گیرند (برخی بازی‌ها، ابزارهای خط فرمان، برنامه‌های دارای تنظیمات پروکسی مستقل) مستقیم وصل می‌شوند و IP واقعی شما را افشا می‌کنند.',
			'config.serviceModeIosVpnOnly' => 'iOS فقط از حالت VPN پشتیبانی می‌کند',
			'config.warpGenerating' => 'در حال ساخت پیکربندی WARP…',
			'config.warpConfigFailed' => 'ساخت پیکربندی WARP ناموفق بود. لطفاً بعداً دوباره تلاش کنید.',
			'config.portRangeError' => 'پورت باید بین 1024 و 65535 باشد',
			'config.dnsEmptyError' => 'نشانی DNS نمی‌تواند خالی باشد',
			'config.rangeFormatError' => 'یک عدد یا بازه وارد کنید، مثلاً 10-30',
			'config.urlSchemeError' => 'نشانی باید با http:// یا https:// شروع شود',
			'config.manageRuleAssets' => 'مدیریت مجموعه‌قواعد',
			_ => null,
		};
	}
}
