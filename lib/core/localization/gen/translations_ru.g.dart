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
class TranslationsRu extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsRu({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ru,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <ru>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsRu _root = this; // ignore: unused_field

	@override 
	TranslationsRu $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsRu(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$ru general = Translations$general$ru._(_root);
	@override late final Translations$intro$ru intro = Translations$intro$ru._(_root);
	@override late final Translations$home$ru home = Translations$home$ru._(_root);
	@override late final Translations$stats$ru stats = Translations$stats$ru._(_root);
	@override late final Translations$profile$ru profile = Translations$profile$ru._(_root);
	@override late final Translations$proxies$ru proxies = Translations$proxies$ru._(_root);
	@override late final Translations$logs$ru logs = Translations$logs$ru._(_root);
	@override late final Translations$settings$ru settings = Translations$settings$ru._(_root);
	@override late final Translations$about$ru about = Translations$about$ru._(_root);
	@override late final Translations$appUpdate$ru appUpdate = Translations$appUpdate$ru._(_root);
	@override late final Translations$tray$ru tray = Translations$tray$ru._(_root);
	@override late final Translations$failure$ru failure = Translations$failure$ru._(_root);
	@override late final Translations$connection$ru connection = Translations$connection$ru._(_root);
	@override late final Translations$config$ru config = Translations$config$ru._(_root);
}

// Path: general
class Translations$general$ru extends Translations$general$en {
	Translations$general$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'Сброс';
	@override late final Translations$general$toggle$ru toggle = Translations$general$toggle$ru._(_root);
	@override late final Translations$general$state$ru state = Translations$general$state$ru._(_root);
	@override String get sort => 'Сортировка';
	@override String get sortBy => 'Сортировка';
	@override String get addToClipboard => 'Копировать в буфер обмена';
	@override String get notSet => 'Не задано';
	@override String get agree => 'Соглашаться';
	@override String get decline => 'Отклонить';
	@override String get unknown => 'Неизвестный';
	@override String get hidden => 'Скрытый';
	@override String get timeout => 'Таймаут';
	@override String get clipboardExportSuccessMsg => 'Скопировано';
	@override String get showMore => 'Развернуть ';
	@override String get showLess => 'Свернуть ';
	@override String get openAppSettings => 'Открыть настройки';
	@override String get grantPermission => 'Дать права доступа';
	@override String get underDevelopment => 'В разработке';
	@override String get confirm => 'Подтвердить';
	@override String get close => 'Закрыть';
	@override String get cancel => 'Отмена';
	@override String get clipboardEmpty => 'Буфер обмена пуст';
	@override String get clipboardReadFailed => 'Не удалось прочитать буфер обмена';
	@override String get moreOptions => 'Дополнительно';
}

// Path: intro
class Translations$intro$ru extends Translations$intro$en {
	Translations$intro$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'Продолжая, Вы соглашаетесь с '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => 'Начать';
}

// Path: home
class Translations$home$ru extends Translations$home$en {
	Translations$home$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Главная';
	@override String get emptyProfilesMsg => 'Начните с добавления профиля подписки';
	@override String get noActiveProfileMsg => 'Выберите профиль';
	@override late final Translations$home$routingMode$ru routingMode = Translations$home$routingMode$ru._(_root);
	@override String failedToSwitchMode({required Object error}) => 'Не удалось сменить режим: ${error}';
	@override String get connectionFailedTitle => 'Не удалось подключиться';
	@override String get coreMissingTitle => 'Библиотека ядра не найдена';
	@override String get coreMissingMsg => 'Приложению не удалось загрузить сетевое ядро. Подключение недоступно. Переустановите приложение или убедитесь, что файл библиотеки ядра находится рядом с исполняемым файлом.';
	@override String get degradedTitle => 'Подключено, но нет доступа в интернет';
	@override String get degradedMsg => 'Туннель поднят, но трафик не проходит. Возможно, узел недоступен — попробуйте другой узел или отключитесь.';
	@override String get degradedRetry => 'Проверить ещё раз';
	@override late final Translations$home$egressIp$ru egressIp = Translations$home$egressIp$ru._(_root);
	@override String get emptyProfilesHint => 'Нажмите кнопку ниже, чтобы начать';
	@override String get noActiveProfileTitle => 'Профиль не выбран';
}

// Path: stats
class Translations$stats$ru extends Translations$stats$en {
	Translations$stats$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Трафик';
	@override String get trafficLive => 'Текущий трафик';
	@override String get trafficTotal => 'Трафик';
	@override String get uplink => 'Скорость отправки';
	@override String get downlink => 'Скорость загрузки';
	@override String get connection => 'Соединение ';
	@override String get speed => 'Скорость';
	@override String get totalTransferred => 'Всего передано';
	@override String get trafficUsage => 'Использование трафика';
	@override String get liveSpeed => 'Текущая скорость';
	@override String get sessionTraffic => 'Трафик за сеанс';
	@override String get downloadSpeed => 'Скорость загрузки';
}

// Path: profile
class Translations$profile$ru extends Translations$profile$en {
	Translations$profile$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'Профили';
	@override String get detailsPageTitle => 'Профиль';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'Имя активного профиля: «${name}».';
	@override String get activeProfileBtnSemanticLabel => 'Посмотреть все профили';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Выберите «${name}» в качестве активного профиля.';
	@override late final Translations$profile$subscription$ru subscription = Translations$profile$subscription$ru._(_root);
	@override late final Translations$profile$sortBy$ru sortBy = Translations$profile$sortBy$ru._(_root);
	@override late final Translations$profile$add$ru add = Translations$profile$add$ru._(_root);
	@override late final Translations$profile$update$ru update = Translations$profile$update$ru._(_root);
	@override late final Translations$profile$share$ru share = Translations$profile$share$ru._(_root);
	@override late final Translations$profile$edit$ru edit = Translations$profile$edit$ru._(_root);
	@override late final Translations$profile$delete$ru delete = Translations$profile$delete$ru._(_root);
	@override late final Translations$profile$save$ru save = Translations$profile$save$ru._(_root);
	@override late final Translations$profile$detailsForm$ru detailsForm = Translations$profile$detailsForm$ru._(_root);
	@override late final Translations$profile$actionButtons$ru actionButtons = Translations$profile$actionButtons$ru._(_root);
	@override late final Translations$profile$details$ru details = Translations$profile$details$ru._(_root);
	@override late final Translations$profile$overview$ru overview = Translations$profile$overview$ru._(_root);
	@override String get remoteProfile => 'Удалённый профиль';
	@override String get defaultLocalName => 'Локальный импорт';
	@override String get defaultDeepLinkName => 'Импорт по ссылке';
	@override String get switchFailedMsg => 'Не удалось переключить профиль';
}

// Path: proxies
class Translations$proxies$ru extends Translations$proxies$en {
	Translations$proxies$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Прокси';
	@override String get emptyProxiesMsg => 'Нет доступных прокси';
	@override String get delayTestTooltip => 'Тестирование задержки';
	@override String get sortTooltip => 'Сортировка прокси';
	@override String get checkIp => 'Проверить IP';
	@override String get unknownIp => 'Неизвестный IP';
	@override late final Translations$proxies$sortOptions$ru sortOptions = Translations$proxies$sortOptions$ru._(_root);
	@override String get activeProxySemanticLabel => 'Активный прокси';
	@override late final Translations$proxies$delaySemantics$ru delaySemantics = Translations$proxies$delaySemantics$ru._(_root);
	@override late final Translations$proxies$ipInfoSemantics$ru ipInfoSemantics = Translations$proxies$ipInfoSemantics$ru._(_root);
	@override String get autoSelect => 'Автовыбор';
	@override String get autoSelectDescription => 'Автоматически подключаться к самому быстрому узлу';
	@override String get sortModalTitle => 'Выберите способ сортировки';
	@override String testingDelayInfo({required Object name}) => 'Проверка задержки: ${name}';
	@override String switchedTo({required Object name}) => 'Переключено на ${name}';
	@override String get switchFailed => 'Не удалось переключить сервер. Попробуйте ещё раз.';
	@override String get testFailed => 'Не удалось проверить задержку. Попробуйте ещё раз.';
	@override String get groupsLoading => 'Список серверов ещё загружается. Повторите попытку через минуту.';
	@override String get connectBeforeSwitch => 'Подключитесь перед сменой линии';
	@override String startDelayTestForGroups({required Object count}) => 'Запущена проверка задержки для ${count} линий';
	@override String get delayTestBtn => 'Задержка';
	@override String get delayTimeout => 'Тайм-аут';
	@override String get connectBeforeTest => 'Сначала подключитесь, чтобы проверить задержку';
	@override String lineCount({required Object count}) => 'Линий: ${count}';
	@override String get manualSelect => 'Ручной выбор';
	@override String get autoTest => 'Автотест';
}

// Path: logs
class Translations$logs$ru extends Translations$logs$en {
	Translations$logs$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Журналы';
	@override String get filterHint => 'Фильтр';
	@override String get allLevelsFilter => 'Все';
	@override String get shareCoreLogs => 'Поделиться журналами ядра';
	@override String get shareAppLogs => 'Поделиться журналами приложения';
	@override String get pauseTooltip => 'Приостановить';
	@override String get resumeTooltip => 'Возобновить';
	@override String get clearTooltip => 'Очистить';
	@override String get logsCleared => 'Журналы очищены';
	@override String get logsCopied => 'Журналы скопированы';
	@override String get logsUnderDevelopment => 'Функция журналов в разработке';
	@override String get noLogsWhenDisconnected => 'Нет подключения, журналы отсутствуют';
	@override String get loadFailed => 'Не удалось загрузить журнал';
	@override String get empty => 'Журнал пока пуст';
	@override String get clearFailed => 'Не удалось очистить журнал';
}

// Path: settings
class Translations$settings$ru extends Translations$settings$en {
	Translations$settings$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Настройки';
	@override String get requiresRestartMsg => 'Чтобы применить изменения, перезапустите приложение.';
	@override String get experimental => 'Экспериментальный';
	@override String get experimentalMsg => 'Функции с флагом «Экспериментально» все еще находятся в разработке и могут вызвать проблемы.';
	@override String get importOptions => 'Импорт параметров из буфера обмена';
	@override String get importOptionsMsg => 'Это перезапишет все параметры конфига предоставленными значениями. Вы уверены?';
	@override late final Translations$settings$backup$ru backup = Translations$settings$backup$ru._(_root);
	@override late final Translations$settings$general$ru general = Translations$settings$general$ru._(_root);
	@override late final Translations$settings$advanced$ru advanced = Translations$settings$advanced$ru._(_root);
	@override late final Translations$settings$network$ru network = Translations$settings$network$ru._(_root);
	@override late final Translations$settings$geoAssets$ru geoAssets = Translations$settings$geoAssets$ru._(_root);
	@override String get exportOptions => 'Копировать анонимные параметры в буфер обмена';
	@override String get exportAllOptions => 'Копировать все параметры в буфер обмена';
	@override String get systemProxyEnabled => 'Системный прокси включён';
	@override String get systemProxyDisabled => 'Системный прокси отключён (переподключитесь для применения)';
	@override String get adminPrivilegesRequired => 'На macOS требуются права администратора';
	@override String get portChangeNotice => 'Изменения порта применяются после переподключения';
	@override late final Translations$settings$groups$ru groups = Translations$settings$groups$ru._(_root);
	@override String get importOptionsInvalid => 'В буфере обмена нет корректного JSON настроек';
	@override String get importOptionsNothing => 'Не найдено настроек для импорта';
	@override String importOptionsDone({required Object count}) => 'Импортировано настроек: ${count}';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => 'Импортировано: ${applied}; пропущено как некорректные: ${skipped}';
}

// Path: about
class Translations$about$ru extends Translations$about$en {
	Translations$about$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'О программе';
	@override String get version => 'Версия';
	@override String get sourceCode => 'Исходный код';
	@override String get telegramChannel => 'Telegram-канал';
	@override String get checkForUpdate => 'Проверка обновления';
	@override String get privacyPolicy => 'Политика конфиденциальности';
	@override String get termsAndConditions => 'Условия и положения';
	@override String get appDescription => 'Кроссплатформенный прокси-клиент на основе ядра sing-box';
	@override String get openSourceLicenses => 'Лицензии открытого ПО';
}

// Path: appUpdate
class Translations$appUpdate$ru extends Translations$appUpdate$en {
	Translations$appUpdate$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'Установлена последняя версия';
	@override String get dialogTitle => 'Доступно обновление';
	@override String get updateMsg => 'Доступна новая версия ${_root.general.appTitle}. Обновить сейчас?';
	@override String get currentVersionLbl => 'Текущая версия';
	@override String get newVersionLbl => 'Новая версия';
	@override String get updateNowBtnTxt => 'Обновить';
	@override String get laterBtnTxt => 'Позже';
	@override String get ignoreBtnTxt => 'Пропустить';
	@override String get checkFailedMsg => 'Не удалось проверить обновления. Проверьте сеть и повторите попытку.';
}

// Path: tray
class Translations$tray$ru extends Translations$tray$en {
	Translations$tray$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'Панель';
	@override String get quit => 'Выход';
	@override String get open => 'Открыть';
	@override late final Translations$tray$status$ru status = Translations$tray$status$ru._(_root);
	@override String get hide => 'Скрыть';
	@override String get proxyModeMenu => 'Режим прокси';
}

// Path: failure
class Translations$failure$ru extends Translations$failure$en {
	Translations$failure$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Непредвиденная ошибка';
	@override late final Translations$failure$clash$ru clash = Translations$failure$clash$ru._(_root);
	@override late final Translations$failure$singbox$ru singbox = Translations$failure$singbox$ru._(_root);
	@override late final Translations$failure$connectivity$ru connectivity = Translations$failure$connectivity$ru._(_root);
	@override late final Translations$failure$profiles$ru profiles = Translations$failure$profiles$ru._(_root);
	@override late final Translations$failure$connection$ru connection = Translations$failure$connection$ru._(_root);
	@override late final Translations$failure$geoAssets$ru geoAssets = Translations$failure$geoAssets$ru._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$ru extends Translations$connection$en {
	Translations$connection$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'Нажмите для подключения';
	@override String get connecting => 'Подключение';
	@override String get disconnecting => 'Отключение';
	@override String get connected => 'Подключено';
	@override String get reconnect => 'Восстановить соединение';
	@override String get connectAnyWay => 'Всё равно подключиться';
	@override String get experimentalNotice => 'Экспериментальные функции в использовании';
	@override String get experimentalNoticeMsg => 'Вы включили некоторые экспериментальные функции, которые могут повлиять на качество соединения и вызвать непредвиденные ошибки. Вы всегда можете изменить или сбросить эти параметры на странице параметров конфигурации.';
	@override String get disableExperimentalNotice => 'Больше не показывать';
	@override String get reconnectMsg => 'Переподключить для применения изменений';
	@override String get staleSystemProxyCleaned => 'Удалены настройки системного прокси, оставшиеся после аварийного завершения';
}

// Path: config
class Translations$config$ru extends Translations$config$en {
	Translations$config$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'Сбросить параметры';
	@override String get serviceMode => 'Режим работы';
	@override String get quickSettings => 'Быстрые настройки';
	@override String get setupWarp => 'Настроить WARP';
	@override String get allOptions => 'Все параметры ';
	@override late final Translations$config$serviceModes$ru serviceModes = Translations$config$serviceModes$ru._(_root);
	@override late final Translations$config$shortServiceModes$ru shortServiceModes = Translations$config$shortServiceModes$ru._(_root);
	@override late final Translations$config$section$ru section = Translations$config$section$ru._(_root);
	@override late final Translations$config$warpConsent$ru warpConsent = Translations$config$warpConsent$ru._(_root);
	@override String get generateWarpConfig => 'Cгенерировать WARP конфиг';
	@override String get missingWarpConfig => 'Отсутствует WARP конфиг';
	@override String get warpConfigGenerated => 'WARP конфиг сгенерирован';
	@override String get pageTitle => 'Параметры конфигурации';
	@override String get logLevel => 'Подробность журналирования';
	@override String get resolveDestination => 'Определять назначение';
	@override String get ipv6Mode => 'Маршрутизация IPv6';
	@override late final Translations$config$ipv6Modes$ru ipv6Modes = Translations$config$ipv6Modes$ru._(_root);
	@override String get remoteDnsAddress => 'Удалённый DNS';
	@override String get remoteDnsDomainStrategy => 'Стратегия удалённого домена DNS';
	@override String get directDnsAddress => 'Прямой DNS';
	@override String get directDnsDomainStrategy => 'Стратегия прямого домена DNS';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'Не применено: маршрутизация IPv6 отключена, а «${field}» — только IPv6, поэтому ни один домен не разрешится. Сначала включите маршрутизацию IPv6 или выберите другую стратегию.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'Не применено: маршрутизация IPv6 — только IPv6, а «${field}» — только IPv4, поэтому ни один домен не разрешится. Сначала измените один из параметров.';
	@override String dnsStrategyReset({required Object field}) => '«${field}» конфликтовала с настройкой маршрутизации IPv6 (ни один домен не разрешился бы) и сброшена на авто.';
	@override String get mixedPort => 'Смешанный порт';
	@override String get tproxyPort => 'Прозрачный прокси порт';
	@override String get localDnsPort => 'Локальный порт DNS';
	@override String get allowConnectionFromLan => 'Allow Connection from LAN';
	@override String get tunImplementation => 'Реализация TUN';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'URL проверки подключения';
	@override String get urlTestInterval => 'Интервал проверки URL';
	@override String get enableClashApi => 'Использовать Clash API';
	@override String get clashApiPort => 'Порт Clash API';
	@override String get enableTun => 'Использовать TUN';
	@override String get setSystemProxy => 'Использовать системный прокси';
	@override String get enableDnsRouting => 'Enable DNS Routing';
	@override String get enableFakeDns => 'Использовать поддельную DNS';
	@override String get bypassLan => 'Обход локальной сети';
	@override String get strictRoute => 'Строгая маршрутизация';
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
	@override String get setUpWarp => 'Настроить WARP';
	@override String get warpNotConfigured => 'Не настроено';
	@override String get warpDetourMode => 'Detour Mode';
	@override late final Translations$config$warpDetourModes$ru warpDetourModes = Translations$config$warpDetourModes$ru._(_root);
	@override String get warpLicenseKey => 'License Key';
	@override String get warpCleanIp => 'Clean IP';
	@override String get warpPort => 'Port';
	@override String get warpNoise => 'Noise';
	@override String get quickSettingsSubtitle => 'Настройте подключение под себя';
	@override String get allAdvancedOptions => 'Все дополнительные настройки';
	@override String get blockAds => 'Блокировать рекламу';
	@override String get warpNoiseSize => 'Размер шума';
	@override String get warpNoiseMode => 'Режим шума';
	@override String get warpNoiseDelay => 'Задержка шума';
	@override String get desktopProxyScopeNotice => 'На настольных системах через туннель идут только приложения, соблюдающие системный прокси. Программы, которые его игнорируют (некоторые игры, консольные утилиты, приложения с собственными настройками прокси), подключаются напрямую и раскрывают ваш реальный IP.';
	@override String get serviceModeIosVpnOnly => 'iOS поддерживает только режим VPN';
	@override String get warpGenerating => 'Создание конфигурации WARP…';
	@override String get warpConfigFailed => 'Не удалось создать конфигурацию WARP. Повторите попытку позже.';
	@override String get portRangeError => 'Порт должен быть от 1024 до 65535';
	@override String get dnsEmptyError => 'Адрес DNS не может быть пустым';
	@override String get rangeFormatError => 'Введите число или диапазон, например 10-30';
	@override String get urlSchemeError => 'URL должен начинаться с http:// или https://';
	@override String get manageRuleAssets => 'Наборы правил';
}

// Path: general.toggle
class Translations$general$toggle$ru extends Translations$general$toggle$en {
	Translations$general$toggle$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'Включено';
	@override String get disabled => 'Отключено';
}

// Path: general.state
class Translations$general$state$ru extends Translations$general$state$en {
	Translations$general$state$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Отключить';
}

// Path: home.routingMode
class Translations$home$routingMode$ru extends Translations$home$routingMode$en {
	Translations$home$routingMode$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get global => 'Глобальный прокси';
	@override String get smart => 'Умная маршрутизация';
}

// Path: home.egressIp
class Translations$home$egressIp$ru extends Translations$home$egressIp$en {
	Translations$home$egressIp$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get label => 'Выходной IP';
	@override String get notConnected => 'Подключитесь, чтобы увидеть выходной IP';
	@override String get tapToCheck => 'Нажмите, чтобы проверить выходной IP';
	@override String get checking => 'Проверка…';
	@override String get failedRetry => 'Не удалось проверить, нажмите для повтора';
}

// Path: profile.subscription
class Translations$profile$subscription$ru extends Translations$profile$subscription$en {
	Translations$profile$subscription$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Трафик';
	@override String updatedTimeAgo({required Object timeago}) => 'Обновлено ${timeago}';
	@override String remainingDuration({required Object duration}) => 'Ещё ${duration} дн';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => 'Использовано ${consumed} трафика из ${total}';
	@override String get expired => 'Истекло';
	@override String get noTraffic => 'Нет доступного трафика';
	@override String get upload => 'Отправлено ';
	@override String get download => 'Скачано';
	@override String get total => 'Всего трафика';
	@override String get expireDate => 'Дата окончания подписки ';
}

// Path: profile.sortBy
class Translations$profile$sortBy$ru extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'по последнему обновлению';
	@override String get name => 'по названию';
}

// Path: profile.add
class Translations$profile$add$ru extends Translations$profile$add$en {
	Translations$profile$add$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Новый профиль';
	@override String get shortBtnTxt => 'Новый профиль';
	@override String get fromClipboard => 'Добавить из буфера обмена';
	@override String get scanQr => 'Сканировать QR-код';
	@override late final Translations$profile$add$qrScanner$ru qrScanner = Translations$profile$add$qrScanner$ru._(_root);
	@override String get manually => 'Ввести вручную';
	@override String get addingProfileMsg => 'Добавление профиля';
	@override String get failureMsg => 'Не удалось добавить профиль';
	@override String get modalSubtitle => 'Выберите способ добавления файла конфигурации';
	@override String get manuallyDescription => 'Введите конфигурацию сервера вручную';
	@override String get addWarp => 'Добавить WARP';
	@override String get warpDescription => 'Бесплатное ускорение через Cloudflare WARP';
	@override String get addingWarpMsg => 'Подождите, идёт регистрация WARP.';
	@override String importedNamed({required Object name}) => 'Подписка импортирована: ${name}';
	@override String get clipboardEmpty => 'Буфер обмена пуст, импортировать нечего';
	@override String get deepLinkMissingUrl => 'В ссылке нет адреса подписки';
	@override String get successMsg => 'Профиль добавлен';
	@override String get nameAutoHint => 'Определяется автоматически (необязательно)';
}

// Path: profile.update
class Translations$profile$update$ru extends Translations$profile$update$en {
	Translations$profile$update$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Обновить';
	@override String get tooltip => 'Обновить профиль';
	@override String get updateSubscriptions => 'Обновить подписки';
	@override String get failureMsg => 'Не удалось обновить профиль';
	@override String get successMsg => 'Профиль успешно обновлён';
	@override String namedFailureMsg({required Object name}) => 'Не удалось обновить "${name}".';
	@override String namedSuccessMsg({required Object name}) => '"${name}" успешно обновлено';
}

// Path: profile.share
class Translations$profile$share$ru extends Translations$profile$share$en {
	Translations$profile$share$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Поделиться';
	@override String get exportToClipboardSuccess => 'Ссылка скопирована в буфер обмена';
	@override String get exportSubLinkToClipboard => 'Скопировать ссылку на подписку в буфер обмена';
	@override String get subLinkQrCode => 'QR-код ссылки на подписку';
	@override String get exportConfigToClipboard => 'Скопировать конфигурацию в буфер обмена';
	@override String get exportConfigToClipboardSuccess => 'Конфигурация скопирована в буфер обмена';
	@override String get shareLink => 'Поделиться ссылкой';
	@override String get subscriptionLinkCopied => 'Ссылка на подписку скопирована';
	@override String get configCopied => 'Конфигурация скопирована';
	@override String get copyFailed => 'Не удалось скопировать';
}

// Path: profile.edit
class Translations$profile$edit$ru extends Translations$profile$edit$en {
	Translations$profile$edit$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Изменить';
	@override String get selectActiveTxt => 'Выберите активный профиль';
}

// Path: profile.delete
class Translations$profile$delete$ru extends Translations$profile$delete$en {
	Translations$profile$delete$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Удалить';
	@override String get confirmationMsg => 'Безвозвратно удалить профиль?';
	@override String get successMsg => 'Профиль успешно удалён';
	@override String get confirmTitle => 'Удалить профиль';
	@override String namedConfirmMsg({required Object name}) => 'Удалить «${name}»? Это действие нельзя отменить.';
}

// Path: profile.save
class Translations$profile$save$ru extends Translations$profile$save$en {
	Translations$profile$save$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Сохранить';
	@override String get successMsg => 'Профиль успешно сохранён';
	@override String get failureMsg => 'Не удалось сохранить профиль';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$ru extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'Имя';
	@override String get nameHint => 'Имя профиля';
	@override String get urlLabel => 'URL';
	@override String get urlHint => 'Полный URL конфигурации';
	@override String get emptyNameMsg => 'Поле «Имя» обязательно';
	@override String get invalidUrlMsg => 'Неправильный URL';
	@override String get lastUpdate => 'Последнее обновление';
	@override String get updateInterval => 'Автоматическое обновление';
	@override String get updateIntervalDialogTitle => 'Интервал обновления (в часах)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'Выкл.';
	@override String updateIntervalHours({required Object hours}) => '${hours} ч';
	@override String updateIntervalDays({required Object days}) => '${days} дн.';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$ru extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get add => 'Добавить';
	@override String get updateAll => 'Обновить все';
	@override String get sort => 'Сортировать';
	@override String get copyConfigSuccess => 'Конфигурация скопирована';
	@override String get editConfig => 'Изменить конфигурацию';
}

// Path: profile.details
class Translations$profile$details$ru extends Translations$profile$details$en {
	Translations$profile$details$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'Основные сведения';
	@override String get subscriptionStatus => 'Состояние подписки';
	@override String get options => 'Параметры';
	@override String get updateNow => 'Обновить сейчас';
	@override String get updateNowDescription => 'Загрузить актуальную конфигурацию с сервера';
	@override String get expireDate => 'Дата окончания';
	@override String get unlimited => 'Безлимитно';
}

// Path: profile.overview
class Translations$profile$overview$ru extends Translations$profile$overview$en {
	Translations$profile$overview$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'Используется сейчас';
	@override String remainingDays({required Object days}) => 'Осталось ${days} дн.';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$ru extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'По умолчанию';
	@override String get name => 'По алфавиту';
	@override String get delay => 'По задержке';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$ru extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'Задержка: ${delay}мс';
	@override String get timeout => 'Тайм-аут при тестировании задержки';
	@override String get testing => 'Задержка: Тестирование...';
	@override String get untested => 'Задержка: не проверялась';
	@override String stale({required Object delay}) => 'Задержка: ${delay}мс (прежний результат)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$ru extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get address => 'IP адрес';
	@override String get country => 'Страна';
}

// Path: settings.backup
class Translations$settings$backup$ru extends Translations$settings$backup$en {
	Translations$settings$backup$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'Импорт резервной копии';
	@override String get importConfirmMsg => 'Ваши подписки будут заменены подписками из резервной копии, а настройки из неё применены. Сначала сохраняется снимок текущих данных, который автоматически восстанавливается, если импорт не удастся.';
	@override String importRemovesMsg({required Object count}) => 'Подписок на этом устройстве, которых нет в резервной копии, будет удалено: ${count}.';
	@override String reportImported({required Object profiles, required Object settings}) => 'Импортировано подписок: ${profiles}, настроек: ${settings}.';
	@override String reportDropped({required Object count}) => 'Пропущено подписок из резервной копии из-за недопустимых данных: ${count}.';
	@override String reportSettingsSkipped({required Object count}) => 'Пропущено настроек: ${count}; текущие значения сохранены.';
	@override String get reportWarpOff => 'При импорте WARP был выключен. Включите его заново на этом устройстве.';
	@override String reportBackfill({required Object count}) => 'Подписок, которые будут загружены в фоне: ${count}.';
	@override String get errInvalidFile => 'Это не файл резервной копии ClashMiao.';
	@override String get errUnsupportedVersion => 'Этот формат резервной копии не поддерживается.';
	@override String get errNewerSchema => 'Эта резервная копия создана более новой версией приложения. Сначала обновите приложение.';
	@override String get errNoUsableProfiles => 'Ни одну подписку из этой резервной копии нельзя импортировать.';
	@override String get errSnapshotFailed => 'Не удалось сохранить снимок текущих данных, поэтому ничего не изменено.';
	@override String get errUnresolvedPrevious => 'Предыдущий импорт был прерван и пока не отменён. Ничего не изменено. Перезапустите приложение и повторите попытку.';
	@override String get errRolledBack => 'Не удалось импортировать. Прежние данные восстановлены.';
	@override String errNotRolledBack({required Object path}) => 'Не удалось импортировать, а автоматическое восстановление не завершилось. Перезапустите приложение, чтобы повторить его. Снимок сохранён в ${path}.';
	@override String get errFailed => 'Не удалось импортировать.';
	@override String get errBusy => 'Другой импорт уже выполняется. Дождитесь его завершения.';
	@override String get recoveryFailedTitle => 'Автоматическое восстановление не завершилось';
	@override String get recoveryFailedMsg => 'Последний импорт резервной копии был прерван, и приложению не удалось вернуть данные в прежнее состояние. Часть данных могла быть импортирована не полностью. Повторите автоматическое восстановление.';
	@override String get recoveryUnrecoverableTitle => 'Не удалось отменить прерванный импорт';
	@override String get recoveryUnrecoverableMsg => 'Последний импорт резервной копии был прерван, но его снимок отсутствует или не читается, поэтому отменить его нельзя. Проверьте свои подписки и настройки.';
	@override String get recoveryRetry => 'Повторить';
	@override String get recoveryClose => 'Закрыть';
	@override String get recoveryRetried => 'Данные возвращены в состояние до прерванного импорта.';
	@override String get exportAction => 'Экспорт резервной копии';
	@override String get importAction => 'Импорт резервной копии';
	@override String get exportFailed => 'Не удалось экспортировать резервную копию';
	@override String get shareText => 'Резервная копия ClashMiao';
}

// Path: settings.general
class Translations$settings$general$ru extends Translations$settings$general$en {
	Translations$settings$general$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Основные';
	@override String get locale => 'Язык';
	@override String get region => 'Регион';
	@override String get regionMsg => 'Помогает установить параметры по умолчанию для обхода внутренних адресов.';
	@override late final Translations$settings$general$regions$ru regions = Translations$settings$general$regions$ru._(_root);
	@override String get themeMode => 'Оформление';
	@override late final Translations$settings$general$themeModes$ru themeModes = Translations$settings$general$themeModes$ru._(_root);
	@override String get enableAnalytics => 'Сбор аналитики';
	@override String get enableAnalyticsMsg => 'Сбор данных аналитики и отправка отчётов о сбоях для улучшения приложения';
	@override String get autoStart => 'Запуск при загрузке';
	@override String get silentStart => 'Тихий запуск';
	@override String get openWorkingDir => 'Открыть рабочую папку';
	@override String get ignoreBatteryOptimizations => 'Отключить оптимизацию батареи';
	@override String get ignoreBatteryOptimizationsMsg => 'Отключение ограничений для оптимальной производительности VPN.';
	@override String get dynamicNotification => 'Отображение скорости в уведомлении';
	@override String get autoIpCheck => 'Автоматически проверять IP-адрес соединения';
	@override String get hapticFeedback => 'Тактильная отдача';
	@override String get autoStartPermission => 'Разрешить автозапуск';
	@override String get autoStartPermissionMsg => 'Если включено, подключение автоматически восстановится после перезагрузки телефона или обновления приложения';
	@override late final Translations$settings$general$autoStartPermissionStatus$ru autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$ru._(_root);
	@override late final Translations$settings$general$batteryOptimizationStatus$ru batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$ru._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$ru extends Translations$settings$advanced$en {
	Translations$settings$advanced$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Расширенные';
	@override String get debugMode => 'Режим отладки';
	@override String get debugModeMsg => 'Чтобы применить изменения, перезапустите приложение.';
	@override String get memoryLimit => 'Ограничение памяти';
	@override String get memoryLimitMsg => 'Включите, если у вас возникают ошибки нехватки памяти или частые сбои приложения.';
	@override String get resetTunnel => 'Сбросить профиль VPN';
	@override String get resetTunnelSuccess => 'Профиль VPN сброшен';
}

// Path: settings.network
class Translations$settings$network$ru extends Translations$settings$network$en {
	Translations$settings$network$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'Раздельное проксирование';
	@override late final Translations$settings$network$perAppProxyModes$ru perAppProxyModes = Translations$settings$network$perAppProxyModes$ru._(_root);
	@override String get showSystemApps => 'Показать системные приложения';
	@override String get hideSystemApps => 'Скрыть системные приложения';
	@override String get clearSelection => 'Очистить выбор';
	@override String get perAppProxyLoadFailedMsg => 'Не удалось загрузить список приложений';
	@override String get perAppProxyRetry => 'Повторить';
	@override String get perAppProxyEmptyMsg => 'Ничего не найдено';
	@override String get perAppProxyAndroidOnlyMsg => 'Режим линий для отдельных приложений поддерживается только на Android';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$ru extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Активы маршрутизации';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => 'Версия ${version}';
	@override String get fileMissing => 'Файл отсутствует';
	@override String get update => 'Обновить';
	@override String get download => 'Скачать';
	@override String get failureMsg => 'Не удалось обновить объект';
	@override String get successMsg => 'Объект успешно обновлен';
	@override String get addRecommended => 'Добавить рекомендуемые активы';
	@override String get missingGeoAssetsMsg => 'Файлы выбранных ресурсов маршрутизации отсутствуют. Либо скачайте их, либо выберите существующие.';
}

// Path: settings.groups
class Translations$settings$groups$ru extends Translations$settings$groups$en {
	Translations$settings$groups$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get general => 'Общие';
	@override String get connection => 'Подключение';
	@override String get privacy => 'Конфиденциальность';
}

// Path: tray.status
class Translations$tray$status$ru extends Translations$tray$status$en {
	Translations$tray$status$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get connect => 'Подключиться';
	@override String get connecting => 'Подключение';
	@override String get disconnect => 'Отключиться';
	@override String get disconnecting => 'Отключение';
}

// Path: failure.clash
class Translations$failure$clash$ru extends Translations$failure$clash$en {
	Translations$failure$clash$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Непредвиденная ошибка (Clash)';
	@override String core({required Object reason}) => 'Ошибка ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$ru extends Translations$failure$singbox$en {
	Translations$failure$singbox$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Непредвиденная ошибка (SingBox)';
	@override String get serviceNotRunning => 'Сервис не запущен';
	@override String get missingPrivilege => 'Отсутствие прав';
	@override String get missingPrivilegeMsg => 'Режим VPN требует прав администратора. Перезапустите приложение от имени администратора или измените режим работы приложения.';
	@override String get missingGeoAssets => 'Отсутствуют географические ресурсы';
	@override String get missingGeoAssetsMsg => 'Георесурсы отсутствуют. Изменените выбранный ресурс или загрузите собственный в настройках.';
	@override String get invalidConfigOptions => 'Неправильные параметры конфигурации';
	@override String get invalidConfig => 'Неправильная конфигурация';
	@override String get create => 'Ошибка создания сервиса';
	@override String get start => 'Ошибка запуска сервиса';
	@override String get coreLibraryMissing => 'Библиотека ядра не установлена';
	@override String get startTimeout => 'Истекло время запуска службы';
	@override String get kernelUnresponsive => 'Ядро не отвечает. Повторите попытку или перезапустите приложение.';
	@override String get kernelExited => 'Ядро неожиданно завершило работу';
}

// Path: failure.connectivity
class Translations$failure$connectivity$ru extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Непредвиденная ошибка';
	@override String get missingVpnPermission => 'Отсутствует разрешение VPN';
	@override String get missingNotificationPermission => 'Отсутствует разрешение на показ уведомлений';
	@override String get core => 'Ошибка ядра';
	@override String get networkUnavailable => 'Сеть недоступна';
	@override String get nativeUnresponsive => 'Потеряна связь с фоновой службой. Повторите попытку.';
}

// Path: failure.profiles
class Translations$failure$profiles$ru extends Translations$failure$profiles$en {
	Translations$failure$profiles$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Непредвиденная ошибка';
	@override String get notFound => 'Профиль не найден';
	@override String get invalidConfig => 'Неправильная конфигурация';
	@override String get invalidUrl => 'Неправильный URL';
	@override String get noActive => 'Нет активного профиля';
	@override String get readOnlyUpgrade => 'Обновите приложение, прежде чем изменять подписки';
}

// Path: failure.connection
class Translations$failure$connection$ru extends Translations$failure$connection$en {
	Translations$failure$connection$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Неожиданная ошибка подключения';
	@override String get timeout => 'Истекло время подключения';
	@override String get badResponse => 'Неправильный ответ';
	@override String get connectionError => 'Ошибка подключения';
	@override String get badCertificate => 'Неправильный сертификат';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$ru extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Неожиданная ошибка';
	@override String get notUpdate => 'Нет доступных обновлений';
	@override String get activeNotFound => 'Активный географический актив не найден';
}

// Path: config.serviceModes
class Translations$config$serviceModes$ru extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Прокси';
	@override String get systemProxy => 'Системный прокси';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN сервис';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$ru extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Прокси';
	@override String get systemProxy => 'Системный прокси';
	@override String get tun => 'VPN';
	@override String get tunService => 'VPN сервис';
}

// Path: config.section
class Translations$config$section$ru extends Translations$config$section$en {
	Translations$config$section$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get route => 'Варианты маршрутизации';
	@override String get dns => 'Параметры DNS';
	@override String get inbound => 'Входящие параметры';
	@override String get mux => 'Multiplexer';
	@override String get outbound => 'Outbound Options';
	@override String get tlsTricks => 'TLS Tricks';
	@override String get warp => 'WARP Options';
	@override String get misc => 'Разные параметры';
}

// Path: config.warpConsent
class Translations$config$warpConsent$ru extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get title => 'Согласие Cloudflare WARP';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP — бесплатный провайдер WireGuard VPN. Включая эту опцию, вы соглашаетесь с '),
		tos('Условиями обслуживания'),
		const TextSpan(text: ' и '),
		privacy('Политикой конфиденциальности'),
		const TextSpan(text: ' Cloudflare WARP.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$ru extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Отключено';
	@override String get enable => 'Включено';
	@override String get prefer => 'Предпочтительно';
	@override String get only => 'Исключительно';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$ru extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get proxyOverWarp => 'Работа прокси через WARP';
	@override String get warpOverProxy => 'Работа WARP через прокси';
	@override String get inbound => 'Detour WARP through proxies';
	@override String get outbound => 'Detour proxies through WARP';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$ru extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'Нет прав';
	@override String get unexpectedError => 'Неизвестная ошибка';
	@override String get torchSemanticLabel => 'Вспышка';
	@override String get facingSemanticLabel => 'Фронтальная камера';
	@override String get permissionRequest => 'Права на использование камеры для считывания QR';
}

// Path: settings.general.regions
class Translations$settings$general$regions$ru extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get ir => 'Иран (ir)';
	@override String get cn => 'Китай (cn)';
	@override String get ru => 'Россия (ru)';
	@override String get af => 'Afghanistan (af)';
	@override String get id => 'Индонезия (id)';
	@override String get other => 'Другой';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$ru extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get system => 'Системная тема';
	@override String get dark => 'Тёмная тема';
	@override String get light => 'Светлая тема';
	@override String get black => 'Чёрная тема';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$ru extends Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Включено';
	@override String get denied => 'Выключено';
	@override String get pending => '…';
	@override String get unknown => 'Неизвестно';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$ru extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'Исключено';
	@override String get notExempted => 'Не исключено';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$ru extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$ru._(TranslationsRu root) : this._root = root, super.internal(root);

	final TranslationsRu _root; // ignore: unused_field

	// Translations
	@override String get off => 'Все';
	@override String get offMsg => 'Проксировать все приложения';
	@override String get include => 'Прокси';
	@override String get includeMsg => 'Проксировать выбранные приложения';
	@override String get exclude => 'Обход';
	@override String get excludeMsg => 'Не проксировать выбранные приложения';
}

