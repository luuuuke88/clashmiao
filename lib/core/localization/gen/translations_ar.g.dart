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
class TranslationsAr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsAr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ar,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <ar>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsAr _root = this; // ignore: unused_field

	@override 
	TranslationsAr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsAr(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$ar general = Translations$general$ar._(_root);
	@override late final Translations$intro$ar intro = Translations$intro$ar._(_root);
	@override late final Translations$home$ar home = Translations$home$ar._(_root);
	@override late final Translations$stats$ar stats = Translations$stats$ar._(_root);
	@override late final Translations$profile$ar profile = Translations$profile$ar._(_root);
	@override late final Translations$proxies$ar proxies = Translations$proxies$ar._(_root);
	@override late final Translations$logs$ar logs = Translations$logs$ar._(_root);
	@override late final Translations$settings$ar settings = Translations$settings$ar._(_root);
	@override late final Translations$about$ar about = Translations$about$ar._(_root);
	@override late final Translations$appUpdate$ar appUpdate = Translations$appUpdate$ar._(_root);
	@override late final Translations$tray$ar tray = Translations$tray$ar._(_root);
	@override late final Translations$failure$ar failure = Translations$failure$ar._(_root);
	@override late final Translations$connection$ar connection = Translations$connection$ar._(_root);
	@override late final Translations$config$ar config = Translations$config$ar._(_root);
}

// Path: general
class Translations$general$ar extends Translations$general$en {
	Translations$general$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'إعادة تعيين';
	@override late final Translations$general$toggle$ar toggle = Translations$general$toggle$ar._(_root);
	@override late final Translations$general$state$ar state = Translations$general$state$ar._(_root);
	@override String get sort => 'فرز';
	@override String get sortBy => 'فرز حسب';
	@override String get addToClipboard => 'إضافة إلى الحافظة';
	@override String get notSet => 'غير مُحدد';
	@override String get agree => 'موافقة';
	@override String get decline => 'رفض';
	@override String get unknown => 'غير معروف';
	@override String get hidden => 'مخفي';
	@override String get timeout => 'انتهاء الوقت';
	@override String get clipboardExportSuccessMsg => 'تمت إضافة البيانات إلى الحافظة';
	@override String get showMore => 'عرض المزيد';
	@override String get showLess => 'عرض أقل';
	@override String get openAppSettings => 'فتح إعدادات التطبيق';
	@override String get grantPermission => 'منح الإذن';
	@override String get underDevelopment => 'قيد التطوير';
	@override String get confirm => 'تأكيد';
	@override String get close => 'إغلاق';
	@override String get cancel => 'إلغاء';
	@override String get clipboardEmpty => 'الحافظة فارغة';
	@override String get clipboardReadFailed => 'تعذّرت قراءة الحافظة';
	@override String get moreOptions => 'خيارات إضافية';
}

// Path: intro
class Translations$intro$ar extends Translations$intro$en {
	Translations$intro$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'بمواصلة استخدامك، فإنك توافق على '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => 'ابدأ';
}

// Path: home
class Translations$home$ar extends Translations$home$en {
	Translations$home$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'الصفحة الرئيسية';
	@override String get emptyProfilesMsg => 'ابدأ بإضافة ملف تعريف اشتراك';
	@override String get noActiveProfileMsg => 'اختر ملف تعريف';
	@override late final Translations$home$routingMode$ar routingMode = Translations$home$routingMode$ar._(_root);
	@override String failedToSwitchMode({required Object error}) => 'فشل تبديل الوضع: ${error}';
	@override String get connectionFailedTitle => 'فشل الاتصال';
	@override String get coreMissingTitle => 'لم يتم العثور على مكتبة النواة';
	@override String get coreMissingMsg => 'تعذّر على التطبيق تحميل نواة الشبكة. الاتصال غير متاح. أعد تثبيت التطبيق أو تأكد من وجود ملف مكتبة النواة بجوار الملف التنفيذي.';
	@override String get degradedTitle => 'متصل، لكن لا يوجد وصول إلى الإنترنت';
	@override String get degradedMsg => 'النفق يعمل لكن البيانات لا تمر. قد يكون الخادم معطلاً — جرّب خادماً آخر أو اقطع الاتصال.';
	@override String get degradedRetry => 'إعادة الفحص';
	@override late final Translations$home$egressIp$ar egressIp = Translations$home$egressIp$ar._(_root);
	@override String get emptyProfilesHint => 'اضغط على الزر أدناه للبدء';
	@override String get noActiveProfileTitle => 'لم يتم اختيار ملف تعريف';
}

// Path: stats
class Translations$stats$ar extends Translations$stats$en {
	Translations$stats$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'حركة المرور';
	@override String get trafficLive => 'حركة المرور الحية';
	@override String get trafficTotal => 'إجمالي حركة المرور';
	@override String get uplink => 'الصعود';
	@override String get downlink => 'الهبوط';
	@override String get connection => 'الاتصال';
	@override String get speed => 'السرعة';
	@override String get totalTransferred => 'إجمالي البيانات المنقولة';
	@override String get trafficUsage => 'استخدام البيانات';
	@override String get liveSpeed => 'السرعة الحالية';
	@override String get sessionTraffic => 'حركة البيانات في هذه الجلسة';
	@override String get downloadSpeed => 'سرعة التنزيل';
}

// Path: profile
class Translations$profile$ar extends Translations$profile$en {
	Translations$profile$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'الملفات الشخصية';
	@override String get detailsPageTitle => 'ملف التعريف';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'اسم ملف التعريف النشط: "${name}".';
	@override String get activeProfileBtnSemanticLabel => 'عرض جميع ملفات التعريف';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'اختر "${name}" كملف تعريف نشط';
	@override late final Translations$profile$subscription$ar subscription = Translations$profile$subscription$ar._(_root);
	@override late final Translations$profile$sortBy$ar sortBy = Translations$profile$sortBy$ar._(_root);
	@override late final Translations$profile$add$ar add = Translations$profile$add$ar._(_root);
	@override late final Translations$profile$update$ar update = Translations$profile$update$ar._(_root);
	@override late final Translations$profile$share$ar share = Translations$profile$share$ar._(_root);
	@override late final Translations$profile$edit$ar edit = Translations$profile$edit$ar._(_root);
	@override late final Translations$profile$delete$ar delete = Translations$profile$delete$ar._(_root);
	@override late final Translations$profile$save$ar save = Translations$profile$save$ar._(_root);
	@override late final Translations$profile$detailsForm$ar detailsForm = Translations$profile$detailsForm$ar._(_root);
	@override late final Translations$profile$actionButtons$ar actionButtons = Translations$profile$actionButtons$ar._(_root);
	@override late final Translations$profile$details$ar details = Translations$profile$details$ar._(_root);
	@override late final Translations$profile$overview$ar overview = Translations$profile$overview$ar._(_root);
	@override String get remoteProfile => 'اشتراك بعيد';
	@override String get defaultLocalName => 'استيراد محلي';
	@override String get defaultDeepLinkName => 'استيراد من رابط';
	@override String get switchFailedMsg => 'تعذّر تبديل ملف التعريف';
}

// Path: proxies
class Translations$proxies$ar extends Translations$proxies$en {
	Translations$proxies$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'الخوادم الوكيلية';
	@override String get emptyProxiesMsg => 'لا توجد خوادم وكيلية متاحة';
	@override String get delayTestTooltip => 'اختبار التأخير';
	@override String get sortTooltip => 'فرز الخوادم الوكيلية';
	@override String get checkIp => 'تحقق من عنوان IP';
	@override String get unknownIp => 'عنوان IP غير معروف';
	@override late final Translations$proxies$sortOptions$ar sortOptions = Translations$proxies$sortOptions$ar._(_root);
	@override String get activeProxySemanticLabel => 'الخادم الوكيل النشط';
	@override late final Translations$proxies$delaySemantics$ar delaySemantics = Translations$proxies$delaySemantics$ar._(_root);
	@override late final Translations$proxies$ipInfoSemantics$ar ipInfoSemantics = Translations$proxies$ipInfoSemantics$ar._(_root);
	@override String get autoSelect => 'اختيار تلقائي';
	@override String get autoSelectDescription => 'الاتصال تلقائياً بأسرع خادم';
	@override String get sortModalTitle => 'اختر طريقة الترتيب';
	@override String testingDelayInfo({required Object name}) => 'جارٍ اختبار التأخير لـ: ${name}';
	@override String switchedTo({required Object name}) => 'تم التبديل إلى ${name}';
	@override String get switchFailed => 'تعذّر تبديل الخادم. يُرجى المحاولة مرة أخرى.';
	@override String get testFailed => 'فشل اختبار زمن الاستجابة. يُرجى المحاولة مرة أخرى.';
	@override String get groupsLoading => 'لا تزال قائمة الخوادم قيد التحميل. يُرجى المحاولة بعد قليل.';
	@override String get connectBeforeSwitch => 'يرجى الاتصال قبل تبديل الخطوط';
	@override String startDelayTestForGroups({required Object count}) => 'بدأ اختبار التأخير لـ ${count} خط';
	@override String get delayTestBtn => 'التأخير';
	@override String get delayTimeout => 'انتهت المهلة';
	@override String get connectBeforeTest => 'اتصل أولاً لاختبار التأخير';
	@override String lineCount({required Object count}) => '${count} خط';
	@override String get manualSelect => 'اختيار يدوي';
	@override String get autoTest => 'اختبار تلقائي';
}

// Path: logs
class Translations$logs$ar extends Translations$logs$en {
	Translations$logs$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'السجلات';
	@override String get filterHint => 'تصفية';
	@override String get allLevelsFilter => 'الكل';
	@override String get shareCoreLogs => 'مشاركة سجلات النواة';
	@override String get shareAppLogs => 'مشاركة سجلات التطبيق';
	@override String get pauseTooltip => 'إيقاف مؤقت';
	@override String get resumeTooltip => 'استئناف';
	@override String get clearTooltip => 'مسح';
	@override String get logsCleared => 'تم مسح السجلات';
	@override String get logsCopied => 'تم نسخ السجلات';
	@override String get logsUnderDevelopment => 'ميزة السجلات قيد التطوير';
	@override String get noLogsWhenDisconnected => 'غير متصل، لا توجد سجلات';
	@override String get loadFailed => 'تعذّر تحميل السجلات';
	@override String get empty => 'لا توجد سجلات بعد';
	@override String get clearFailed => 'تعذّر مسح السجلات';
}

// Path: settings
class Translations$settings$ar extends Translations$settings$en {
	Translations$settings$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'الإعدادات';
	@override String get requiresRestartMsg => 'لتطبيق هذه التغييرات، أعد تشغيل التطبيق';
	@override String get experimental => 'تجريبي';
	@override String get experimentalMsg => 'الميزات ذات العلامة التجريبية لا تزال قيد التطوير وقد تسبب مشاكل.';
	@override String get exportOptions => 'تصدير الخيارات إلى الحافظة';
	@override String get exportAllOptions => 'تصدير جميع الخيارات إلى الحافظة (تصحيح الأخطاء)';
	@override String get importOptions => 'استيراد الخيارات من الحافظة';
	@override String get importOptionsMsg => 'سيؤدي هذا إلى إعادة كتابة جميع خيارات التكوين بالقيم المحددة. هل أنت متأكد؟';
	@override late final Translations$settings$backup$ar backup = Translations$settings$backup$ar._(_root);
	@override late final Translations$settings$general$ar general = Translations$settings$general$ar._(_root);
	@override late final Translations$settings$advanced$ar advanced = Translations$settings$advanced$ar._(_root);
	@override late final Translations$settings$network$ar network = Translations$settings$network$ar._(_root);
	@override late final Translations$settings$geoAssets$ar geoAssets = Translations$settings$geoAssets$ar._(_root);
	@override String get systemProxyEnabled => 'تم تفعيل بروكسي النظام';
	@override String get systemProxyDisabled => 'تم تعطيل بروكسي النظام (أعد الاتصال للتطبيق)';
	@override String get adminPrivilegesRequired => 'يتطلب صلاحيات المسؤول على macOS';
	@override String get portChangeNotice => 'تغييرات المنفذ تتطلب إعادة الاتصال لتفعيلها';
	@override late final Translations$settings$groups$ar groups = Translations$settings$groups$ar._(_root);
	@override String get importOptionsInvalid => 'لا تحتوي الحافظة على JSON إعدادات صالح';
	@override String get importOptionsNothing => 'لم يتم العثور على إعدادات قابلة للاستيراد';
	@override String importOptionsDone({required Object count}) => 'تم استيراد ${count} من الإعدادات';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => 'تم استيراد ${applied} من الإعدادات، وتم تخطي ${skipped} لأنها غير صالحة';
}

// Path: about
class Translations$about$ar extends Translations$about$en {
	Translations$about$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'حول\nتعريب:م. ابراهيم قاسم';
	@override String get version => 'الإصدار';
	@override String get sourceCode => 'رمز المصدر';
	@override String get telegramChannel => 'قناة Telegram';
	@override String get checkForUpdate => 'التحقق من وجود تحديث';
	@override String get privacyPolicy => 'سياسة الخصوصية';
	@override String get termsAndConditions => 'الشروط والأحكام';
	@override String get appDescription => 'عميل بروكسي متعدد المنصات يعتمد على نواة sing-box';
	@override String get openSourceLicenses => 'تراخيص المصدر المفتوح';
}

// Path: appUpdate
class Translations$appUpdate$ar extends Translations$appUpdate$en {
	Translations$appUpdate$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'أنت تستخدم أحدث إصدار بالفعل';
	@override String get dialogTitle => 'تحديث متاح';
	@override String get updateMsg => 'إصدار جديد من ${_root.general.appTitle} متاح. هل تريد التحديث الآن؟';
	@override String get currentVersionLbl => 'الإصدار الحالي';
	@override String get newVersionLbl => 'الإصدار الجديد';
	@override String get updateNowBtnTxt => 'تحديث الآن';
	@override String get laterBtnTxt => 'لاحقًا';
	@override String get ignoreBtnTxt => 'تجاهل';
	@override String get checkFailedMsg => 'تعذّر التحقق من التحديثات. تحقق من اتصالك بالشبكة وحاول مرة أخرى.';
}

// Path: tray
class Translations$tray$ar extends Translations$tray$en {
	Translations$tray$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'لوحة التحكم';
	@override String get quit => 'إنهاء';
	@override String get open => 'فتح';
	@override late final Translations$tray$status$ar status = Translations$tray$status$ar._(_root);
	@override String get hide => 'إخفاء';
	@override String get proxyModeMenu => 'وضع الوكيل';
}

// Path: failure
class Translations$failure$ar extends Translations$failure$en {
	Translations$failure$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ غير متوقع';
	@override late final Translations$failure$clash$ar clash = Translations$failure$clash$ar._(_root);
	@override late final Translations$failure$singbox$ar singbox = Translations$failure$singbox$ar._(_root);
	@override late final Translations$failure$connectivity$ar connectivity = Translations$failure$connectivity$ar._(_root);
	@override late final Translations$failure$profiles$ar profiles = Translations$failure$profiles$ar._(_root);
	@override late final Translations$failure$connection$ar connection = Translations$failure$connection$ar._(_root);
	@override late final Translations$failure$geoAssets$ar geoAssets = Translations$failure$geoAssets$ar._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$ar extends Translations$connection$en {
	Translations$connection$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'انقر للاتصال';
	@override String get connecting => 'جار الاتصال';
	@override String get disconnecting => 'جار فصم الاتصال';
	@override String get connected => 'متصل';
	@override String get reconnect => 'أعد الاتصال';
	@override String get connectAnyWay => 'اتصل على أي حال';
	@override String get experimentalNotice => 'ميزات تجريبية قيد الاستخدام';
	@override String get experimentalNoticeMsg => 'لقد قمت بتمكين بعض الميزات التجريبية التي قد تؤثر على جودة الاتصال وتسبب أخطاء غير متوقعة. يمكنك دائمًا تغيير هذه الخيارات أو إعادة تعيينها من صفحة خيارات التكوين.';
	@override String get disableExperimentalNotice => 'لا تعرض مرة أخرى';
	@override String get reconnectMsg => 'أعد الاتصال ليتم تطبيق التغييرات';
	@override String get staleSystemProxyCleaned => 'تم تنظيف إعدادات وكيل النظام المتبقية من إنهاء غير طبيعي سابق';
}

// Path: config
class Translations$config$ar extends Translations$config$en {
	Translations$config$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'إعادة تعيين الخيارات';
	@override String get serviceMode => 'وضع الخدمة';
	@override String get quickSettings => 'الإعدادات السريعة';
	@override String get setupWarp => 'إعداد WARP';
	@override String get allOptions => 'جميع خيارات التكوين';
	@override late final Translations$config$serviceModes$ar serviceModes = Translations$config$serviceModes$ar._(_root);
	@override late final Translations$config$shortServiceModes$ar shortServiceModes = Translations$config$shortServiceModes$ar._(_root);
	@override late final Translations$config$section$ar section = Translations$config$section$ar._(_root);
	@override late final Translations$config$warpConsent$ar warpConsent = Translations$config$warpConsent$ar._(_root);
	@override String get generateWarpConfig => 'إنشاء تكوين WARP';
	@override String get missingWarpConfig => 'تكوين WARP مفقود';
	@override String get warpConfigGenerated => 'تم إنشاء تكوين WARP';
	@override String get pageTitle => 'خيارات التكوين';
	@override String get logLevel => 'مستوى السجل';
	@override String get resolveDestination => 'حل الوجهة';
	@override String get ipv6Mode => 'توجيه IPv6';
	@override late final Translations$config$ipv6Modes$ar ipv6Modes = Translations$config$ipv6Modes$ar._(_root);
	@override String get remoteDnsAddress => 'DNS البعيد';
	@override String get remoteDnsDomainStrategy => 'استراتيجية مجال DNS البعيد';
	@override String get directDnsAddress => 'DNS المباشر';
	@override String get directDnsDomainStrategy => 'استراتيجية مجال DNS المباشر';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'لم يتم التطبيق: توجيه IPv6 معطّل لكن "${field}" هو IPv6 فقط، لذا لا يمكن حل أي نطاق. فعّل توجيه IPv6 أولاً أو اختر استراتيجية أخرى.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'لم يتم التطبيق: توجيه IPv6 هو IPv6 فقط لكن "${field}" هو IPv4 فقط، لذا لا يمكن حل أي نطاق. عدّل أحدهما أولاً.';
	@override String dnsStrategyReset({required Object field}) => 'تعارض "${field}" مع إعداد توجيه IPv6 (لا يمكن حل أي نطاق) وتمت إعادته إلى تلقائي.';
	@override String get mixedPort => 'منفذ مُختلط';
	@override String get tproxyPort => 'منفذ الوكيل الشفاف';
	@override String get localDnsPort => 'منفذ DNS المحلي';
	@override String get allowConnectionFromLan => 'مشاركة VPN على الشبكة المحلية';
	@override String get tunImplementation => 'تنفيذ TUN';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'عنوان URL لاختبار الاتصال';
	@override String get urlTestInterval => 'مُدة اختبار عنوان URL';
	@override String get enableClashApi => 'تمكين Clash API';
	@override String get clashApiPort => 'منفذ Clash API';
	@override String get enableTun => 'تمكين TUN';
	@override String get setSystemProxy => 'تعيين وكيل النظام';
	@override String get enableDnsRouting => 'تمكين توجيه DNS';
	@override String get enableFakeDns => 'تمكين DNS المزيف';
	@override String get bypassLan => 'تجاوز LAN';
	@override String get strictRoute => 'توجيه صارم';
	@override String get enableTlsFragment => 'تمكين تجزئة TLS';
	@override String get tlsFragmentSize => 'حجم تجزئة TLS';
	@override String get tlsFragmentSleep => 'وقت تعليق تجزئة TLS';
	@override String get enableTlsMixedSniCase => 'تمكين خلط حالات SNI في TLS';
	@override String get enableTlsPadding => 'تمكين حشو TLS';
	@override String get tlsPaddingSize => 'حشو TLS';
	@override String get enableMux => 'تمكين Mux';
	@override String get muxProtocol => 'بروتوكول Mux';
	@override String get muxMaxStreams => 'أقصى عدد من التدفقات المتزامنة';
	@override String get enableWarp => 'تمكين WARP';
	@override String get setUpWarp => 'إعداد WARP';
	@override String get warpNotConfigured => 'غير مهيأ';
	@override String get warpDetourMode => 'وضع التفاف';
	@override late final Translations$config$warpDetourModes$ar warpDetourModes = Translations$config$warpDetourModes$ar._(_root);
	@override String get warpLicenseKey => 'مفتاح الترخيص';
	@override String get warpCleanIp => 'عنوان IP نظيف';
	@override String get warpPort => 'المنفذ';
	@override String get warpNoise => 'عدد الضوضاء';
	@override String get warpNoiseDelay => 'تأخير الضوضاء';
	@override String get quickSettingsSubtitle => 'خصص تجربة الاتصال';
	@override String get allAdvancedOptions => 'جميع الخيارات المتقدمة';
	@override String get blockAds => 'حظر الإعلانات';
	@override String get warpNoiseSize => 'حجم الضجيج';
	@override String get warpNoiseMode => 'وضع الضجيج';
	@override String get desktopProxyScopeNotice => 'على سطح المكتب، يتم توجيه التطبيقات التي تحترم بروكسي النظام فقط عبر النفق. البرامج التي تتجاهله (بعض الألعاب وأدوات سطر الأوامر والتطبيقات ذات إعدادات البروكسي الخاصة) تتصل مباشرة وتكشف عنوان IP الحقيقي.';
	@override String get serviceModeIosVpnOnly => 'يدعم iOS وضع VPN فقط';
	@override String get warpGenerating => 'جارٍ إنشاء إعدادات WARP…';
	@override String get warpConfigFailed => 'تعذّر إنشاء إعدادات WARP. يُرجى المحاولة لاحقًا.';
	@override String get portRangeError => 'يجب أن يكون المنفذ بين 1024 و65535';
	@override String get dnsEmptyError => 'لا يمكن أن يكون عنوان DNS فارغًا';
	@override String get rangeFormatError => 'أدخل رقمًا أو نطاقًا، مثل 10-30';
	@override String get urlSchemeError => 'يجب أن يبدأ الرابط بـ http:// أو https://';
	@override String get manageRuleAssets => 'إدارة مجموعات القواعد';
}

// Path: general.toggle
class Translations$general$toggle$ar extends Translations$general$toggle$en {
	Translations$general$toggle$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'مُفعّل';
	@override String get disabled => 'غير مُفعّل';
}

// Path: general.state
class Translations$general$state$ar extends Translations$general$state$en {
	Translations$general$state$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'تعطيل';
}

// Path: home.routingMode
class Translations$home$routingMode$ar extends Translations$home$routingMode$en {
	Translations$home$routingMode$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get global => 'بروكسي عام';
	@override String get smart => 'توجيه ذكي';
}

// Path: home.egressIp
class Translations$home$egressIp$ar extends Translations$home$egressIp$en {
	Translations$home$egressIp$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get label => 'عنوان IP الخارجي';
	@override String get notConnected => 'اتصل لعرض عنوان IP الخارجي';
	@override String get tapToCheck => 'اضغط للتحقق من عنوان IP الخارجي';
	@override String get checking => 'جارٍ التحقق…';
	@override String get failedRetry => 'فشل التحقق، اضغط لإعادة المحاولة';
}

// Path: profile.subscription
class Translations$profile$subscription$ar extends Translations$profile$subscription$en {
	Translations$profile$subscription$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'حركة المرور';
	@override String updatedTimeAgo({required Object timeago}) => 'تم التحديث قبل ${timeago}';
	@override String remainingDuration({required Object duration}) => 'تبقى ${duration} يومًا';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => 'استُهلك ${consumed} من أصل ${total} حركة مرور';
	@override String get expired => 'منتهي الصلاحية';
	@override String get noTraffic => 'غير متاح';
	@override String get upload => 'التحميل';
	@override String get download => 'التنزيل';
	@override String get total => 'إجمالي حركة المرور';
	@override String get expireDate => 'تاريخ انتهاء الصلاحية';
}

// Path: profile.sortBy
class Translations$profile$sortBy$ar extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'تم التحديث مؤخرًا';
	@override String get name => 'أبجديًا';
}