/// The flat map containing all translations for locale <ru>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsRu {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Сброс',
			'general.toggle.enabled' => 'Включено',
			'general.toggle.disabled' => 'Отключено',
			'general.state.disable' => 'Отключить',
			'general.sort' => 'Сортировка',
			'general.sortBy' => 'Сортировка',
			'general.addToClipboard' => 'Копировать в буфер обмена',
			'general.notSet' => 'Не задано',
			'general.agree' => 'Соглашаться',
			'general.decline' => 'Отклонить',
			'general.unknown' => 'Неизвестный',
			'general.hidden' => 'Скрытый',
			'general.timeout' => 'Таймаут',
			'general.clipboardExportSuccessMsg' => 'Скопировано',
			'general.showMore' => 'Развернуть ',
			'general.showLess' => 'Свернуть ',
			'general.openAppSettings' => 'Открыть настройки',
			'general.grantPermission' => 'Дать права доступа',
			'general.underDevelopment' => 'В разработке',
			'general.confirm' => 'Подтвердить',
			'general.close' => 'Закрыть',
			'general.cancel' => 'Отмена',
			'general.clipboardEmpty' => 'Буфер обмена пуст',
			'general.clipboardReadFailed' => 'Не удалось прочитать буфер обмена',
			'general.moreOptions' => 'Дополнительно',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'Продолжая, Вы соглашаетесь с '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => 'Начать',
			'home.pageTitle' => 'Главная',
			'home.emptyProfilesMsg' => 'Начните с добавления профиля подписки',
			'home.noActiveProfileMsg' => 'Выберите профиль',
			'home.routingMode.global' => 'Глобальный прокси',
			'home.routingMode.smart' => 'Умная маршрутизация',
			'home.failedToSwitchMode' => ({required Object error}) => 'Не удалось сменить режим: ${error}',
			'home.connectionFailedTitle' => 'Не удалось подключиться',
			'home.coreMissingTitle' => 'Библиотека ядра не найдена',
			'home.coreMissingMsg' => 'Приложению не удалось загрузить сетевое ядро. Подключение недоступно. Переустановите приложение или убедитесь, что файл библиотеки ядра находится рядом с исполняемым файлом.',
			'home.degradedTitle' => 'Подключено, но нет доступа в интернет',
			'home.degradedMsg' => 'Туннель поднят, но трафик не проходит. Возможно, узел недоступен — попробуйте другой узел или отключитесь.',
			'home.degradedRetry' => 'Проверить ещё раз',
			'home.egressIp.label' => 'Выходной IP',
			'home.egressIp.notConnected' => 'Подключитесь, чтобы увидеть выходной IP',
			'home.egressIp.tapToCheck' => 'Нажмите, чтобы проверить выходной IP',
			'home.egressIp.checking' => 'Проверка…',
			'home.egressIp.failedRetry' => 'Не удалось проверить, нажмите для повтора',
			'home.emptyProfilesHint' => 'Нажмите кнопку ниже, чтобы начать',
			'home.noActiveProfileTitle' => 'Профиль не выбран',
			'stats.traffic' => 'Трафик',
			'stats.trafficLive' => 'Текущий трафик',
			'stats.trafficTotal' => 'Трафик',
			'stats.uplink' => 'Скорость отправки',
			'stats.downlink' => 'Скорость загрузки',
			'stats.connection' => 'Соединение ',
			'stats.speed' => 'Скорость',
			'stats.totalTransferred' => 'Всего передано',
			'stats.trafficUsage' => 'Использование трафика',
			'stats.liveSpeed' => 'Текущая скорость',
			'stats.sessionTraffic' => 'Трафик за сеанс',
			'stats.downloadSpeed' => 'Скорость загрузки',
			'profile.overviewPageTitle' => 'Профили',
			'profile.detailsPageTitle' => 'Профиль',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Имя активного профиля: «${name}».',
			'profile.activeProfileBtnSemanticLabel' => 'Посмотреть все профили',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Выберите «${name}» в качестве активного профиля.',
			'profile.subscription.traffic' => 'Трафик',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => 'Обновлено ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => 'Ещё ${duration} дн',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => 'Использовано ${consumed} трафика из ${total}',
			'profile.subscription.expired' => 'Истекло',
			'profile.subscription.noTraffic' => 'Нет доступного трафика',
			'profile.subscription.upload' => 'Отправлено ',
			'profile.subscription.download' => 'Скачано',
			'profile.subscription.total' => 'Всего трафика',
			'profile.subscription.expireDate' => 'Дата окончания подписки ',
			'profile.sortBy.lastUpdate' => 'по последнему обновлению',
			'profile.sortBy.name' => 'по названию',
			'profile.add.buttonText' => 'Новый профиль',
			'profile.add.shortBtnTxt' => 'Новый профиль',
			'profile.add.fromClipboard' => 'Добавить из буфера обмена',
			'profile.add.scanQr' => 'Сканировать QR-код',
			'profile.add.qrScanner.permissionDeniedError' => 'Нет прав',
			'profile.add.qrScanner.unexpectedError' => 'Неизвестная ошибка',
			'profile.add.qrScanner.torchSemanticLabel' => 'Вспышка',
			'profile.add.qrScanner.facingSemanticLabel' => 'Фронтальная камера',
			'profile.add.qrScanner.permissionRequest' => 'Права на использование камеры для считывания QR',
			'profile.add.manually' => 'Ввести вручную',
			'profile.add.addingProfileMsg' => 'Добавление профиля',
			'profile.add.failureMsg' => 'Не удалось добавить профиль',
			'profile.add.modalSubtitle' => 'Выберите способ добавления файла конфигурации',
			'profile.add.manuallyDescription' => 'Введите конфигурацию сервера вручную',
			'profile.add.addWarp' => 'Добавить WARP',
			'profile.add.warpDescription' => 'Бесплатное ускорение через Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'Подождите, идёт регистрация WARP.',
			'profile.add.importedNamed' => ({required Object name}) => 'Подписка импортирована: ${name}',
			'profile.add.clipboardEmpty' => 'Буфер обмена пуст, импортировать нечего',
			'profile.add.deepLinkMissingUrl' => 'В ссылке нет адреса подписки',
			'profile.add.successMsg' => 'Профиль добавлен',
			'profile.add.nameAutoHint' => 'Определяется автоматически (необязательно)',
			'profile.update.buttonTxt' => 'Обновить',
			'profile.update.tooltip' => 'Обновить профиль',
			'profile.update.updateSubscriptions' => 'Обновить подписки',
			'profile.update.failureMsg' => 'Не удалось обновить профиль',
			'profile.update.successMsg' => 'Профиль успешно обновлён',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'Не удалось обновить "${name}".',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" успешно обновлено',
			'profile.share.buttonText' => 'Поделиться',
			'profile.share.exportToClipboardSuccess' => 'Ссылка скопирована в буфер обмена',
			'profile.share.exportSubLinkToClipboard' => 'Скопировать ссылку на подписку в буфер обмена',
			'profile.share.subLinkQrCode' => 'QR-код ссылки на подписку',
			'profile.share.exportConfigToClipboard' => 'Скопировать конфигурацию в буфер обмена',
			'profile.share.exportConfigToClipboardSuccess' => 'Конфигурация скопирована в буфер обмена',
			'profile.share.shareLink' => 'Поделиться ссылкой',
			'profile.share.subscriptionLinkCopied' => 'Ссылка на подписку скопирована',
			'profile.share.configCopied' => 'Конфигурация скопирована',
			'profile.share.copyFailed' => 'Не удалось скопировать',
			'profile.edit.buttonTxt' => 'Изменить',
			'profile.edit.selectActiveTxt' => 'Выберите активный профиль',
			'profile.delete.buttonTxt' => 'Удалить',
			'profile.delete.confirmationMsg' => 'Безвозвратно удалить профиль?',
			'profile.delete.successMsg' => 'Профиль успешно удалён',
			'profile.delete.confirmTitle' => 'Удалить профиль',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => 'Удалить «${name}»? Это действие нельзя отменить.',
			'profile.save.buttonText' => 'Сохранить',
			'profile.save.successMsg' => 'Профиль успешно сохранён',
			'profile.save.failureMsg' => 'Не удалось сохранить профиль',
			'profile.detailsForm.nameLabel' => 'Имя',
			'profile.detailsForm.nameHint' => 'Имя профиля',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'Полный URL конфигурации',
			'profile.detailsForm.emptyNameMsg' => 'Поле «Имя» обязательно',
			'profile.detailsForm.invalidUrlMsg' => 'Неправильный URL',
			'profile.detailsForm.lastUpdate' => 'Последнее обновление',
			'profile.detailsForm.updateInterval' => 'Автоматическое обновление',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Интервал обновления (в часах)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Выкл.',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} ч',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} дн.',
			'profile.actionButtons.add' => 'Добавить',
			'profile.actionButtons.updateAll' => 'Обновить все',
			'profile.actionButtons.sort' => 'Сортировать',
			'profile.actionButtons.copyConfigSuccess' => 'Конфигурация скопирована',
			'profile.actionButtons.editConfig' => 'Изменить конфигурацию',
			'profile.details.basicInfo' => 'Основные сведения',
			'profile.details.subscriptionStatus' => 'Состояние подписки',
			'profile.details.options' => 'Параметры',
			'profile.details.updateNow' => 'Обновить сейчас',
			'profile.details.updateNowDescription' => 'Загрузить актуальную конфигурацию с сервера',
			'profile.details.expireDate' => 'Дата окончания',
			'profile.details.unlimited' => 'Безлимитно',
			'profile.overview.currentlyUsing' => 'Используется сейчас',
			'profile.overview.remainingDays' => ({required Object days}) => 'Осталось ${days} дн.',
			'profile.remoteProfile' => 'Удалённый профиль',
			'profile.defaultLocalName' => 'Локальный импорт',
			'profile.defaultDeepLinkName' => 'Импорт по ссылке',
			'profile.switchFailedMsg' => 'Не удалось переключить профиль',
			'proxies.pageTitle' => 'Прокси',
			'proxies.emptyProxiesMsg' => 'Нет доступных прокси',
			'proxies.delayTestTooltip' => 'Тестирование задержки',
			'proxies.sortTooltip' => 'Сортировка прокси',
			'proxies.checkIp' => 'Проверить IP',
			'proxies.unknownIp' => 'Неизвестный IP',
			'proxies.sortOptions.unsorted' => 'По умолчанию',
			'proxies.sortOptions.name' => 'По алфавиту',
			'proxies.sortOptions.delay' => 'По задержке',
			'proxies.activeProxySemanticLabel' => 'Активный прокси',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'Задержка: ${delay}мс',
			'proxies.delaySemantics.timeout' => 'Тайм-аут при тестировании задержки',
			'proxies.delaySemantics.testing' => 'Задержка: Тестирование...',
			'proxies.delaySemantics.untested' => 'Задержка: не проверялась',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'Задержка: ${delay}мс (прежний результат)',
			'proxies.ipInfoSemantics.address' => 'IP адрес',
			'proxies.ipInfoSemantics.country' => 'Страна',
			'proxies.autoSelect' => 'Автовыбор',
			'proxies.autoSelectDescription' => 'Автоматически подключаться к самому быстрому узлу',
			'proxies.sortModalTitle' => 'Выберите способ сортировки',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Проверка задержки: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'Переключено на ${name}',
			'proxies.switchFailed' => 'Не удалось переключить сервер. Попробуйте ещё раз.',
			'proxies.testFailed' => 'Не удалось проверить задержку. Попробуйте ещё раз.',
			'proxies.groupsLoading' => 'Список серверов ещё загружается. Повторите попытку через минуту.',
			'proxies.connectBeforeSwitch' => 'Подключитесь перед сменой линии',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'Запущена проверка задержки для ${count} линий',
			'proxies.delayTestBtn' => 'Задержка',
			'proxies.delayTimeout' => 'Тайм-аут',
			'proxies.connectBeforeTest' => 'Сначала подключитесь, чтобы проверить задержку',
			'proxies.lineCount' => ({required Object count}) => 'Линий: ${count}',
			'proxies.manualSelect' => 'Ручной выбор',
			'proxies.autoTest' => 'Автотест',
			'logs.pageTitle' => 'Журналы',
			'logs.filterHint' => 'Фильтр',
			'logs.allLevelsFilter' => 'Все',
			'logs.shareCoreLogs' => 'Поделиться журналами ядра',
			'logs.shareAppLogs' => 'Поделиться журналами приложения',
			'logs.pauseTooltip' => 'Приостановить',
			'logs.resumeTooltip' => 'Возобновить',
			'logs.clearTooltip' => 'Очистить',
			'logs.logsCleared' => 'Журналы очищены',
			'logs.logsCopied' => 'Журналы скопированы',
			'logs.logsUnderDevelopment' => 'Функция журналов в разработке',
			'logs.noLogsWhenDisconnected' => 'Нет подключения, журналы отсутствуют',
			'logs.loadFailed' => 'Не удалось загрузить журнал',
			'logs.empty' => 'Журнал пока пуст',
			'logs.clearFailed' => 'Не удалось очистить журнал',
			'settings.pageTitle' => 'Настройки',
			'settings.requiresRestartMsg' => 'Чтобы применить изменения, перезапустите приложение.',
			'settings.experimental' => 'Экспериментальный',
			'settings.experimentalMsg' => 'Функции с флагом «Экспериментально» все еще находятся в разработке и могут вызвать проблемы.',
			'settings.importOptions' => 'Импорт параметров из буфера обмена',
			'settings.importOptionsMsg' => 'Это перезапишет все параметры конфига предоставленными значениями. Вы уверены?',
			'settings.backup.importConfirmTitle' => 'Импорт резервной копии',
			'settings.backup.importConfirmMsg' => 'Ваши подписки будут заменены подписками из резервной копии, а настройки из неё применены. Сначала сохраняется снимок текущих данных, который автоматически восстанавливается, если импорт не удастся.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => 'Подписок на этом устройстве, которых нет в резервной копии, будет удалено: ${count}.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => 'Импортировано подписок: ${profiles}, настроек: ${settings}.',
			'settings.backup.reportDropped' => ({required Object count}) => 'Пропущено подписок из резервной копии из-за недопустимых данных: ${count}.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => 'Пропущено настроек: ${count}; текущие значения сохранены.',
			'settings.backup.reportWarpOff' => 'При импорте WARP был выключен. Включите его заново на этом устройстве.',
			'settings.backup.reportBackfill' => ({required Object count}) => 'Подписок, которые будут загружены в фоне: ${count}.',
			'settings.backup.errInvalidFile' => 'Это не файл резервной копии ClashMiao.',
			'settings.backup.errUnsupportedVersion' => 'Этот формат резервной копии не поддерживается.',
			'settings.backup.errNewerSchema' => 'Эта резервная копия создана более новой версией приложения. Сначала обновите приложение.',
			'settings.backup.errNoUsableProfiles' => 'Ни одну подписку из этой резервной копии нельзя импортировать.',
			'settings.backup.errSnapshotFailed' => 'Не удалось сохранить снимок текущих данных, поэтому ничего не изменено.',
			'settings.backup.errUnresolvedPrevious' => 'Предыдущий импорт был прерван и пока не отменён. Ничего не изменено. Перезапустите приложение и повторите попытку.',
			'settings.backup.errRolledBack' => 'Не удалось импортировать. Прежние данные восстановлены.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'Не удалось импортировать, а автоматическое восстановление не завершилось. Перезапустите приложение, чтобы повторить его. Снимок сохранён в ${path}.',
			'settings.backup.errFailed' => 'Не удалось импортировать.',
			'settings.backup.errBusy' => 'Другой импорт уже выполняется. Дождитесь его завершения.',
			'settings.backup.recoveryFailedTitle' => 'Автоматическое восстановление не завершилось',
			'settings.backup.recoveryFailedMsg' => 'Последний импорт резервной копии был прерван, и приложению не удалось вернуть данные в прежнее состояние. Часть данных могла быть импортирована не полностью. Повторите автоматическое восстановление.',
			'settings.backup.recoveryUnrecoverableTitle' => 'Не удалось отменить прерванный импорт',
			'settings.backup.recoveryUnrecoverableMsg' => 'Последний импорт резервной копии был прерван, но его снимок отсутствует или не читается, поэтому отменить его нельзя. Проверьте свои подписки и настройки.',
			'settings.backup.recoveryRetry' => 'Повторить',
			'settings.backup.recoveryClose' => 'Закрыть',
			'settings.backup.recoveryRetried' => 'Данные возвращены в состояние до прерванного импорта.',
			'settings.backup.exportAction' => 'Экспорт резервной копии',
			'settings.backup.importAction' => 'Импорт резервной копии',
			'settings.backup.exportFailed' => 'Не удалось экспортировать резервную копию',
			'settings.backup.shareText' => 'Резервная копия ClashMiao',
			'settings.general.sectionTitle' => 'Основные',
			'settings.general.locale' => 'Язык',
			'settings.general.region' => 'Регион',
			'settings.general.regionMsg' => 'Помогает установить параметры по умолчанию для обхода внутренних адресов.',
			'settings.general.regions.ir' => 'Иран (ir)',
			'settings.general.regions.cn' => 'Китай (cn)',
			'settings.general.regions.ru' => 'Россия (ru)',
			'settings.general.regions.af' => 'Afghanistan (af)',
			'settings.general.regions.id' => 'Индонезия (id)',
			'settings.general.regions.other' => 'Другой',
			'settings.general.themeMode' => 'Оформление',
			'settings.general.themeModes.system' => 'Системная тема',
			'settings.general.themeModes.dark' => 'Тёмная тема',
			'settings.general.themeModes.light' => 'Светлая тема',
			'settings.general.themeModes.black' => 'Чёрная тема',
			'settings.general.enableAnalytics' => 'Сбор аналитики',
			'settings.general.enableAnalyticsMsg' => 'Сбор данных аналитики и отправка отчётов о сбоях для улучшения приложения',
			'settings.general.autoStart' => 'Запуск при загрузке',
			'settings.general.silentStart' => 'Тихий запуск',
			'settings.general.openWorkingDir' => 'Открыть рабочую папку',
			'settings.general.ignoreBatteryOptimizations' => 'Отключить оптимизацию батареи',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Отключение ограничений для оптимальной производительности VPN.',
			'settings.general.dynamicNotification' => 'Отображение скорости в уведомлении',
			'settings.general.autoIpCheck' => 'Автоматически проверять IP-адрес соединения',
			'settings.general.hapticFeedback' => 'Тактильная отдача',
			'settings.general.autoStartPermission' => 'Разрешить автозапуск',
			'settings.general.autoStartPermissionMsg' => 'Если включено, подключение автоматически восстановится после перезагрузки телефона или обновления приложения',
			'settings.general.autoStartPermissionStatus.allowed' => 'Включено',
			'settings.general.autoStartPermissionStatus.denied' => 'Выключено',
			'settings.general.autoStartPermissionStatus.pending' => '…',
			'settings.general.autoStartPermissionStatus.unknown' => 'Неизвестно',
			'settings.general.batteryOptimizationStatus.exempted' => 'Исключено',
			'settings.general.batteryOptimizationStatus.notExempted' => 'Не исключено',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Расширенные',
			'settings.advanced.debugMode' => 'Режим отладки',
			'settings.advanced.debugModeMsg' => 'Чтобы применить изменения, перезапустите приложение.',
			'settings.advanced.memoryLimit' => 'Ограничение памяти',
			'settings.advanced.memoryLimitMsg' => 'Включите, если у вас возникают ошибки нехватки памяти или частые сбои приложения.',
			'settings.advanced.resetTunnel' => 'Сбросить профиль VPN',
			'settings.advanced.resetTunnelSuccess' => 'Профиль VPN сброшен',
			'settings.network.perAppProxyPageTitle' => 'Раздельное проксирование',
			'settings.network.perAppProxyModes.off' => 'Все',
			'settings.network.perAppProxyModes.offMsg' => 'Проксировать все приложения',
			'settings.network.perAppProxyModes.include' => 'Прокси',
			'settings.network.perAppProxyModes.includeMsg' => 'Проксировать выбранные приложения',
			'settings.network.perAppProxyModes.exclude' => 'Обход',
			'settings.network.perAppProxyModes.excludeMsg' => 'Не проксировать выбранные приложения',
			'settings.network.showSystemApps' => 'Показать системные приложения',
			'settings.network.hideSystemApps' => 'Скрыть системные приложения',
			'settings.network.clearSelection' => 'Очистить выбор',
			'settings.network.perAppProxyLoadFailedMsg' => 'Не удалось загрузить список приложений',
			'settings.network.perAppProxyRetry' => 'Повторить',
			'settings.network.perAppProxyEmptyMsg' => 'Ничего не найдено',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'Режим линий для отдельных приложений поддерживается только на Android',
			'settings.geoAssets.pageTitle' => 'Активы маршрутизации',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => 'Версия ${version}',
			'settings.geoAssets.fileMissing' => 'Файл отсутствует',
			'settings.geoAssets.update' => 'Обновить',
			'settings.geoAssets.download' => 'Скачать',
			'settings.geoAssets.failureMsg' => 'Не удалось обновить объект',
			'settings.geoAssets.successMsg' => 'Объект успешно обновлен',
			'settings.geoAssets.addRecommended' => 'Добавить рекомендуемые активы',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Файлы выбранных ресурсов маршрутизации отсутствуют. Либо скачайте их, либо выберите существующие.',
			'settings.exportOptions' => 'Копировать анонимные параметры в буфер обмена',
			'settings.exportAllOptions' => 'Копировать все параметры в буфер обмена',
			'settings.systemProxyEnabled' => 'Системный прокси включён',
			'settings.systemProxyDisabled' => 'Системный прокси отключён (переподключитесь для применения)',
			'settings.adminPrivilegesRequired' => 'На macOS требуются права администратора',
			'settings.portChangeNotice' => 'Изменения порта применяются после переподключения',
			'settings.groups.general' => 'Общие',
			'settings.groups.connection' => 'Подключение',
			'settings.groups.privacy' => 'Конфиденциальность',
			'settings.importOptionsInvalid' => 'В буфере обмена нет корректного JSON настроек',
			'settings.importOptionsNothing' => 'Не найдено настроек для импорта',
			'settings.importOptionsDone' => ({required Object count}) => 'Импортировано настроек: ${count}',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => 'Импортировано: ${applied}; пропущено как некорректные: ${skipped}',
			'about.pageTitle' => 'О программе',
			'about.version' => 'Версия',
			'about.sourceCode' => 'Исходный код',
			'about.telegramChannel' => 'Telegram-канал',
			'about.checkForUpdate' => 'Проверка обновления',
			'about.privacyPolicy' => 'Политика конфиденциальности',
			'about.termsAndConditions' => 'Условия и положения',
			'about.appDescription' => 'Кроссплатформенный прокси-клиент на основе ядра sing-box',
			'about.openSourceLicenses' => 'Лицензии открытого ПО',
			'appUpdate.notAvailableMsg' => 'Установлена последняя версия',
			'appUpdate.dialogTitle' => 'Доступно обновление',
			'appUpdate.updateMsg' => 'Доступна новая версия ${_root.general.appTitle}. Обновить сейчас?',
			'appUpdate.currentVersionLbl' => 'Текущая версия',
			'appUpdate.newVersionLbl' => 'Новая версия',
			'appUpdate.updateNowBtnTxt' => 'Обновить',
			'appUpdate.laterBtnTxt' => 'Позже',
			'appUpdate.ignoreBtnTxt' => 'Пропустить',
			'appUpdate.checkFailedMsg' => 'Не удалось проверить обновления. Проверьте сеть и повторите попытку.',
			'tray.dashboard' => 'Панель',
			'tray.quit' => 'Выход',
			'tray.open' => 'Открыть',
			'tray.status.connect' => 'Подключиться',
			'tray.status.connecting' => 'Подключение',
			'tray.status.disconnect' => 'Отключиться',
			'tray.status.disconnecting' => 'Отключение',
			'tray.hide' => 'Скрыть',
			'tray.proxyModeMenu' => 'Режим прокси',
			'failure.unexpected' => 'Непредвиденная ошибка',
			'failure.clash.unexpected' => 'Непредвиденная ошибка (Clash)',
			'failure.clash.core' => ({required Object reason}) => 'Ошибка ${reason}',
			'failure.singbox.unexpected' => 'Непредвиденная ошибка (SingBox)',
			'failure.singbox.serviceNotRunning' => 'Сервис не запущен',
			'failure.singbox.missingPrivilege' => 'Отсутствие прав',
			'failure.singbox.missingPrivilegeMsg' => 'Режим VPN требует прав администратора. Перезапустите приложение от имени администратора или измените режим работы приложения.',
			'failure.singbox.missingGeoAssets' => 'Отсутствуют географические ресурсы',
			'failure.singbox.missingGeoAssetsMsg' => 'Георесурсы отсутствуют. Изменените выбранный ресурс или загрузите собственный в настройках.',
			'failure.singbox.invalidConfigOptions' => 'Неправильные параметры конфигурации',
			'failure.singbox.invalidConfig' => 'Неправильная конфигурация',
			'failure.singbox.create' => 'Ошибка создания сервиса',
			'failure.singbox.start' => 'Ошибка запуска сервиса',
			'failure.singbox.coreLibraryMissing' => 'Библиотека ядра не установлена',
			'failure.singbox.startTimeout' => 'Истекло время запуска службы',
			'failure.singbox.kernelUnresponsive' => 'Ядро не отвечает. Повторите попытку или перезапустите приложение.',
			'failure.singbox.kernelExited' => 'Ядро неожиданно завершило работу',
			'failure.connectivity.unexpected' => 'Непредвиденная ошибка',
			'failure.connectivity.missingVpnPermission' => 'Отсутствует разрешение VPN',
			'failure.connectivity.missingNotificationPermission' => 'Отсутствует разрешение на показ уведомлений',
			'failure.connectivity.core' => 'Ошибка ядра',
			'failure.connectivity.networkUnavailable' => 'Сеть недоступна',
			'failure.connectivity.nativeUnresponsive' => 'Потеряна связь с фоновой службой. Повторите попытку.',
			'failure.profiles.unexpected' => 'Непредвиденная ошибка',
			'failure.profiles.notFound' => 'Профиль не найден',
			'failure.profiles.invalidConfig' => 'Неправильная конфигурация',
			'failure.profiles.invalidUrl' => 'Неправильный URL',
			'failure.profiles.noActive' => 'Нет активного профиля',
			'failure.profiles.readOnlyUpgrade' => 'Обновите приложение, прежде чем изменять подписки',
			'failure.connection.unexpected' => 'Неожиданная ошибка подключения',
			'failure.connection.timeout' => 'Истекло время подключения',
			'failure.connection.badResponse' => 'Неправильный ответ',
			'failure.connection.connectionError' => 'Ошибка подключения',
			'failure.connection.badCertificate' => 'Неправильный сертификат',
			'failure.geoAssets.unexpected' => 'Неожиданная ошибка',
			'failure.geoAssets.notUpdate' => 'Нет доступных обновлений',
			'failure.geoAssets.activeNotFound' => 'Активный географический актив не найден',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Нажмите для подключения',
			'connection.connecting' => 'Подключение',
			'connection.disconnecting' => 'Отключение',
			'connection.connected' => 'Подключено',
			'connection.reconnect' => 'Восстановить соединение',
			'connection.connectAnyWay' => 'Всё равно подключиться',
			'connection.experimentalNotice' => 'Экспериментальные функции в использовании',
			'connection.experimentalNoticeMsg' => 'Вы включили некоторые экспериментальные функции, которые могут повлиять на качество соединения и вызвать непредвиденные ошибки. Вы всегда можете изменить или сбросить эти параметры на странице параметров конфигурации.',
			'connection.disableExperimentalNotice' => 'Больше не показывать',
			'connection.reconnectMsg' => 'Переподключить для применения изменений',
			'connection.staleSystemProxyCleaned' => 'Удалены настройки системного прокси, оставшиеся после аварийного завершения',
			'config.resetBtn' => 'Сбросить параметры',
			'config.serviceMode' => 'Режим работы',
			'config.quickSettings' => 'Быстрые настройки',
			'config.setupWarp' => 'Настроить WARP',
			'config.allOptions' => 'Все параметры ',
			'config.serviceModes.proxy' => 'Прокси',
			'config.serviceModes.systemProxy' => 'Системный прокси',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'VPN сервис',
			'config.shortServiceModes.proxy' => 'Прокси',
			'config.shortServiceModes.systemProxy' => 'Системный прокси',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'VPN сервис',
			'config.section.route' => 'Варианты маршрутизации',
			'config.section.dns' => 'Параметры DNS',
			'config.section.inbound' => 'Входящие параметры',
			'config.section.mux' => 'Multiplexer',
			'config.section.outbound' => 'Outbound Options',
			'config.section.tlsTricks' => 'TLS Tricks',
			'config.section.warp' => 'WARP Options',
			'config.section.misc' => 'Разные параметры',
			'config.warpConsent.title' => 'Согласие Cloudflare WARP',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP — бесплатный провайдер WireGuard VPN. Включая эту опцию, вы соглашаетесь с '), tos('Условиями обслуживания'), const TextSpan(text: ' и '), privacy('Политикой конфиденциальности'), const TextSpan(text: ' Cloudflare WARP.'), ]), 
			'config.generateWarpConfig' => 'Cгенерировать WARP конфиг',
			'config.missingWarpConfig' => 'Отсутствует WARP конфиг',
			'config.warpConfigGenerated' => 'WARP конфиг сгенерирован',
			'config.pageTitle' => 'Параметры конфигурации',
			'config.logLevel' => 'Подробность журналирования',
			'config.resolveDestination' => 'Определять назначение',
			'config.ipv6Mode' => 'Маршрутизация IPv6',
			'config.ipv6Modes.disable' => 'Отключено',
			'config.ipv6Modes.enable' => 'Включено',
			'config.ipv6Modes.prefer' => 'Предпочтительно',
			'config.ipv6Modes.only' => 'Исключительно',
			'config.remoteDnsAddress' => 'Удалённый DNS',
			'config.remoteDnsDomainStrategy' => 'Стратегия удалённого домена DNS',
			'config.directDnsAddress' => 'Прямой DNS',
			'config.directDnsDomainStrategy' => 'Стратегия прямого домена DNS',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'Не применено: маршрутизация IPv6 отключена, а «${field}» — только IPv6, поэтому ни один домен не разрешится. Сначала включите маршрутизацию IPv6 или выберите другую стратегию.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'Не применено: маршрутизация IPv6 — только IPv6, а «${field}» — только IPv4, поэтому ни один домен не разрешится. Сначала измените один из параметров.',
			'config.dnsStrategyReset' => ({required Object field}) => '«${field}» конфликтовала с настройкой маршрутизации IPv6 (ни один домен не разрешился бы) и сброшена на авто.',
			'config.mixedPort' => 'Смешанный порт',
			'config.tproxyPort' => 'Прозрачный прокси порт',
			'config.localDnsPort' => 'Локальный порт DNS',
			'config.allowConnectionFromLan' => 'Allow Connection from LAN',
			'config.tunImplementation' => 'Реализация TUN',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'URL проверки подключения',
			'config.urlTestInterval' => 'Интервал проверки URL',
			'config.enableClashApi' => 'Использовать Clash API',
			'config.clashApiPort' => 'Порт Clash API',
			'config.enableTun' => 'Использовать TUN',
			'config.setSystemProxy' => 'Использовать системный прокси',
			'config.enableDnsRouting' => 'Enable DNS Routing',
			'config.enableFakeDns' => 'Использовать поддельную DNS',
			'config.bypassLan' => 'Обход локальной сети',
			'config.strictRoute' => 'Строгая маршрутизация',
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
			'config.setUpWarp' => 'Настроить WARP',
			'config.warpNotConfigured' => 'Не настроено',
			'config.warpDetourMode' => 'Detour Mode',
			'config.warpDetourModes.proxyOverWarp' => 'Работа прокси через WARP',
			'config.warpDetourModes.warpOverProxy' => 'Работа WARP через прокси',
			'config.warpDetourModes.inbound' => 'Detour WARP through proxies',
			'config.warpDetourModes.outbound' => 'Detour proxies through WARP',
			'config.warpLicenseKey' => 'License Key',
			'config.warpCleanIp' => 'Clean IP',
			'config.warpPort' => 'Port',
			'config.warpNoise' => 'Noise',
			'config.quickSettingsSubtitle' => 'Настройте подключение под себя',
			'config.allAdvancedOptions' => 'Все дополнительные настройки',
			'config.blockAds' => 'Блокировать рекламу',
			'config.warpNoiseSize' => 'Размер шума',
			'config.warpNoiseMode' => 'Режим шума',
			'config.warpNoiseDelay' => 'Задержка шума',
			'config.desktopProxyScopeNotice' => 'На настольных системах через туннель идут только приложения, соблюдающие системный прокси. Программы, которые его игнорируют (некоторые игры, консольные утилиты, приложения с собственными настройками прокси), подключаются напрямую и раскрывают ваш реальный IP.',
			'config.serviceModeIosVpnOnly' => 'iOS поддерживает только режим VPN',
			'config.warpGenerating' => 'Создание конфигурации WARP…',
			'config.warpConfigFailed' => 'Не удалось создать конфигурацию WARP. Повторите попытку позже.',
			'config.portRangeError' => 'Порт должен быть от 1024 до 65535',
			'config.dnsEmptyError' => 'Адрес DNS не может быть пустым',
			'config.rangeFormatError' => 'Введите число или диапазон, например 10-30',
			'config.urlSchemeError' => 'URL должен начинаться с http:// или https://',
			'config.manageRuleAssets' => 'Наборы правил',
			_ => null,
		};
	}
}