// Path: profile.add
class Translations$profile$add$ar extends Translations$profile$add$en {
	Translations$profile$add$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'ملف تعريف جديد';
	@override String get shortBtnTxt => 'ملف تعريف جديد';
	@override String get fromClipboard => 'إضافة من الحافظة';
	@override String get scanQr => 'مسح رمز الاستجابة السريعة';
	@override late final Translations$profile$add$qrScanner$ar qrScanner = Translations$profile$add$qrScanner$ar._(_root);
	@override String get manually => 'إدخال يدوي';
	@override String get addingProfileMsg => 'إضافة ملف التعريف';
	@override String get failureMsg => 'فشل في إضافة ملف التعريف';
	@override String get modalSubtitle => 'اختر طريقة إضافة ملف الإعداد';
	@override String get manuallyDescription => 'أدخل إعداد الخادم يدوياً';
	@override String get addWarp => 'إضافة WARP';
	@override String get warpDescription => 'تسريع مجاني عبر Cloudflare WARP';
	@override String get addingWarpMsg => 'يرجى الانتظار أثناء تسجيل WARP.';
	@override String importedNamed({required Object name}) => 'تم استيراد الاشتراك: ${name}';
	@override String get clipboardEmpty => 'الحافظة فارغة، لا يوجد ما يمكن استيراده';
	@override String get deepLinkMissingUrl => 'لا يحتوي الرابط على عنوان اشتراك';
	@override String get successMsg => 'تمت إضافة ملف التعريف';
	@override String get nameAutoHint => 'يُكتشف تلقائيًا (اختياري)';
}

// Path: profile.update
class Translations$profile$update$ar extends Translations$profile$update$en {
	Translations$profile$update$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'تحديث';
	@override String get tooltip => 'تحديث ملف التعريف';
	@override String get updateSubscriptions => 'تحديث الاشتراكات';
	@override String get failureMsg => 'فشل في تحديث ملف التعريف';
	@override String get successMsg => 'تم تحديث ملف التعريف بنجاح';
	@override String namedFailureMsg({required Object name}) => 'فشل في تحديث "${name}"';
	@override String namedSuccessMsg({required Object name}) => 'تم تحديث "${name}" بنجاح';
}

// Path: profile.share
class Translations$profile$share$ar extends Translations$profile$share$en {
	Translations$profile$share$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'مشاركة';
	@override String get exportToClipboardSuccess => 'تم تصدير البيانات إلى الحافظة';
	@override String get exportSubLinkToClipboard => 'تصدير رابط الاشتراك إلى الحافظة';
	@override String get subLinkQrCode => 'رمز الاستجابة السريعة لرابط الاشتراك';
	@override String get exportConfigToClipboard => 'تصدير التكوين إلى الحافظة';
	@override String get exportConfigToClipboardSuccess => 'تم نسخ التكوين إلى الحافظة';
	@override String get shareLink => 'مشاركة الرابط';
	@override String get subscriptionLinkCopied => 'تم نسخ رابط الاشتراك';
	@override String get configCopied => 'تم نسخ الإعداد';
	@override String get copyFailed => 'فشل النسخ';
}

// Path: profile.edit
class Translations$profile$edit$ar extends Translations$profile$edit$en {
	Translations$profile$edit$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'تحرير';
	@override String get selectActiveTxt => 'اختر ملف التعريف النشط';
}

// Path: profile.delete
class Translations$profile$delete$ar extends Translations$profile$delete$en {
	Translations$profile$delete$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'حذف';
	@override String get confirmationMsg => 'حذف ملف التعريف نهائياً؟';
	@override String get successMsg => 'تم حذف ملف التعريف بنجاح';
	@override String get confirmTitle => 'حذف ملف التعريف';
	@override String namedConfirmMsg({required Object name}) => 'هل تريد حذف "${name}"؟ لا يمكن التراجع عن ذلك.';
}

// Path: profile.save
class Translations$profile$save$ar extends Translations$profile$save$en {
	Translations$profile$save$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'حفظ';
	@override String get successMsg => 'تم حفظ ملف التعريف بنجاح';
	@override String get failureMsg => 'فشل في حفظ ملف التعريف';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$ar extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'الاسم';
	@override String get nameHint => 'اسم ملف التعريف';
	@override String get urlLabel => 'العنوان';
	@override String get urlHint => 'عنوان URL للتكوين الكامل';
	@override String get emptyNameMsg => 'الاسم مطلوب';
	@override String get invalidUrlMsg => 'عنوان URL غير صالح';
	@override String get lastUpdate => 'آخر تحديث';
	@override String get updateInterval => 'التحديث التلقائي';
	@override String get updateIntervalDialogTitle => 'مُدة التحديث التلقائي (بالساعات)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'إيقاف';
	@override String updateIntervalHours({required Object hours}) => '${hours} ساعة';
	@override String updateIntervalDays({required Object days}) => '${days} يوم';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$ar extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get add => 'إضافة';
	@override String get updateAll => 'تحديث الكل';
	@override String get sort => 'ترتيب';
	@override String get copyConfigSuccess => 'تم نسخ الإعداد';
	@override String get editConfig => 'تحرير الإعداد';
}

// Path: profile.details
class Translations$profile$details$ar extends Translations$profile$details$en {
	Translations$profile$details$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'معلومات أساسية';
	@override String get subscriptionStatus => 'حالة الاشتراك';
	@override String get options => 'خيارات';
	@override String get updateNow => 'تحديث الآن';
	@override String get updateNowDescription => 'جلب أحدث إعداد من الخادم';
	@override String get expireDate => 'تاريخ الانتهاء';
	@override String get unlimited => 'غير محدود';
}

// Path: profile.overview
class Translations$profile$overview$ar extends Translations$profile$overview$en {
	Translations$profile$overview$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'قيد الاستخدام حالياً';
	@override String remainingDays({required Object days}) => 'متبقٍ ${days} يوماً';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$ar extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'افتراضي';
	@override String get name => 'أبجديًا';
	@override String get delay => 'حسب التأخير';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$ar extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'التأخير: ${delay} مللي ثانية';
	@override String get timeout => 'انتهاء الوقت في اختبار التأخير';
	@override String get testing => 'التأخير: قيد الاختبار...';
	@override String get untested => 'التأخير: لم يُختبر بعد';
	@override String stale({required Object delay}) => 'التأخير: ${delay} مللي ثانية (نتيجة سابقة)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$ar extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get address => 'عنوان IP';
	@override String get country => 'الدولة';
}

// Path: settings.backup
class Translations$settings$backup$ar extends Translations$settings$backup$en {
	Translations$settings$backup$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'استيراد نسخة احتياطية';
	@override String get importConfirmMsg => 'سيؤدي هذا إلى استبدال اشتراكاتك بالاشتراكات الموجودة في النسخة الاحتياطية وتطبيق إعداداتها. يتم أولًا حفظ لقطة من البيانات الحالية وتُستعاد تلقائيًا إذا فشل الاستيراد.';
	@override String importRemovesMsg({required Object count}) => 'يوجد ${count} اشتراك على هذا الجهاز غير موجود في النسخة الاحتياطية وسيتم حذفه.';
	@override String reportImported({required Object profiles, required Object settings}) => 'تم استيراد ${profiles} اشتراك و${settings} إعداد.';
	@override String reportDropped({required Object count}) => 'تم تخطي ${count} اشتراك في النسخة الاحتياطية لأن بياناته غير صالحة.';
	@override String reportSettingsSkipped({required Object count}) => 'تم تخطي ${count} إعداد، وتم الاحتفاظ بقيمك الحالية.';
	@override String get reportWarpOff => 'أدى الاستيراد إلى إيقاف WARP. أعد تفعيله على هذا الجهاز.';
	@override String reportBackfill({required Object count}) => 'سيتم تنزيل ${count} اشتراك في الخلفية.';
	@override String get errInvalidFile => 'هذا ليس ملف نسخة احتياطية صالحًا لـ ClashMiao.';
	@override String get errUnsupportedVersion => 'صيغة هذه النسخة الاحتياطية غير مدعومة.';
	@override String get errNewerSchema => 'تم إنشاء هذه النسخة الاحتياطية بإصدار أحدث من التطبيق. يرجى تحديث التطبيق أولًا.';
	@override String get errNoUsableProfiles => 'لا يمكن استيراد أي من الاشتراكات في هذه النسخة الاحتياطية.';
	@override String get errSnapshotFailed => 'تعذر حفظ لقطة من البيانات الحالية، لذلك لم يتم تغيير أي شيء.';
	@override String get errUnresolvedPrevious => 'توقف استيراد سابق ولم يتم التراجع عنه بعد. لم يتم تغيير أي شيء. أعد تشغيل التطبيق وحاول مرة أخرى.';
	@override String get errRolledBack => 'فشل الاستيراد. تمت استعادة بياناتك السابقة.';
	@override String errNotRolledBack({required Object path}) => 'فشل الاستيراد ولم تكتمل الاستعادة التلقائية. أعد تشغيل التطبيق لإعادة المحاولة. تم حفظ لقطة في ${path}.';
	@override String get errFailed => 'فشل الاستيراد.';
	@override String get errBusy => 'هناك استيراد آخر قيد التنفيذ. يرجى الانتظار حتى ينتهي.';
	@override String get recoveryFailedTitle => 'لم تكتمل الاستعادة التلقائية';
	@override String get recoveryFailedMsg => 'توقف آخر استيراد للنسخة الاحتياطية ولم يتمكن التطبيق من إعادة بياناتك إلى حالتها السابقة. قد تكون بعض البيانات قد استُوردت جزئيًا. أعد محاولة الاستعادة التلقائية الآن.';
	@override String get recoveryUnrecoverableTitle => 'تعذر التراجع عن الاستيراد المتوقف';
	@override String get recoveryUnrecoverableMsg => 'توقف آخر استيراد للنسخة الاحتياطية، لكن لقطته مفقودة أو غير قابلة للقراءة، لذلك لا يمكن التراجع عنه. يرجى مراجعة اشتراكاتك وإعداداتك.';
	@override String get recoveryRetry => 'إعادة المحاولة';
	@override String get recoveryClose => 'إغلاق';
	@override String get recoveryRetried => 'تمت استعادة بياناتك إلى ما قبل الاستيراد المتوقف.';
	@override String get exportAction => 'تصدير نسخة احتياطية';
	@override String get importAction => 'استيراد نسخة احتياطية';
	@override String get exportFailed => 'تعذّر تصدير النسخة الاحتياطية';
	@override String get shareText => 'نسخة ClashMiao الاحتياطية';
}

// Path: settings.general
class Translations$settings$general$ar extends Translations$settings$general$en {
	Translations$settings$general$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'عام';
	@override String get locale => 'اللغة';
	@override String get region => 'المنطقة';
	@override String get regionMsg => 'يساعد على تعيين الخيارات الافتراضية لتجاوز العناوين المحلية';
	@override late final Translations$settings$general$regions$ar regions = Translations$settings$general$regions$ar._(_root);
	@override String get themeMode => 'وضع السمة';
	@override late final Translations$settings$general$themeModes$ar themeModes = Translations$settings$general$themeModes$ar._(_root);
	@override String get enableAnalytics => 'تمكين التحليلات';
	@override String get enableAnalyticsMsg => 'منح الإذن بجمع التحليلات وإرسال تقارير الأعطال لتحسين التطبيق';
	@override String get autoStart => 'بدء التشغيل عند تسجيل الدخول';
	@override String get silentStart => 'بدء التشغيل مُصغر';
	@override String get openWorkingDir => 'فتح دليل العمل';
	@override String get ignoreBatteryOptimizations => 'تعطيل تحسينات البطارية';
	@override String get ignoreBatteryOptimizationsMsg => 'إزالة القيود للحصول على أفضل أداء VPN';
	@override String get dynamicNotification => 'عرض السرعة في الإشعار';
	@override String get hapticFeedback => 'ردود فعل اللمس';
	@override String get autoIpCheck => 'التحقق من عنوان IP للاتصال تلقائيًا';
	@override late final Translations$settings$general$batteryOptimizationStatus$ar batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$ar._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$ar extends Translations$settings$advanced$en {
	Translations$settings$advanced$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'متقدم';
	@override String get debugMode => 'وضع تصحيح الأخطاء';
	@override String get debugModeMsg => 'أعد تشغيل التطبيق لتطبيق هذا التغيير';
	@override String get memoryLimit => 'حد الذاكرة';
	@override String get memoryLimitMsg => 'قم بتمكين هذه الميزة إذا كنت تواجه أخطاء «عدم كفاية الذاكرة» أو تعطل التطبيق بشكل متكرر';
	@override String get resetTunnel => 'إعادة تعيين ملف تعريف VPN';
	@override String get resetTunnelSuccess => 'تمت إعادة تعيين ملف VPN';
}

// Path: settings.network
class Translations$settings$network$ar extends Translations$settings$network$en {
	Translations$settings$network$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'الوكيل لكل تطبيق';
	@override late final Translations$settings$network$perAppProxyModes$ar perAppProxyModes = Translations$settings$network$perAppProxyModes$ar._(_root);
	@override String get showSystemApps => 'عرض تطبيقات النظام';
	@override String get hideSystemApps => 'إخفاء تطبيقات النظام';
	@override String get clearSelection => 'مسح الاختيار';
	@override String get perAppProxyLoadFailedMsg => 'فشل تحميل قائمة التطبيقات';
	@override String get perAppProxyRetry => 'إعادة المحاولة';
	@override String get perAppProxyEmptyMsg => 'لا توجد نتائج';
	@override String get perAppProxyAndroidOnlyMsg => 'وضع الخط لكل تطبيق مدعوم على Android فقط';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$ar extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'أصول التوجيه';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'GeoSite';
	@override String version({required Object version}) => 'الإصدار ${version}';
	@override String get fileMissing => 'الملف مفقود';
	@override String get update => 'تحديث';
	@override String get download => 'تنزيل';
	@override String get failureMsg => 'فشل في تحديث الأصل';
	@override String get successMsg => 'تم تحديث الأصل بنجاح';
	@override String get addRecommended => 'إضافة الأصول الموصى بها';
	@override String get missingGeoAssetsMsg => 'ملفات أصول التوجيه المحددة مفقودة. قم بتنزيلها أو اختر ملفات موجودة';
}

// Path: settings.groups
class Translations$settings$groups$ar extends Translations$settings$groups$en {
	Translations$settings$groups$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get general => 'عام';
	@override String get connection => 'الاتصال';
	@override String get privacy => 'الخصوصية';
}

// Path: tray.status
class Translations$tray$status$ar extends Translations$tray$status$en {
	Translations$tray$status$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get connect => 'الاتصال';
	@override String get connecting => 'جار الاتصال';
	@override String get disconnect => 'فصم الاتصال';
	@override String get disconnecting => 'جار فصم الاتصال';
}

// Path: failure.clash
class Translations$failure$clash$ar extends Translations$failure$clash$en {
	Translations$failure$clash$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ غير متوقع';
	@override String core({required Object reason}) => 'خطأ في Clash ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$ar extends Translations$failure$singbox$en {
	Translations$failure$singbox$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ في الخدمة غير متوقع';
	@override String get serviceNotRunning => 'الخدمة غير قيد التشغيل';
	@override String get missingPrivilege => 'غياب الامتياز';
	@override String get missingPrivilegeMsg => 'وضع VPN يتطلب امتيازات المسؤول. أعد تشغيل التطبيق كمسؤول أو غيّر وضع الخدمة.';
	@override String get missingGeoAssets => 'أصول Geo مفقودة';
	@override String get missingGeoAssetsMsg => 'أصول Geo مفقودة. فكر في تغيير الأصل النشط أو تنزيل الأصل المحدد في الإعدادات.';
	@override String get invalidConfigOptions => 'خيارات التكوين غير صحيحة';
	@override String get invalidConfig => 'تكوين غير صالح';
	@override String get create => 'خطأ في إنشاء الخدمة';
	@override String get start => 'خطأ في بدء تشغيل الخدمة';
	@override String get coreLibraryMissing => 'مكتبة النواة غير مثبتة';
	@override String get startTimeout => 'انتهت مهلة بدء الخدمة';
	@override String get kernelUnresponsive => 'النواة لا تستجيب. حاول مرة أخرى أو أعد تشغيل التطبيق.';
	@override String get kernelExited => 'توقفت النواة بشكل غير متوقع';
}

// Path: failure.connectivity
class Translations$failure$connectivity$ar extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'فشل غير متوقع';
	@override String get missingVpnPermission => 'غياب إذن VPN';
	@override String get missingNotificationPermission => 'غياب إذن الإشعارات';
	@override String get core => 'خطأ في النواة';
	@override String get networkUnavailable => 'الشبكة غير متاحة';
	@override String get nativeUnresponsive => 'فُقد الاتصال بالخدمة الخلفية. حاول مرة أخرى.';
}

// Path: failure.profiles
class Translations$failure$profiles$ar extends Translations$failure$profiles$en {
	Translations$failure$profiles$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ غير متوقع';
	@override String get notFound => 'لم يتم العثور على ملف التعريف';
	@override String get invalidConfig => 'تكوينات غير صحيحة';
	@override String get invalidUrl => 'عنوان URL غير صالح';
	@override String get noActive => 'لا يوجد اشتراك مفعّل';
	@override String get readOnlyUpgrade => 'يرجى ترقية التطبيق قبل تعديل الاشتراكات';
}

// Path: failure.connection
class Translations$failure$connection$ar extends Translations$failure$connection$en {
	Translations$failure$connection$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ في الاتصال غير متوقع';
	@override String get timeout => 'انتهاء الوقت في الاتصال';
	@override String get badResponse => 'استجابة سيئة';
	@override String get connectionError => 'خطأ في الاتصال';
	@override String get badCertificate => 'شهادة غير صالحة';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$ar extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'خطأ غير متوقع';
	@override String get notUpdate => 'لا يوجد تحديث متاح';
	@override String get activeNotFound => 'لم يتم العثور على أصل Geo النشط';
}

// Path: config.serviceModes
class Translations$config$serviceModes$ar extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'خدمة الوكيل فقط';
	@override String get systemProxy => 'تعيين وكيل النظام';
	@override String get tun => 'VPN';
	@override String get tunService => 'خدمة VPN';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$ar extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'وكيل';
	@override String get systemProxy => 'وكيل النظام';
	@override String get tun => 'VPN';
	@override String get tunService => 'خدمة VPN';
}

// Path: config.section
class Translations$config$section$ar extends Translations$config$section$en {
	Translations$config$section$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get route => 'خيارات التوجيه';
	@override String get dns => 'خيارات DNS';
	@override String get inbound => 'خيارات الوارد';
	@override String get mux => 'MultiPlexer';
	@override String get outbound => 'خيارات الخارج';
	@override String get tlsTricks => 'حيل TLS';
	@override String get warp => 'خيارات WARP';
	@override String get misc => 'خيارات متنوعة';
}

// Path: config.warpConsent
class Translations$config$warpConsent$ar extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get title => 'موافقة Cloudflare WARP';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP هو مزود VPN مجاني لـ WireGuard. بتمكين هذا الخيار، فإنك توافق على '),
		tos('Terms of Service'),
		const TextSpan(text: ' و '),
		privacy('Privacy Policy'),
		const TextSpan(text: ' لـ Cloudflare WARP.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$ar extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'تعطيل';
	@override String get enable => 'تمكين';
	@override String get prefer => 'مُفضل';
	@override String get only => 'حصري';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$ar extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get proxyOverWarp => 'لف الخوادم الوكيلية عبر WARP';
	@override String get warpOverProxy => 'لف WARP عبر الخوادم الوكيلية';
	@override String get inbound => 'لف WARP عبر الخوادم الوكيلية';
	@override String get outbound => 'لف الخوادم الوكيلية عبر WARP';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$ar extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'تم رفض الإذن';
	@override String get unexpectedError => 'حدث خطأ ما';
	@override String get torchSemanticLabel => 'ضوء فلاش';
	@override String get facingSemanticLabel => 'اتجاه الكاميرا';
	@override String get permissionRequest => 'الإذن للكاميرا لمسح رمز الاستجابة السريعة';
}

// Path: settings.general.regions
class Translations$settings$general$regions$ar extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get ir => 'إيران (ir)';
	@override String get cn => 'الصين (cn)';
	@override String get ru => 'روسيا (ru)';
	@override String get af => 'أفغانستان (af)';
	@override String get id => 'إندونيسيا (id)';
	@override String get other => 'أخرى';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$ar extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get system => 'اتباع سمة النظام';
	@override String get dark => 'الوضع الداكن';
	@override String get light => 'الوضع الفاتح';
	@override String get black => 'الوضع الأسود';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$ar extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'مُستثنى';
	@override String get notExempted => 'غير مُستثنى';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$ar extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$ar._(TranslationsAr root) : this._root = root, super.internal(root);

	final TranslationsAr _root; // ignore: unused_field

	// Translations
	@override String get off => 'الكل';
	@override String get offMsg => 'وكيل جميع التطبيقات';
	@override String get include => 'وكيل';
	@override String get includeMsg => 'وكيل التطبيقات المحددة فقط';
	@override String get exclude => 'تجاوز';
	@override String get excludeMsg => 'لا تستخدم الوكيل للتطبيقات المحددة';
}

/// The flat map containing all translations for locale <ar>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsAr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'إعادة تعيين',
			'general.toggle.enabled' => 'مُفعّل',
			'general.toggle.disabled' => 'غير مُفعّل',
			'general.state.disable' => 'تعطيل',
			'general.sort' => 'فرز',
			'general.sortBy' => 'فرز حسب',
			'general.addToClipboard' => 'إضافة إلى الحافظة',
			'general.notSet' => 'غير مُحدد',
			'general.agree' => 'موافقة',
			'general.decline' => 'رفض',
			'general.unknown' => 'غير معروف',
			'general.hidden' => 'مخفي',
			'general.timeout' => 'انتهاء الوقت',
			'general.clipboardExportSuccessMsg' => 'تمت إضافة البيانات إلى الحافظة',
			'general.showMore' => 'عرض المزيد',
			'general.showLess' => 'عرض أقل',
			'general.openAppSettings' => 'فتح إعدادات التطبيق',
			'general.grantPermission' => 'منح الإذن',
			'general.underDevelopment' => 'قيد التطوير',
			'general.confirm' => 'تأكيد',
			'general.close' => 'إغلاق',
			'general.cancel' => 'إلغاء',
			'general.clipboardEmpty' => 'الحافظة فارغة',
			'general.clipboardReadFailed' => 'تعذّرت قراءة الحافظة',
			'general.moreOptions' => 'خيارات إضافية',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'بمواصلة استخدامك، فإنك توافق على '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => 'ابدأ',
			'home.pageTitle' => 'الصفحة الرئيسية',
			'home.emptyProfilesMsg' => 'ابدأ بإضافة ملف تعريف اشتراك',
			'home.noActiveProfileMsg' => 'اختر ملف تعريف',
			'home.routingMode.global' => 'بروكسي عام',
			'home.routingMode.smart' => 'توجيه ذكي',
			'home.failedToSwitchMode' => ({required Object error}) => 'فشل تبديل الوضع: ${error}',
			'home.connectionFailedTitle' => 'فشل الاتصال',
			'home.coreMissingTitle' => 'لم يتم العثور على مكتبة النواة',
			'home.coreMissingMsg' => 'تعذّر على التطبيق تحميل نواة الشبكة. الاتصال غير متاح. أعد تثبيت التطبيق أو تأكد من وجود ملف مكتبة النواة بجوار الملف التنفيذي.',
			'home.degradedTitle' => 'متصل، لكن لا يوجد وصول إلى الإنترنت',
			'home.degradedMsg' => 'النفق يعمل لكن البيانات لا تمر. قد يكون الخادم معطلاً — جرّب خادماً آخر أو اقطع الاتصال.',
			'home.degradedRetry' => 'إعادة الفحص',
			'home.egressIp.label' => 'عنوان IP الخارجي',
			'home.egressIp.notConnected' => 'اتصل لعرض عنوان IP الخارجي',
			'home.egressIp.tapToCheck' => 'اضغط للتحقق من عنوان IP الخارجي',
			'home.egressIp.checking' => 'جارٍ التحقق…',
			'home.egressIp.failedRetry' => 'فشل التحقق، اضغط لإعادة المحاولة',
			'home.emptyProfilesHint' => 'اضغط على الزر أدناه للبدء',
			'home.noActiveProfileTitle' => 'لم يتم اختيار ملف تعريف',
			'stats.traffic' => 'حركة المرور',
			'stats.trafficLive' => 'حركة المرور الحية',
			'stats.trafficTotal' => 'إجمالي حركة المرور',
			'stats.uplink' => 'الصعود',
			'stats.downlink' => 'الهبوط',
			'stats.connection' => 'الاتصال',
			'stats.speed' => 'السرعة',
			'stats.totalTransferred' => 'إجمالي البيانات المنقولة',
			'stats.trafficUsage' => 'استخدام البيانات',
			'stats.liveSpeed' => 'السرعة الحالية',
			'stats.sessionTraffic' => 'حركة البيانات في هذه الجلسة',
			'stats.downloadSpeed' => 'سرعة التنزيل',
			'profile.overviewPageTitle' => 'الملفات الشخصية',
			'profile.detailsPageTitle' => 'ملف التعريف',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'اسم ملف التعريف النشط: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'عرض جميع ملفات التعريف',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'اختر "${name}" كملف تعريف نشط',
			'profile.subscription.traffic' => 'حركة المرور',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => 'تم التحديث قبل ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => 'تبقى ${duration} يومًا',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => 'استُهلك ${consumed} من أصل ${total} حركة مرور',
			'profile.subscription.expired' => 'منتهي الصلاحية',
			'profile.subscription.noTraffic' => 'غير متاح',
			'profile.subscription.upload' => 'التحميل',
			'profile.subscription.download' => 'التنزيل',
			'profile.subscription.total' => 'إجمالي حركة المرور',
			'profile.subscription.expireDate' => 'تاريخ انتهاء الصلاحية',
			'profile.sortBy.lastUpdate' => 'تم التحديث مؤخرًا',
			'profile.sortBy.name' => 'أبجديًا',
			'profile.add.buttonText' => 'ملف تعريف جديد',
			'profile.add.shortBtnTxt' => 'ملف تعريف جديد',
			'profile.add.fromClipboard' => 'إضافة من الحافظة',
			'profile.add.scanQr' => 'مسح رمز الاستجابة السريعة',
			'profile.add.qrScanner.permissionDeniedError' => 'تم رفض الإذن',
			'profile.add.qrScanner.unexpectedError' => 'حدث خطأ ما',
			'profile.add.qrScanner.torchSemanticLabel' => 'ضوء فلاش',
			'profile.add.qrScanner.facingSemanticLabel' => 'اتجاه الكاميرا',
			'profile.add.qrScanner.permissionRequest' => 'الإذن للكاميرا لمسح رمز الاستجابة السريعة',
			'profile.add.manually' => 'إدخال يدوي',
			'profile.add.addingProfileMsg' => 'إضافة ملف التعريف',
			'profile.add.failureMsg' => 'فشل في إضافة ملف التعريف',
			'profile.add.modalSubtitle' => 'اختر طريقة إضافة ملف الإعداد',
			'profile.add.manuallyDescription' => 'أدخل إعداد الخادم يدوياً',
			'profile.add.addWarp' => 'إضافة WARP',
			'profile.add.warpDescription' => 'تسريع مجاني عبر Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'يرجى الانتظار أثناء تسجيل WARP.',
			'profile.add.importedNamed' => ({required Object name}) => 'تم استيراد الاشتراك: ${name}',
			'profile.add.clipboardEmpty' => 'الحافظة فارغة، لا يوجد ما يمكن استيراده',
			'profile.add.deepLinkMissingUrl' => 'لا يحتوي الرابط على عنوان اشتراك',
			'profile.add.successMsg' => 'تمت إضافة ملف التعريف',
			'profile.add.nameAutoHint' => 'يُكتشف تلقائيًا (اختياري)',
			'profile.update.buttonTxt' => 'تحديث',
			'profile.update.tooltip' => 'تحديث ملف التعريف',
			'profile.update.updateSubscriptions' => 'تحديث الاشتراكات',
			'profile.update.failureMsg' => 'فشل في تحديث ملف التعريف',
			'profile.update.successMsg' => 'تم تحديث ملف التعريف بنجاح',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'فشل في تحديث "${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => 'تم تحديث "${name}" بنجاح',
			'profile.share.buttonText' => 'مشاركة',
			'profile.share.exportToClipboardSuccess' => 'تم تصدير البيانات إلى الحافظة',
			'profile.share.exportSubLinkToClipboard' => 'تصدير رابط الاشتراك إلى الحافظة',
			'profile.share.subLinkQrCode' => 'رمز الاستجابة السريعة لرابط الاشتراك',
			'profile.share.exportConfigToClipboard' => 'تصدير التكوين إلى الحافظة',
			'profile.share.exportConfigToClipboardSuccess' => 'تم نسخ التكوين إلى الحافظة',
			'profile.share.shareLink' => 'مشاركة الرابط',
			'profile.share.subscriptionLinkCopied' => 'تم نسخ رابط الاشتراك',
			'profile.share.configCopied' => 'تم نسخ الإعداد',
			'profile.share.copyFailed' => 'فشل النسخ',
			'profile.edit.buttonTxt' => 'تحرير',
			'profile.edit.selectActiveTxt' => 'اختر ملف التعريف النشط',
			'profile.delete.buttonTxt' => 'حذف',
			'profile.delete.confirmationMsg' => 'حذف ملف التعريف نهائياً؟',
			'profile.delete.successMsg' => 'تم حذف ملف التعريف بنجاح',
			'profile.delete.confirmTitle' => 'حذف ملف التعريف',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => 'هل تريد حذف "${name}"؟ لا يمكن التراجع عن ذلك.',
			'profile.save.buttonText' => 'حفظ',
			'profile.save.successMsg' => 'تم حفظ ملف التعريف بنجاح',
			'profile.save.failureMsg' => 'فشل في حفظ ملف التعريف',
			'profile.detailsForm.nameLabel' => 'الاسم',
			'profile.detailsForm.nameHint' => 'اسم ملف التعريف',
			'profile.detailsForm.urlLabel' => 'العنوان',
			'profile.detailsForm.urlHint' => 'عنوان URL للتكوين الكامل',
			'profile.detailsForm.emptyNameMsg' => 'الاسم مطلوب',
			'profile.detailsForm.invalidUrlMsg' => 'عنوان URL غير صالح',
			'profile.detailsForm.lastUpdate' => 'آخر تحديث',
			'profile.detailsForm.updateInterval' => 'التحديث التلقائي',
			'profile.detailsForm.updateIntervalDialogTitle' => 'مُدة التحديث التلقائي (بالساعات)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'إيقاف',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} ساعة',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} يوم',
			'profile.actionButtons.add' => 'إضافة',
			'profile.actionButtons.updateAll' => 'تحديث الكل',
			'profile.actionButtons.sort' => 'ترتيب',
			'profile.actionButtons.copyConfigSuccess' => 'تم نسخ الإعداد',
			'profile.actionButtons.editConfig' => 'تحرير الإعداد',
			'profile.details.basicInfo' => 'معلومات أساسية',
			'profile.details.subscriptionStatus' => 'حالة الاشتراك',
			'profile.details.options' => 'خيارات',
			'profile.details.updateNow' => 'تحديث الآن',
			'profile.details.updateNowDescription' => 'جلب أحدث إعداد من الخادم',
			'profile.details.expireDate' => 'تاريخ الانتهاء',
			'profile.details.unlimited' => 'غير محدود',
			'profile.overview.currentlyUsing' => 'قيد الاستخدام حالياً',
			'profile.overview.remainingDays' => ({required Object days}) => 'متبقٍ ${days} يوماً',
			'profile.remoteProfile' => 'اشتراك بعيد',
			'profile.defaultLocalName' => 'استيراد محلي',
			'profile.defaultDeepLinkName' => 'استيراد من رابط',
			'profile.switchFailedMsg' => 'تعذّر تبديل ملف التعريف',
			'proxies.pageTitle' => 'الخوادم الوكيلية',
			'proxies.emptyProxiesMsg' => 'لا توجد خوادم وكيلية متاحة',
			'proxies.delayTestTooltip' => 'اختبار التأخير',
			'proxies.sortTooltip' => 'فرز الخوادم الوكيلية',
			'proxies.checkIp' => 'تحقق من عنوان IP',
			'proxies.unknownIp' => 'عنوان IP غير معروف',
			'proxies.sortOptions.unsorted' => 'افتراضي',
			'proxies.sortOptions.name' => 'أبجديًا',
			'proxies.sortOptions.delay' => 'حسب التأخير',
			'proxies.activeProxySemanticLabel' => 'الخادم الوكيل النشط',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'التأخير: ${delay} مللي ثانية',
			'proxies.delaySemantics.timeout' => 'انتهاء الوقت في اختبار التأخير',
			'proxies.delaySemantics.testing' => 'التأخير: قيد الاختبار...',
			'proxies.delaySemantics.untested' => 'التأخير: لم يُختبر بعد',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'التأخير: ${delay} مللي ثانية (نتيجة سابقة)',
			'proxies.ipInfoSemantics.address' => 'عنوان IP',
			'proxies.ipInfoSemantics.country' => 'الدولة',
			'proxies.autoSelect' => 'اختيار تلقائي',
			'proxies.autoSelectDescription' => 'الاتصال تلقائياً بأسرع خادم',
			'proxies.sortModalTitle' => 'اختر طريقة الترتيب',
			'proxies.testingDelayInfo' => ({required Object name}) => 'جارٍ اختبار التأخير لـ: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'تم التبديل إلى ${name}',
			'proxies.switchFailed' => 'تعذّر تبديل الخادم. يُرجى المحاولة مرة أخرى.',
			'proxies.testFailed' => 'فشل اختبار زمن الاستجابة. يُرجى المحاولة مرة أخرى.',
			'proxies.groupsLoading' => 'لا تزال قائمة الخوادم قيد التحميل. يُرجى المحاولة بعد قليل.',
			'proxies.connectBeforeSwitch' => 'يرجى الاتصال قبل تبديل الخطوط',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'بدأ اختبار التأخير لـ ${count} خط',
			'proxies.delayTestBtn' => 'التأخير',
			'proxies.delayTimeout' => 'انتهت المهلة',
			'proxies.connectBeforeTest' => 'اتصل أولاً لاختبار التأخير',
			'proxies.lineCount' => ({required Object count}) => '${count} خط',
			'proxies.manualSelect' => 'اختيار يدوي',
			'proxies.autoTest' => 'اختبار تلقائي',
			'logs.pageTitle' => 'السجلات',
			'logs.filterHint' => 'تصفية',
			'logs.allLevelsFilter' => 'الكل',
			'logs.shareCoreLogs' => 'مشاركة سجلات النواة',
			'logs.shareAppLogs' => 'مشاركة سجلات التطبيق',
			'logs.pauseTooltip' => 'إيقاف مؤقت',
			'logs.resumeTooltip' => 'استئناف',
			'logs.clearTooltip' => 'مسح',
			'logs.logsCleared' => 'تم مسح السجلات',
			'logs.logsCopied' => 'تم نسخ السجلات',
			'logs.logsUnderDevelopment' => 'ميزة السجلات قيد التطوير',
			'logs.noLogsWhenDisconnected' => 'غير متصل، لا توجد سجلات',
			'logs.loadFailed' => 'تعذّر تحميل السجلات',
			'logs.empty' => 'لا توجد سجلات بعد',
			'logs.clearFailed' => 'تعذّر مسح السجلات',
			'settings.pageTitle' => 'الإعدادات',
			'settings.requiresRestartMsg' => 'لتطبيق هذه التغييرات، أعد تشغيل التطبيق',
			'settings.experimental' => 'تجريبي',
			'settings.experimentalMsg' => 'الميزات ذات العلامة التجريبية لا تزال قيد التطوير وقد تسبب مشاكل.',
			'settings.exportOptions' => 'تصدير الخيارات إلى الحافظة',
			'settings.exportAllOptions' => 'تصدير جميع الخيارات إلى الحافظة (تصحيح الأخطاء)',
			'settings.importOptions' => 'استيراد الخيارات من الحافظة',
			'settings.importOptionsMsg' => 'سيؤدي هذا إلى إعادة كتابة جميع خيارات التكوين بالقيم المحددة. هل أنت متأكد؟',
			'settings.backup.importConfirmTitle' => 'استيراد نسخة احتياطية',
			'settings.backup.importConfirmMsg' => 'سيؤدي هذا إلى استبدال اشتراكاتك بالاشتراكات الموجودة في النسخة الاحتياطية وتطبيق إعداداتها. يتم أولًا حفظ لقطة من البيانات الحالية وتُستعاد تلقائيًا إذا فشل الاستيراد.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => 'يوجد ${count} اشتراك على هذا الجهاز غير موجود في النسخة الاحتياطية وسيتم حذفه.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => 'تم استيراد ${profiles} اشتراك و${settings} إعداد.',
			'settings.backup.reportDropped' => ({required Object count}) => 'تم تخطي ${count} اشتراك في النسخة الاحتياطية لأن بياناته غير صالحة.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => 'تم تخطي ${count} إعداد، وتم الاحتفاظ بقيمك الحالية.',
			'settings.backup.reportWarpOff' => 'أدى الاستيراد إلى إيقاف WARP. أعد تفعيله على هذا الجهاز.',
			'settings.backup.reportBackfill' => ({required Object count}) => 'سيتم تنزيل ${count} اشتراك في الخلفية.',
			'settings.backup.errInvalidFile' => 'هذا ليس ملف نسخة احتياطية صالحًا لـ ClashMiao.',
			'settings.backup.errUnsupportedVersion' => 'صيغة هذه النسخة الاحتياطية غير مدعومة.',
			'settings.backup.errNewerSchema' => 'تم إنشاء هذه النسخة الاحتياطية بإصدار أحدث من التطبيق. يرجى تحديث التطبيق أولًا.',
			'settings.backup.errNoUsableProfiles' => 'لا يمكن استيراد أي من الاشتراكات في هذه النسخة الاحتياطية.',
			'settings.backup.errSnapshotFailed' => 'تعذر حفظ لقطة من البيانات الحالية، لذلك لم يتم تغيير أي شيء.',
			'settings.backup.errUnresolvedPrevious' => 'توقف استيراد سابق ولم يتم التراجع عنه بعد. لم يتم تغيير أي شيء. أعد تشغيل التطبيق وحاول مرة أخرى.',
			'settings.backup.errRolledBack' => 'فشل الاستيراد. تمت استعادة بياناتك السابقة.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'فشل الاستيراد ولم تكتمل الاستعادة التلقائية. أعد تشغيل التطبيق لإعادة المحاولة. تم حفظ لقطة في ${path}.',
			'settings.backup.errFailed' => 'فشل الاستيراد.',
			'settings.backup.errBusy' => 'هناك استيراد آخر قيد التنفيذ. يرجى الانتظار حتى ينتهي.',
			'settings.backup.recoveryFailedTitle' => 'لم تكتمل الاستعادة التلقائية',
			'settings.backup.recoveryFailedMsg' => 'توقف آخر استيراد للنسخة الاحتياطية ولم يتمكن التطبيق من إعادة بياناتك إلى حالتها السابقة. قد تكون بعض البيانات قد استُوردت جزئيًا. أعد محاولة الاستعادة التلقائية الآن.',
			'settings.backup.recoveryUnrecoverableTitle' => 'تعذر التراجع عن الاستيراد المتوقف',
			'settings.backup.recoveryUnrecoverableMsg' => 'توقف آخر استيراد للنسخة الاحتياطية، لكن لقطته مفقودة أو غير قابلة للقراءة، لذلك لا يمكن التراجع عنه. يرجى مراجعة اشتراكاتك وإعداداتك.',
			'settings.backup.recoveryRetry' => 'إعادة المحاولة',
			'settings.backup.recoveryClose' => 'إغلاق',
			'settings.backup.recoveryRetried' => 'تمت استعادة بياناتك إلى ما قبل الاستيراد المتوقف.',
			'settings.backup.exportAction' => 'تصدير نسخة احتياطية',
			'settings.backup.importAction' => 'استيراد نسخة احتياطية',
			'settings.backup.exportFailed' => 'تعذّر تصدير النسخة الاحتياطية',
			'settings.backup.shareText' => 'نسخة ClashMiao الاحتياطية',
			'settings.general.sectionTitle' => 'عام',
			'settings.general.locale' => 'اللغة',
			'settings.general.region' => 'المنطقة',
			'settings.general.regionMsg' => 'يساعد على تعيين الخيارات الافتراضية لتجاوز العناوين المحلية',
			'settings.general.regions.ir' => 'إيران (ir)',
			'settings.general.regions.cn' => 'الصين (cn)',
			'settings.general.regions.ru' => 'روسيا (ru)',
			'settings.general.regions.af' => 'أفغانستان (af)',
			'settings.general.regions.id' => 'إندونيسيا (id)',
			'settings.general.regions.other' => 'أخرى',
			'settings.general.themeMode' => 'وضع السمة',
			'settings.general.themeModes.system' => 'اتباع سمة النظام',
			'settings.general.themeModes.dark' => 'الوضع الداكن',
			'settings.general.themeModes.light' => 'الوضع الفاتح',
			'settings.general.themeModes.black' => 'الوضع الأسود',
			'settings.general.enableAnalytics' => 'تمكين التحليلات',
			'settings.general.enableAnalyticsMsg' => 'منح الإذن بجمع التحليلات وإرسال تقارير الأعطال لتحسين التطبيق',
			'settings.general.autoStart' => 'بدء التشغيل عند تسجيل الدخول',
			'settings.general.silentStart' => 'بدء التشغيل مُصغر',
			'settings.general.openWorkingDir' => 'فتح دليل العمل',
			'settings.general.ignoreBatteryOptimizations' => 'تعطيل تحسينات البطارية',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'إزالة القيود للحصول على أفضل أداء VPN',
			'settings.general.dynamicNotification' => 'عرض السرعة في الإشعار',
			'settings.general.hapticFeedback' => 'ردود فعل اللمس',
			'settings.general.autoIpCheck' => 'التحقق من عنوان IP للاتصال تلقائيًا',
			'settings.general.batteryOptimizationStatus.exempted' => 'مُستثنى',
			'settings.general.batteryOptimizationStatus.notExempted' => 'غير مُستثنى',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'متقدم',
			'settings.advanced.debugMode' => 'وضع تصحيح الأخطاء',
			'settings.advanced.debugModeMsg' => 'أعد تشغيل التطبيق لتطبيق هذا التغيير',
			'settings.advanced.memoryLimit' => 'حد الذاكرة',
			'settings.advanced.memoryLimitMsg' => 'قم بتمكين هذه الميزة إذا كنت تواجه أخطاء «عدم كفاية الذاكرة» أو تعطل التطبيق بشكل متكرر',
			'settings.advanced.resetTunnel' => 'إعادة تعيين ملف تعريف VPN',
			'settings.advanced.resetTunnelSuccess' => 'تمت إعادة تعيين ملف VPN',
			'settings.network.perAppProxyPageTitle' => 'الوكيل لكل تطبيق',
			'settings.network.perAppProxyModes.off' => 'الكل',
			'settings.network.perAppProxyModes.offMsg' => 'وكيل جميع التطبيقات',
			'settings.network.perAppProxyModes.include' => 'وكيل',
			'settings.network.perAppProxyModes.includeMsg' => 'وكيل التطبيقات المحددة فقط',
			'settings.network.perAppProxyModes.exclude' => 'تجاوز',
			'settings.network.perAppProxyModes.excludeMsg' => 'لا تستخدم الوكيل للتطبيقات المحددة',
			'settings.network.showSystemApps' => 'عرض تطبيقات النظام',
			'settings.network.hideSystemApps' => 'إخفاء تطبيقات النظام',
			'settings.network.clearSelection' => 'مسح الاختيار',
			'settings.network.perAppProxyLoadFailedMsg' => 'فشل تحميل قائمة التطبيقات',
			'settings.network.perAppProxyRetry' => 'إعادة المحاولة',
			'settings.network.perAppProxyEmptyMsg' => 'لا توجد نتائج',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'وضع الخط لكل تطبيق مدعوم على Android فقط',
			'settings.geoAssets.pageTitle' => 'أصول التوجيه',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'GeoSite',
			'settings.geoAssets.version' => ({required Object version}) => 'الإصدار ${version}',
			'settings.geoAssets.fileMissing' => 'الملف مفقود',
			'settings.geoAssets.update' => 'تحديث',
			'settings.geoAssets.download' => 'تنزيل',
			'settings.geoAssets.failureMsg' => 'فشل في تحديث الأصل',
			'settings.geoAssets.successMsg' => 'تم تحديث الأصل بنجاح',
			'settings.geoAssets.addRecommended' => 'إضافة الأصول الموصى بها',
			'settings.geoAssets.missingGeoAssetsMsg' => 'ملفات أصول التوجيه المحددة مفقودة. قم بتنزيلها أو اختر ملفات موجودة',
			'settings.systemProxyEnabled' => 'تم تفعيل بروكسي النظام',
			'settings.systemProxyDisabled' => 'تم تعطيل بروكسي النظام (أعد الاتصال للتطبيق)',
			'settings.adminPrivilegesRequired' => 'يتطلب صلاحيات المسؤول على macOS',
			'settings.portChangeNotice' => 'تغييرات المنفذ تتطلب إعادة الاتصال لتفعيلها',
			'settings.groups.general' => 'عام',
			'settings.groups.connection' => 'الاتصال',
			'settings.groups.privacy' => 'الخصوصية',
			'settings.importOptionsInvalid' => 'لا تحتوي الحافظة على JSON إعدادات صالح',
			'settings.importOptionsNothing' => 'لم يتم العثور على إعدادات قابلة للاستيراد',
			'settings.importOptionsDone' => ({required Object count}) => 'تم استيراد ${count} من الإعدادات',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => 'تم استيراد ${applied} من الإعدادات، وتم تخطي ${skipped} لأنها غير صالحة',
			'about.pageTitle' => 'حول\nتعريب:م. ابراهيم قاسم',
			'about.version' => 'الإصدار',
			'about.sourceCode' => 'رمز المصدر',
			'about.telegramChannel' => 'قناة Telegram',
			'about.checkForUpdate' => 'التحقق من وجود تحديث',
			'about.privacyPolicy' => 'سياسة الخصوصية',
			'about.termsAndConditions' => 'الشروط والأحكام',
			'about.appDescription' => 'عميل بروكسي متعدد المنصات يعتمد على نواة sing-box',
			'about.openSourceLicenses' => 'تراخيص المصدر المفتوح',
			'appUpdate.notAvailableMsg' => 'أنت تستخدم أحدث إصدار بالفعل',
			'appUpdate.dialogTitle' => 'تحديث متاح',
			'appUpdate.updateMsg' => 'إصدار جديد من ${_root.general.appTitle} متاح. هل تريد التحديث الآن؟',
			'appUpdate.currentVersionLbl' => 'الإصدار الحالي',
			'appUpdate.newVersionLbl' => 'الإصدار الجديد',
			'appUpdate.updateNowBtnTxt' => 'تحديث الآن',
			'appUpdate.laterBtnTxt' => 'لاحقًا',
			'appUpdate.ignoreBtnTxt' => 'تجاهل',
			'appUpdate.checkFailedMsg' => 'تعذّر التحقق من التحديثات. تحقق من اتصالك بالشبكة وحاول مرة أخرى.',
			'tray.dashboard' => 'لوحة التحكم',
			'tray.quit' => 'إنهاء',
			'tray.open' => 'فتح',
			'tray.status.connect' => 'الاتصال',
			'tray.status.connecting' => 'جار الاتصال',
			'tray.status.disconnect' => 'فصم الاتصال',
			'tray.status.disconnecting' => 'جار فصم الاتصال',
			'tray.hide' => 'إخفاء',
			'tray.proxyModeMenu' => 'وضع الوكيل',
			'failure.unexpected' => 'خطأ غير متوقع',
			'failure.clash.unexpected' => 'خطأ غير متوقع',
			'failure.clash.core' => ({required Object reason}) => 'خطأ في Clash ${reason}',
			'failure.singbox.unexpected' => 'خطأ في الخدمة غير متوقع',
			'failure.singbox.serviceNotRunning' => 'الخدمة غير قيد التشغيل',
			'failure.singbox.missingPrivilege' => 'غياب الامتياز',
			'failure.singbox.missingPrivilegeMsg' => 'وضع VPN يتطلب امتيازات المسؤول. أعد تشغيل التطبيق كمسؤول أو غيّر وضع الخدمة.',
			'failure.singbox.missingGeoAssets' => 'أصول Geo مفقودة',
			'failure.singbox.missingGeoAssetsMsg' => 'أصول Geo مفقودة. فكر في تغيير الأصل النشط أو تنزيل الأصل المحدد في الإعدادات.',
			'failure.singbox.invalidConfigOptions' => 'خيارات التكوين غير صحيحة',
			'failure.singbox.invalidConfig' => 'تكوين غير صالح',
			'failure.singbox.create' => 'خطأ في إنشاء الخدمة',
			'failure.singbox.start' => 'خطأ في بدء تشغيل الخدمة',
			'failure.singbox.coreLibraryMissing' => 'مكتبة النواة غير مثبتة',
			'failure.singbox.startTimeout' => 'انتهت مهلة بدء الخدمة',
			'failure.singbox.kernelUnresponsive' => 'النواة لا تستجيب. حاول مرة أخرى أو أعد تشغيل التطبيق.',
			'failure.singbox.kernelExited' => 'توقفت النواة بشكل غير متوقع',
			'failure.connectivity.unexpected' => 'فشل غير متوقع',
			'failure.connectivity.missingVpnPermission' => 'غياب إذن VPN',
			'failure.connectivity.missingNotificationPermission' => 'غياب إذن الإشعارات',
			'failure.connectivity.core' => 'خطأ في النواة',
			'failure.connectivity.networkUnavailable' => 'الشبكة غير متاحة',
			'failure.connectivity.nativeUnresponsive' => 'فُقد الاتصال بالخدمة الخلفية. حاول مرة أخرى.',
			'failure.profiles.unexpected' => 'خطأ غير متوقع',
			'failure.profiles.notFound' => 'لم يتم العثور على ملف التعريف',
			'failure.profiles.invalidConfig' => 'تكوينات غير صحيحة',
			'failure.profiles.invalidUrl' => 'عنوان URL غير صالح',
			'failure.profiles.noActive' => 'لا يوجد اشتراك مفعّل',
			'failure.profiles.readOnlyUpgrade' => 'يرجى ترقية التطبيق قبل تعديل الاشتراكات',
			'failure.connection.unexpected' => 'خطأ في الاتصال غير متوقع',
			'failure.connection.timeout' => 'انتهاء الوقت في الاتصال',
			'failure.connection.badResponse' => 'استجابة سيئة',
			'failure.connection.connectionError' => 'خطأ في الاتصال',
			'failure.connection.badCertificate' => 'شهادة غير صالحة',
			'failure.geoAssets.unexpected' => 'خطأ غير متوقع',
			'failure.geoAssets.notUpdate' => 'لا يوجد تحديث متاح',
			'failure.geoAssets.activeNotFound' => 'لم يتم العثور على أصل Geo النشط',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'انقر للاتصال',
			'connection.connecting' => 'جار الاتصال',
			'connection.disconnecting' => 'جار فصم الاتصال',
			'connection.connected' => 'متصل',
			'connection.reconnect' => 'أعد الاتصال',
			'connection.connectAnyWay' => 'اتصل على أي حال',
			'connection.experimentalNotice' => 'ميزات تجريبية قيد الاستخدام',
			'connection.experimentalNoticeMsg' => 'لقد قمت بتمكين بعض الميزات التجريبية التي قد تؤثر على جودة الاتصال وتسبب أخطاء غير متوقعة. يمكنك دائمًا تغيير هذه الخيارات أو إعادة تعيينها من صفحة خيارات التكوين.',
			'connection.disableExperimentalNotice' => 'لا تعرض مرة أخرى',
			'connection.reconnectMsg' => 'أعد الاتصال ليتم تطبيق التغييرات',
			'connection.staleSystemProxyCleaned' => 'تم تنظيف إعدادات وكيل النظام المتبقية من إنهاء غير طبيعي سابق',
			'config.resetBtn' => 'إعادة تعيين الخيارات',
			'config.serviceMode' => 'وضع الخدمة',
			'config.quickSettings' => 'الإعدادات السريعة',
			'config.setupWarp' => 'إعداد WARP',
			'config.allOptions' => 'جميع خيارات التكوين',
			'config.serviceModes.proxy' => 'خدمة الوكيل فقط',
			'config.serviceModes.systemProxy' => 'تعيين وكيل النظام',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'خدمة VPN',
			'config.shortServiceModes.proxy' => 'وكيل',
			'config.shortServiceModes.systemProxy' => 'وكيل النظام',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'خدمة VPN',
			'config.section.route' => 'خيارات التوجيه',
			'config.section.dns' => 'خيارات DNS',
			'config.section.inbound' => 'خيارات الوارد',
			'config.section.mux' => 'MultiPlexer',
			'config.section.outbound' => 'خيارات الخارج',
			'config.section.tlsTricks' => 'حيل TLS',
			'config.section.warp' => 'خيارات WARP',
			'config.section.misc' => 'خيارات متنوعة',
			'config.warpConsent.title' => 'موافقة Cloudflare WARP',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP هو مزود VPN مجاني لـ WireGuard. بتمكين هذا الخيار، فإنك توافق على '), tos('Terms of Service'), const TextSpan(text: ' و '), privacy('Privacy Policy'), const TextSpan(text: ' لـ Cloudflare WARP.'), ]), 
			'config.generateWarpConfig' => 'إنشاء تكوين WARP',
			'config.missingWarpConfig' => 'تكوين WARP مفقود',
			'config.warpConfigGenerated' => 'تم إنشاء تكوين WARP',
			'config.pageTitle' => 'خيارات التكوين',
			'config.logLevel' => 'مستوى السجل',
			'config.resolveDestination' => 'حل الوجهة',
			'config.ipv6Mode' => 'توجيه IPv6',
			'config.ipv6Modes.disable' => 'تعطيل',
			'config.ipv6Modes.enable' => 'تمكين',
			'config.ipv6Modes.prefer' => 'مُفضل',
			'config.ipv6Modes.only' => 'حصري',
			'config.remoteDnsAddress' => 'DNS البعيد',
			'config.remoteDnsDomainStrategy' => 'استراتيجية مجال DNS البعيد',
			'config.directDnsAddress' => 'DNS المباشر',
			'config.directDnsDomainStrategy' => 'استراتيجية مجال DNS المباشر',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'لم يتم التطبيق: توجيه IPv6 معطّل لكن "${field}" هو IPv6 فقط، لذا لا يمكن حل أي نطاق. فعّل توجيه IPv6 أولاً أو اختر استراتيجية أخرى.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'لم يتم التطبيق: توجيه IPv6 هو IPv6 فقط لكن "${field}" هو IPv4 فقط، لذا لا يمكن حل أي نطاق. عدّل أحدهما أولاً.',
			'config.dnsStrategyReset' => ({required Object field}) => 'تعارض "${field}" مع إعداد توجيه IPv6 (لا يمكن حل أي نطاق) وتمت إعادته إلى تلقائي.',
			'config.mixedPort' => 'منفذ مُختلط',
			'config.tproxyPort' => 'منفذ الوكيل الشفاف',
			'config.localDnsPort' => 'منفذ DNS المحلي',
			'config.allowConnectionFromLan' => 'مشاركة VPN على الشبكة المحلية',
			'config.tunImplementation' => 'تنفيذ TUN',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'عنوان URL لاختبار الاتصال',
			'config.urlTestInterval' => 'مُدة اختبار عنوان URL',
			'config.enableClashApi' => 'تمكين Clash API',
			'config.clashApiPort' => 'منفذ Clash API',
			'config.enableTun' => 'تمكين TUN',
			'config.setSystemProxy' => 'تعيين وكيل النظام',
			'config.enableDnsRouting' => 'تمكين توجيه DNS',
			'config.enableFakeDns' => 'تمكين DNS المزيف',
			'config.bypassLan' => 'تجاوز LAN',
			'config.strictRoute' => 'توجيه صارم',
			'config.enableTlsFragment' => 'تمكين تجزئة TLS',
			'config.tlsFragmentSize' => 'حجم تجزئة TLS',
			'config.tlsFragmentSleep' => 'وقت تعليق تجزئة TLS',
			'config.enableTlsMixedSniCase' => 'تمكين خلط حالات SNI في TLS',
			'config.enableTlsPadding' => 'تمكين حشو TLS',
			'config.tlsPaddingSize' => 'حشو TLS',
			'config.enableMux' => 'تمكين Mux',
			'config.muxProtocol' => 'بروتوكول Mux',
			'config.muxMaxStreams' => 'أقصى عدد من التدفقات المتزامنة',
			'config.enableWarp' => 'تمكين WARP',
			'config.setUpWarp' => 'إعداد WARP',
			'config.warpNotConfigured' => 'غير مهيأ',
			'config.warpDetourMode' => 'وضع التفاف',
			'config.warpDetourModes.proxyOverWarp' => 'لف الخوادم الوكيلية عبر WARP',
			'config.warpDetourModes.warpOverProxy' => 'لف WARP عبر الخوادم الوكيلية',
			'config.warpDetourModes.inbound' => 'لف WARP عبر الخوادم الوكيلية',
			'config.warpDetourModes.outbound' => 'لف الخوادم الوكيلية عبر WARP',
			'config.warpLicenseKey' => 'مفتاح الترخيص',
			'config.warpCleanIp' => 'عنوان IP نظيف',
			'config.warpPort' => 'المنفذ',
			'config.warpNoise' => 'عدد الضوضاء',
			'config.warpNoiseDelay' => 'تأخير الضوضاء',
			'config.quickSettingsSubtitle' => 'خصص تجربة الاتصال',
			'config.allAdvancedOptions' => 'جميع الخيارات المتقدمة',
			'config.blockAds' => 'حظر الإعلانات',
			'config.warpNoiseSize' => 'حجم الضجيج',
			'config.warpNoiseMode' => 'وضع الضجيج',
			'config.desktopProxyScopeNotice' => 'على سطح المكتب، يتم توجيه التطبيقات التي تحترم بروكسي النظام فقط عبر النفق. البرامج التي تتجاهله (بعض الألعاب وأدوات سطر الأوامر والتطبيقات ذات إعدادات البروكسي الخاصة) تتصل مباشرة وتكشف عنوان IP الحقيقي.',
			'config.serviceModeIosVpnOnly' => 'يدعم iOS وضع VPN فقط',
			'config.warpGenerating' => 'جارٍ إنشاء إعدادات WARP…',
			'config.warpConfigFailed' => 'تعذّر إنشاء إعدادات WARP. يُرجى المحاولة لاحقًا.',
			'config.portRangeError' => 'يجب أن يكون المنفذ بين 1024 و65535',
			'config.dnsEmptyError' => 'لا يمكن أن يكون عنوان DNS فارغًا',
			'config.rangeFormatError' => 'أدخل رقمًا أو نطاقًا، مثل 10-30',
			'config.urlSchemeError' => 'يجب أن يبدأ الرابط بـ http:// أو https://',
			'config.manageRuleAssets' => 'إدارة مجموعات القواعد',
			_ => null,
		};
	}
}
