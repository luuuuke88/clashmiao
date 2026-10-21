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
class TranslationsEs extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.es,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <es>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsEs _root = this; // ignore: unused_field

	@override 
	TranslationsEs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEs(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$es general = Translations$general$es._(_root);
	@override late final Translations$intro$es intro = Translations$intro$es._(_root);
	@override late final Translations$home$es home = Translations$home$es._(_root);
	@override late final Translations$profile$es profile = Translations$profile$es._(_root);
	@override late final Translations$proxies$es proxies = Translations$proxies$es._(_root);
	@override late final Translations$logs$es logs = Translations$logs$es._(_root);
	@override late final Translations$settings$es settings = Translations$settings$es._(_root);
	@override late final Translations$about$es about = Translations$about$es._(_root);
	@override late final Translations$appUpdate$es appUpdate = Translations$appUpdate$es._(_root);
	@override late final Translations$tray$es tray = Translations$tray$es._(_root);
	@override late final Translations$failure$es failure = Translations$failure$es._(_root);
	@override late final Translations$connection$es connection = Translations$connection$es._(_root);
	@override late final Translations$config$es config = Translations$config$es._(_root);
	@override late final Translations$stats$es stats = Translations$stats$es._(_root);
}

// Path: general
class Translations$general$es extends Translations$general$en {
	Translations$general$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'Renicio';
	@override late final Translations$general$toggle$es toggle = Translations$general$toggle$es._(_root);
	@override late final Translations$general$state$es state = Translations$general$state$es._(_root);
	@override String get sort => 'Clasificar';
	@override String get sortBy => 'Ordenar por';
	@override String get addToClipboard => 'Añadir al portapapeles';
	@override String get notSet => 'No establecido';
	@override String get agree => 'Aceptar';
	@override String get decline => 'Rechazar';
	@override String get unknown => 'Desconocido';
	@override String get hidden => 'Oculto';
	@override String get timeout => 'Se acabó el tiempo';
	@override String get showMore => 'Mostrar más';
	@override String get showLess => 'Muestra menos';
	@override String get grantPermission => 'Conceder permiso';
	@override String get clipboardExportSuccessMsg => 'Copiado al portapapeles';
	@override String get openAppSettings => 'Abrir ajustes de la app';
	@override String get underDevelopment => 'En desarrollo';
	@override String get confirm => 'Confirmar';
	@override String get close => 'Cerrar';
	@override String get cancel => 'Cancelar';
	@override String get clipboardEmpty => 'El portapapeles está vacío';
	@override String get clipboardReadFailed => 'No se pudo leer el portapapeles';
	@override String get moreOptions => 'Más opciones';
}

// Path: intro
class Translations$intro$es extends Translations$intro$en {
	Translations$intro$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'al continuar, aceptas '),
		tap(_root.about.termsAndConditions),
	]);
	@override String get start => 'Comenzar';
}

// Path: home
class Translations$home$es extends Translations$home$en {
	Translations$home$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Hogar';
	@override String get emptyProfilesMsg => 'Comience agregando un perfil de suscripción';
	@override String get noActiveProfileMsg => 'Elige un perfil';
	@override late final Translations$home$routingMode$es routingMode = Translations$home$routingMode$es._(_root);
	@override String failedToSwitchMode({required Object error}) => 'Error al cambiar de modo: ${error}';
	@override String get connectionFailedTitle => 'Error de conexión';
	@override String get coreMissingTitle => 'No se encontró la biblioteca del núcleo';
	@override String get coreMissingMsg => 'La aplicación no pudo cargar su núcleo de red. La conexión no está disponible. Reinstala la aplicación o asegúrate de que el archivo de la biblioteca del núcleo esté junto al ejecutable.';
	@override String get degradedTitle => 'Conectado, pero sin acceso a Internet';
	@override String get degradedMsg => 'El túnel está activo pero el tráfico no pasa. Puede que el nodo esté caído: prueba otro nodo o desconéctate.';
	@override String get degradedRetry => 'Comprobar de nuevo';
	@override late final Translations$home$egressIp$es egressIp = Translations$home$egressIp$es._(_root);
	@override String get emptyProfilesHint => 'Toca el botón de abajo para empezar';
	@override String get noActiveProfileTitle => 'No hay ningún perfil seleccionado';
}

// Path: profile
class Translations$profile$es extends Translations$profile$en {
	Translations$profile$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'Perfiles';
	@override String get detailsPageTitle => 'Perfil';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'Nombre del perfil activo: "${name}".';
	@override String get activeProfileBtnSemanticLabel => 'Ver todos los perfiles';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Seleccione "${name}" como perfil activo.';
	@override late final Translations$profile$subscription$es subscription = Translations$profile$subscription$es._(_root);
	@override late final Translations$profile$sortBy$es sortBy = Translations$profile$sortBy$es._(_root);
	@override late final Translations$profile$add$es add = Translations$profile$add$es._(_root);
	@override late final Translations$profile$update$es update = Translations$profile$update$es._(_root);
	@override late final Translations$profile$share$es share = Translations$profile$share$es._(_root);
	@override late final Translations$profile$edit$es edit = Translations$profile$edit$es._(_root);
	@override late final Translations$profile$delete$es delete = Translations$profile$delete$es._(_root);
	@override late final Translations$profile$save$es save = Translations$profile$save$es._(_root);
	@override late final Translations$profile$detailsForm$es detailsForm = Translations$profile$detailsForm$es._(_root);
	@override late final Translations$profile$actionButtons$es actionButtons = Translations$profile$actionButtons$es._(_root);
	@override late final Translations$profile$details$es details = Translations$profile$details$es._(_root);
	@override late final Translations$profile$overview$es overview = Translations$profile$overview$es._(_root);
	@override String get remoteProfile => 'Perfil remoto';
	@override String get defaultLocalName => 'Importación local';
	@override String get defaultDeepLinkName => 'Importado desde enlace';
	@override String get switchFailedMsg => 'No se pudo cambiar de perfil';
}

// Path: proxies
class Translations$proxies$es extends Translations$proxies$en {
	Translations$proxies$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Proxies';
	@override String get emptyProxiesMsg => 'No proxies disponibles';
	@override String get delayTestTooltip => 'Prueba de Restraso';
	@override String get sortTooltip => 'Ordenar Proxies';
	@override late final Translations$proxies$sortOptions$es sortOptions = Translations$proxies$sortOptions$es._(_root);
	@override String get checkIp => 'Comprobar IP';
	@override String get unknownIp => 'IP desconocida';
	@override String get autoSelect => 'Selección automática';
	@override String get autoSelectDescription => 'Conectar automáticamente al nodo más rápido';
	@override String get sortModalTitle => 'Elige el método de ordenación';
	@override String get activeProxySemanticLabel => 'Línea activa';
	@override late final Translations$proxies$delaySemantics$es delaySemantics = Translations$proxies$delaySemantics$es._(_root);
	@override late final Translations$proxies$ipInfoSemantics$es ipInfoSemantics = Translations$proxies$ipInfoSemantics$es._(_root);
	@override String testingDelayInfo({required Object name}) => 'Probando latencia de: ${name}';
	@override String switchedTo({required Object name}) => 'Cambiado a ${name}';
	@override String get switchFailed => 'No se pudo cambiar de servidor. Inténtalo de nuevo.';
	@override String get testFailed => 'La prueba de latencia falló. Inténtalo de nuevo.';
	@override String get groupsLoading => 'La lista de servidores aún se está cargando. Inténtalo en un momento.';
	@override String get connectBeforeSwitch => 'Conéctate antes de cambiar de línea';
	@override String startDelayTestForGroups({required Object count}) => 'Prueba de latencia iniciada para ${count} líneas';
	@override String get delayTestBtn => 'Latencia';
	@override String get delayTimeout => 'Agotado';
	@override String get connectBeforeTest => 'Conéctate primero para probar la latencia';
	@override String lineCount({required Object count}) => '${count} líneas';
	@override String get manualSelect => 'Selección manual';
	@override String get autoTest => 'Prueba automática';
}

// Path: logs
class Translations$logs$es extends Translations$logs$en {
	Translations$logs$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Registros';
	@override String get filterHint => 'Filtrar';
	@override String get allLevelsFilter => 'Todo';
	@override String get shareCoreLogs => 'Compartir registros principales';
	@override String get shareAppLogs => 'Compartir registros de aplicaciones';
	@override String get pauseTooltip => 'Pausa';
	@override String get resumeTooltip => 'reanudar';
	@override String get clearTooltip => 'Claro';
	@override String get logsCleared => 'Registros borrados';
	@override String get logsCopied => 'Registros copiados';
	@override String get logsUnderDevelopment => 'La función de registros está en desarrollo';
	@override String get noLogsWhenDisconnected => 'Sin conexión, no hay registros';
	@override String get loadFailed => 'No se pudieron cargar los registros';
	@override String get empty => 'Aún no hay registros';
	@override String get clearFailed => 'No se pudieron borrar los registros';
}

// Path: settings
class Translations$settings$es extends Translations$settings$en {
	Translations$settings$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Ajustes';
	@override String get requiresRestartMsg => 'Para que esto surta efecto, reinicie la aplicación.';
	@override String get experimental => 'Experimental';
	@override String get experimentalMsg => 'Las funciones con el indicador Experimental aún están en desarrollo y pueden causar problemas.';
	@override late final Translations$settings$general$es general = Translations$settings$general$es._(_root);
	@override late final Translations$settings$advanced$es advanced = Translations$settings$advanced$es._(_root);
	@override late final Translations$settings$network$es network = Translations$settings$network$es._(_root);
	@override late final Translations$settings$geoAssets$es geoAssets = Translations$settings$geoAssets$es._(_root);
	@override String get exportOptions => 'Copiar opciones anónimas al portapapeles';
	@override String get exportAllOptions => 'Copiar todas las opciones al portapapeles';
	@override String get importOptions => 'Importar opciones desde el portapapeles';
	@override String get importOptionsMsg => 'Esto sobrescribirá todas las opciones de configuración con los valores proporcionados. ¿Continuar?';
	@override late final Translations$settings$backup$es backup = Translations$settings$backup$es._(_root);
	@override String get systemProxyEnabled => 'Proxy del sistema activado';
	@override String get systemProxyDisabled => 'Proxy del sistema desactivado (reconecta para aplicar)';
	@override String get adminPrivilegesRequired => 'Se requieren privilegios de administrador en macOS';
	@override String get portChangeNotice => 'Los cambios de puerto requieren reconectar para aplicarse';
	@override late final Translations$settings$groups$es groups = Translations$settings$groups$es._(_root);
	@override String get importOptionsInvalid => 'El portapapeles no contiene un JSON de ajustes válido';
	@override String get importOptionsNothing => 'No se encontraron ajustes importables';
	@override String importOptionsDone({required Object count}) => 'Se importaron ${count} ajustes';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => 'Se importaron ${applied} ajustes; se omitieron ${skipped} por no ser válidos';
}

// Path: about
class Translations$about$es extends Translations$about$en {
	Translations$about$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Acerca de';
	@override String get version => 'Versión';
	@override String get sourceCode => 'Código fuente';
	@override String get telegramChannel => 'Canal de telegramas';
	@override String get checkForUpdate => 'Buscar actualizaciones';
	@override String get privacyPolicy => 'Política de privacidad';
	@override String get termsAndConditions => 'Términos y condiciones';
	@override String get appDescription => 'Un cliente proxy multiplataforma basado en el núcleo sing-box';
	@override String get openSourceLicenses => 'Licencias de código abierto';
}

// Path: appUpdate
class Translations$appUpdate$es extends Translations$appUpdate$en {
	Translations$appUpdate$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'Ya estas usando la última versión.';
	@override String get dialogTitle => 'Actualización disponible';
	@override String get updateMsg => 'Hay disponible una nueva versión de ${_root.general.appTitle}. ¿Te gustaría actualizar ahora?';
	@override String get currentVersionLbl => 'Versión actual';
	@override String get newVersionLbl => 'Nueva versión';
	@override String get updateNowBtnTxt => 'Actualizar ahora';
	@override String get laterBtnTxt => 'Más tarde';
	@override String get ignoreBtnTxt => 'Ignorar';
	@override String get checkFailedMsg => 'No se pudo buscar actualizaciones. Revisa tu red e inténtalo de nuevo.';
}

// Path: tray
class Translations$tray$es extends Translations$tray$en {
	Translations$tray$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'Panel';
	@override String get quit => 'Abandonar';
	@override String get open => 'Abierto';
	@override late final Translations$tray$status$es status = Translations$tray$status$es._(_root);
	@override String get hide => 'Ocultar';
	@override String get proxyModeMenu => 'Modo de proxy';
}

// Path: failure
class Translations$failure$es extends Translations$failure$en {
	Translations$failure$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error inesperado';
	@override late final Translations$failure$clash$es clash = Translations$failure$clash$es._(_root);
	@override late final Translations$failure$singbox$es singbox = Translations$failure$singbox$es._(_root);
	@override late final Translations$failure$connectivity$es connectivity = Translations$failure$connectivity$es._(_root);
	@override late final Translations$failure$profiles$es profiles = Translations$failure$profiles$es._(_root);
	@override late final Translations$failure$connection$es connection = Translations$failure$connection$es._(_root);
	@override late final Translations$failure$geoAssets$es geoAssets = Translations$failure$geoAssets$es._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$es extends Translations$connection$en {
	Translations$connection$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'Toque para conectarse';
	@override String get connecting => 'Conectando';
	@override String get disconnecting => 'Desconectando';
	@override String get connected => 'Conectado';
	@override String get experimentalNotice => 'Funciones experimentales en uso';
	@override String get experimentalNoticeMsg => 'Ha habilitado algunas funciones experimentales que podrían afectar la calidad de la conexión y provocar errores inesperados. Siempre puede cambiar o restablecer estas opciones desde la página de opciones de configuración.';
	@override String get disableExperimentalNotice => 'No volver a mostrar';
	@override String get reconnect => 'Reconectar';
	@override String get connectAnyWay => 'Conectar de todos modos';
	@override String get reconnectMsg => 'Reconectando para aplicar los cambios...';
	@override String get staleSystemProxyCleaned => 'Se limpiaron los ajustes de proxy del sistema que quedaron de una salida anómala';
}

// Path: config
class Translations$config$es extends Translations$config$en {
	Translations$config$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'Restablecer opciones';
	@override String get serviceMode => 'Modo de servicio';
	@override late final Translations$config$serviceModes$es serviceModes = Translations$config$serviceModes$es._(_root);
	@override late final Translations$config$section$es section = Translations$config$section$es._(_root);
	@override late final Translations$config$warpConsent$es warpConsent = Translations$config$warpConsent$es._(_root);
	@override String get pageTitle => 'Opciones de configuración';
	@override String get logLevel => 'Registro del Nivel';
	@override String get resolveDestination => 'Resolver Destino';
	@override String get ipv6Mode => 'Ruta IPv6';
	@override late final Translations$config$ipv6Modes$es ipv6Modes = Translations$config$ipv6Modes$es._(_root);
	@override String get remoteDnsAddress => 'DNS Remoto';
	@override String get remoteDnsDomainStrategy => 'Estrategia de dominio DNS remoto';
	@override String get directDnsAddress => 'DNS Directo';
	@override String get directDnsDomainStrategy => 'Estrategia de dominio DNS directo';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'No aplicado: el enrutamiento IPv6 está desactivado pero "${field}" es solo IPv6, así que no se podría resolver ningún dominio. Activa primero el enrutamiento IPv6 o elige otra estrategia.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'No aplicado: el enrutamiento IPv6 es solo IPv6 pero "${field}" es solo IPv4, así que no se podría resolver ningún dominio. Ajusta primero uno de los dos.';
	@override String dnsStrategyReset({required Object field}) => '"${field}" entraba en conflicto con el enrutamiento IPv6 (no se podría resolver ningún dominio) y se restableció a automático.';
	@override String get mixedPort => 'Puerto Mixto';
	@override String get localDnsPort => 'Puerto DNS local';
	@override String get allowConnectionFromLan => 'Permitir conexión desde LAN';
	@override String get tunImplementation => 'Implementación de TUN';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'URL de prueba de conexión';
	@override String get urlTestInterval => 'URL Prueba de Intervalo';
	@override String get enableClashApi => 'Habilitar API de choque';
	@override String get clashApiPort => 'Puerto API de choque';
	@override String get enableTun => 'Habilitar sintonización';
	@override String get setSystemProxy => 'stablecer proxy del sistema';
	@override String get enableDnsRouting => 'Habilitar enrutamiento DNS';
	@override String get enableFakeDns => 'Habilitar DNS falso';
	@override String get bypassLan => 'Omitir LAN';
	@override String get strictRoute => 'Ruta estricta';
	@override String get enableTlsFragment => 'Habilitar fragmento TLS';
	@override String get tlsFragmentSize => 'Tamaño del fragmento TLS';
	@override String get tlsFragmentSleep => 'Sueño de fragmento TLS';
	@override String get enableTlsMixedSniCase => 'Habilitar caso SNI mixto TLS';
	@override String get enableTlsPadding => 'Habilitar el relleno TLS';
	@override String get tlsPaddingSize => 'Relleno TLS';
	@override String get enableMux => 'Enable Mux';
	@override String get muxProtocol => 'Mux Protocol';
	@override String get muxMaxStreams => 'Max Concurrent Streams';
	@override String get enableWarp => 'Enable WARP';
	@override String get setUpWarp => 'Configurar WARP';
	@override String get warpNotConfigured => 'Sin configurar';
	@override String get warpDetourMode => 'Detour Mode';
	@override late final Translations$config$warpDetourModes$es warpDetourModes = Translations$config$warpDetourModes$es._(_root);
	@override String get warpLicenseKey => 'License Key';
	@override String get warpCleanIp => 'Clean IP';
	@override String get warpPort => 'Port';
	@override String get warpNoise => 'Noise';
	@override String get quickSettings => 'Ajustes rápidos';
	@override String get quickSettingsSubtitle => 'Personaliza tu experiencia de conexión';
	@override String get setupWarp => 'Configurar WARP';
	@override String get allOptions => 'Todas las opciones de configuración';
	@override String get allAdvancedOptions => 'Todas las opciones avanzadas';
	@override late final Translations$config$shortServiceModes$es shortServiceModes = Translations$config$shortServiceModes$es._(_root);
	@override String get generateWarpConfig => 'Generar configuración WARP';
	@override String get missingWarpConfig => 'Falta la configuración WARP';
	@override String get warpConfigGenerated => 'Configuración WARP generada';
	@override String get blockAds => 'Bloquear anuncios';
	@override String get tproxyPort => 'Puerto de línea transparente';
	@override String get warpNoiseSize => 'Tamaño del ruido';
	@override String get warpNoiseMode => 'Modo de ruido';
	@override String get warpNoiseDelay => 'Retardo de ruido';
	@override String get desktopProxyScopeNotice => 'En el escritorio, solo las aplicaciones que respetan el proxy del sistema pasan por el túnel. El software que lo ignora (algunos juegos, herramientas de línea de comandos, aplicaciones con su propia configuración de proxy) se conecta directamente y expone tu IP real.';
	@override String get serviceModeIosVpnOnly => 'iOS solo admite el modo VPN';
	@override String get warpGenerating => 'Generando la configuración de WARP…';
	@override String get warpConfigFailed => 'No se pudo generar la configuración de WARP. Inténtalo más tarde.';
	@override String get portRangeError => 'El puerto debe estar entre 1024 y 65535';
	@override String get dnsEmptyError => 'La dirección DNS no puede estar vacía';
	@override String get rangeFormatError => 'Introduce un número o un rango, p. ej. 10-30';
	@override String get urlSchemeError => 'La URL debe empezar por http:// o https://';
	@override String get manageRuleAssets => 'Gestionar conjuntos de reglas';
}

// Path: stats
class Translations$stats$es extends Translations$stats$en {
	Translations$stats$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Tráfico';
	@override String get trafficLive => 'Tráfico en vivo';
	@override String get trafficTotal => 'Tráfico total';
	@override String get trafficUsage => 'Uso de tráfico';
	@override String get liveSpeed => 'Velocidad en vivo';
	@override String get uplink => 'Subida';
	@override String get downlink => 'Bajada';
	@override String get connection => 'Conexión';
	@override String get speed => 'Velocidad';
	@override String get totalTransferred => 'Total transferido';
	@override String get sessionTraffic => 'Tráfico de esta sesión';
	@override String get downloadSpeed => 'Velocidad de descarga';
}

// Path: general.toggle
class Translations$general$toggle$es extends Translations$general$toggle$en {
	Translations$general$toggle$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'Activado';
	@override String get disabled => 'Desactivado';
}

// Path: general.state
class Translations$general$state$es extends Translations$general$state$en {
	Translations$general$state$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Desactivar';
}

// Path: home.routingMode
class Translations$home$routingMode$es extends Translations$home$routingMode$en {
	Translations$home$routingMode$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get global => 'Proxy global';
	@override String get smart => 'Enrutamiento inteligente';
}

// Path: home.egressIp
class Translations$home$egressIp$es extends Translations$home$egressIp$en {
	Translations$home$egressIp$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get label => 'IP de salida';
	@override String get notConnected => 'Conéctate para ver la IP de salida';
	@override String get tapToCheck => 'Toca para comprobar la IP de salida';
	@override String get checking => 'Comprobando…';
	@override String get failedRetry => 'Error al comprobar, toca para reintentar';
}

// Path: profile.subscription
class Translations$profile$subscription$es extends Translations$profile$subscription$en {
	Translations$profile$subscription$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Tráfico';
	@override String updatedTimeAgo({required Object timeago}) => 'Actualizado ${timeago}';
	@override String remainingDuration({required Object duration}) => '${duration} días restantes';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed} de ${total} Tráfico Consumido';
	@override String get expired => 'Caducado';
	@override String get noTraffic => 'Fuera de cuota';
	@override String get upload => 'Subida';
	@override String get download => 'Descarga';
	@override String get total => 'Tráfico total';
	@override String get expireDate => 'Fecha de vencimiento';
}

// Path: profile.sortBy
class Translations$profile$sortBy$es extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'Recientemente actualizado';
	@override String get name => 'Alfabéticamente';
}

// Path: profile.add
class Translations$profile$add$es extends Translations$profile$add$en {
	Translations$profile$add$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Nuevo perfil';
	@override String get shortBtnTxt => 'Nuevo perfil';
	@override String get fromClipboard => 'Agregar desde el portapapeles';
	@override String get scanQr => 'Escanear código QR';
	@override late final Translations$profile$add$qrScanner$es qrScanner = Translations$profile$add$qrScanner$es._(_root);
	@override String get manually => 'Entrada manual';
	@override String get addingProfileMsg => 'Agregar perfil';
	@override String get failureMsg => 'No se pudo agregar el perfil';
	@override String get modalSubtitle => 'Elige cómo añadir el archivo de configuración';
	@override String get manuallyDescription => 'Introduce la configuración del servidor manualmente';
	@override String get addWarp => 'Añadir WARP';
	@override String get warpDescription => 'Aceleración gratuita con Cloudflare WARP';
	@override String get addingWarpMsg => 'Espera mientras registramos WARP.';
	@override String importedNamed({required Object name}) => 'Suscripción importada: ${name}';
	@override String get clipboardEmpty => 'El portapapeles está vacío; no hay nada que importar';
	@override String get deepLinkMissingUrl => 'El enlace no contiene una dirección de suscripción';
	@override String get successMsg => 'Perfil agregado';
	@override String get nameAutoHint => 'Se detecta automáticamente (opcional)';
}

// Path: profile.update
class Translations$profile$update$es extends Translations$profile$update$en {
	Translations$profile$update$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Actualizar';
	@override String get tooltip => 'Actualización del perfil';
	@override String get updateSubscriptions => 'Actualizar suscripciones';
	@override String get failureMsg => 'No se pudo actualizar el perfil';
	@override String get successMsg => 'Perfil actualizado con éxito';
	@override String namedFailureMsg({required Object name}) => 'No se pudo actualizar "${name}"';
	@override String namedSuccessMsg({required Object name}) => '"${name}" actualizado exitosamente';
}

// Path: profile.share
class Translations$profile$share$es extends Translations$profile$share$en {
	Translations$profile$share$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Compartir';
	@override String get exportToClipboardSuccess => 'Exportado al portapapeles';
	@override String get exportSubLinkToClipboard => 'Exportar enlace de suscripción al portapapeles';
	@override String get subLinkQrCode => 'Código QR del enlace de suscripción';
	@override String get exportConfigToClipboard => 'Exportar configuración al portapapeles';
	@override String get exportConfigToClipboardSuccess => 'Configuración copiada al portapapeles';
	@override String get shareLink => 'Compartir enlace';
	@override String get subscriptionLinkCopied => 'Enlace de suscripción copiado';
	@override String get configCopied => 'Configuración copiada';
	@override String get copyFailed => 'Error al copiar';
}

// Path: profile.edit
class Translations$profile$edit$es extends Translations$profile$edit$en {
	Translations$profile$edit$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Editar';
	@override String get selectActiveTxt => 'Seleccionar perfil activo';
}

// Path: profile.delete
class Translations$profile$delete$es extends Translations$profile$delete$en {
	Translations$profile$delete$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Borrar';
	@override String get confirmationMsg => '¿Eliminar perfil permanentemente?';
	@override String get successMsg => 'Perfil eliminado exitosamente';
	@override String get confirmTitle => 'Eliminar perfil';
	@override String namedConfirmMsg({required Object name}) => '¿Eliminar "${name}"? Esta acción no se puede deshacer.';
}

// Path: profile.save
class Translations$profile$save$es extends Translations$profile$save$en {
	Translations$profile$save$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Ahorrar';
	@override String get successMsg => 'Perfil guardado exitosamente';
	@override String get failureMsg => 'No se pudo guardar el perfil';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$es extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'Nombre';
	@override String get nameHint => 'Nombre de perfil';
	@override String get urlLabel => 'URL';
	@override String get urlHint => 'URL de configuración completa';
	@override String get emptyNameMsg => 'Se requiere el nombre';
	@override String get invalidUrlMsg => 'URL invalida';
	@override String get lastUpdate => 'Última actualización';
	@override String get updateInterval => 'Actualización automática';
	@override String get updateIntervalDialogTitle => 'Intervalo de actualización automática (en horas)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'Desactivado';
	@override String updateIntervalHours({required Object hours}) => '${hours} h';
	@override String updateIntervalDays({required Object days}) => '${days} d';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$es extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get add => 'Añadir';
	@override String get updateAll => 'Actualizar todo';
	@override String get sort => 'Ordenar';
	@override String get copyConfigSuccess => 'Configuración copiada';
	@override String get editConfig => 'Editar configuración';
}

// Path: profile.details
class Translations$profile$details$es extends Translations$profile$details$en {
	Translations$profile$details$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'Información básica';
	@override String get subscriptionStatus => 'Estado de la suscripción';
	@override String get options => 'Opciones';
	@override String get updateNow => 'Actualizar ahora';
	@override String get updateNowDescription => 'Obtener la configuración más reciente del servidor';
	@override String get expireDate => 'Fecha de vencimiento';
	@override String get unlimited => 'Ilimitado';
}

// Path: profile.overview
class Translations$profile$overview$es extends Translations$profile$overview$en {
	Translations$profile$overview$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'En uso';
	@override String remainingDays({required Object days}) => 'Quedan ${days} días';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$es extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'Por Defecto';
	@override String get name => 'Alfabéticamente';
	@override String get delay => 'Por retraso';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$es extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'Latencia: ${delay} ms';
	@override String get timeout => 'Tiempo de prueba de latencia agotado';
	@override String get testing => 'Latencia: probando...';
	@override String get untested => 'Latencia: sin probar';
	@override String stale({required Object delay}) => 'Latencia: ${delay} ms (resultado anterior)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$es extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get address => 'Dirección IP';
	@override String get country => 'País';
}

// Path: settings.general
class Translations$settings$general$es extends Translations$settings$general$en {
	Translations$settings$general$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'General';
	@override String get locale => 'Idioma';
	@override String get region => 'Región';
	@override String get regionMsg => 'Ayuda a configurar opciones predeterminadas para omitir direcciones nacionales';
	@override late final Translations$settings$general$regions$es regions = Translations$settings$general$regions$es._(_root);
	@override String get themeMode => 'Modo temático';
	@override late final Translations$settings$general$themeModes$es themeModes = Translations$settings$general$themeModes$es._(_root);
	@override String get enableAnalytics => 'Habilitar análisis';
	@override String get enableAnalyticsMsg => 'Dar permiso para recopilar análisis y enviar informes de fallos para mejorar la aplicación.';
	@override String get autoStart => 'Inicie en el arranque';
	@override String get silentStart => 'Inicio Silencioso';
	@override String get openWorkingDir => 'Abrir directorio de trabajo';
	@override String get ignoreBatteryOptimizations => 'Deshabilitar la optimización de la batería';
	@override String get ignoreBatteryOptimizationsMsg => 'Elimine las restricciones para un rendimiento VPN óptimo';
	@override String get dynamicNotification => 'Mostrar velocidad en la notificación';
	@override String get hapticFeedback => 'Respuesta háptica';
	@override String get autoIpCheck => 'Comprobar automáticamente la IP de conexión';
	@override String get autoStartPermission => 'Permitir inicio automático';
	@override String get autoStartPermissionMsg => 'Si se activa, la conexión se restablece automáticamente tras reiniciar el teléfono o actualizar la app';
	@override late final Translations$settings$general$autoStartPermissionStatus$es autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$es._(_root);
	@override late final Translations$settings$general$batteryOptimizationStatus$es batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$es._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$es extends Translations$settings$advanced$en {
	Translations$settings$advanced$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Avanzado';
	@override String get debugMode => 'Modo de depuración';
	@override String get debugModeMsg => 'Reinicie la aplicación para aplicar este cambio.';
	@override String get memoryLimit => 'Limite de memoria';
	@override String get memoryLimitMsg => 'Habilítelo si experimenta errores de falta de memoria o fallas frecuentes de la aplicación';
	@override String get resetTunnel => 'Restablecer perfil VPN';
	@override String get resetTunnelSuccess => 'Perfil VPN restablecido';
}

// Path: settings.network
class Translations$settings$network$es extends Translations$settings$network$en {
	Translations$settings$network$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'Proxy por aplicación';
	@override late final Translations$settings$network$perAppProxyModes$es perAppProxyModes = Translations$settings$network$perAppProxyModes$es._(_root);
	@override String get showSystemApps => 'Mostrar aplicaciones del sistema';
	@override String get hideSystemApps => 'Ocultar aplicaciones del sistema';
	@override String get clearSelection => 'Selección clara';
	@override String get perAppProxyLoadFailedMsg => 'Error al cargar la lista de aplicaciones';
	@override String get perAppProxyRetry => 'Reintentar';
	@override String get perAppProxyEmptyMsg => 'No se encontraron resultados';
	@override String get perAppProxyAndroidOnlyMsg => 'El modo de línea por aplicación solo es compatible con Android';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$es extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Activos de enrutamiento';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geosite';
	@override String version({required Object version}) => 'Versión ${version}';
	@override String get fileMissing => 'Archivo faltante';
	@override String get update => 'Actualizar';
	@override String get download => 'Descargar';
	@override String get failureMsg => 'No se pudo actualizar el activo';
	@override String get successMsg => 'Activo actualizado correctamente';
	@override String get addRecommended => 'Agregar activos recomendados';
	@override String get missingGeoAssetsMsg => 'Faltan los archivos de los recursos de enrutamiento seleccionados. Descárgalos o elige los existentes.';
}

// Path: settings.backup
class Translations$settings$backup$es extends Translations$settings$backup$en {
	Translations$settings$backup$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'Importar copia de seguridad';
	@override String get importConfirmMsg => 'Esto reemplaza tus suscripciones por las de la copia de seguridad y aplica sus ajustes. Antes se guarda una instantánea de los datos actuales, que se restaura automáticamente si la importación falla.';
	@override String importRemovesMsg({required Object count}) => '${count} suscripción(es) de este dispositivo no están en la copia de seguridad y se eliminarán.';
	@override String reportImported({required Object profiles, required Object settings}) => 'Se importaron ${profiles} suscripción(es) y ${settings} ajuste(s).';
	@override String reportDropped({required Object count}) => 'Se omitieron ${count} suscripción(es) de la copia de seguridad porque sus datos no eran válidos.';
	@override String reportSettingsSkipped({required Object count}) => 'Se omitieron ${count} ajuste(s); se conservan tus valores actuales.';
	@override String get reportWarpOff => 'La importación desactivó WARP. Vuelve a activarlo en este dispositivo.';
	@override String reportBackfill({required Object count}) => '${count} suscripción(es) se descargarán en segundo plano.';
	@override String get errInvalidFile => 'Este no es un archivo de copia de seguridad de ClashMiao válido.';
	@override String get errUnsupportedVersion => 'Este formato de copia de seguridad no es compatible.';
	@override String get errNewerSchema => 'Esta copia de seguridad fue creada por una versión más reciente de la aplicación. Actualiza la aplicación primero.';
	@override String get errNoUsableProfiles => 'Ninguna de las suscripciones de esta copia de seguridad se puede importar.';
	@override String get errSnapshotFailed => 'No se pudo guardar una instantánea de los datos actuales, así que no se cambió nada.';
	@override String get errUnresolvedPrevious => 'Una importación anterior se interrumpió y aún no se pudo deshacer. No se cambió nada. Reinicia la aplicación e inténtalo de nuevo.';
	@override String get errRolledBack => 'La importación falló. Se han restaurado tus datos anteriores.';
	@override String errNotRolledBack({required Object path}) => 'La importación falló y la restauración automática no terminó. Reinicia la aplicación para reintentarla. Hay una instantánea guardada en ${path}.';
	@override String get errFailed => 'La importación falló.';
	@override String get errBusy => 'Ya hay otra importación en curso. Espera a que termine.';
	@override String get recoveryFailedTitle => 'La restauración automática no terminó';
	@override String get recoveryFailedMsg => 'La última importación de la copia de seguridad se interrumpió y la aplicación no pudo devolver tus datos a su estado anterior. Es posible que algunos datos se hayan importado a medias. Reintenta la restauración automática ahora.';
	@override String get recoveryUnrecoverableTitle => 'No se pudo deshacer la importación interrumpida';
	@override String get recoveryUnrecoverableMsg => 'La última importación de la copia de seguridad se interrumpió, pero su instantánea falta o no se puede leer, así que no se puede deshacer. Revisa tus suscripciones y ajustes.';
	@override String get recoveryRetry => 'Reintentar';
	@override String get recoveryClose => 'Cerrar';
	@override String get recoveryRetried => 'Tus datos se restauraron al estado anterior a la importación interrumpida.';
	@override String get exportAction => 'Exportar copia de seguridad';
	@override String get importAction => 'Importar copia de seguridad';
	@override String get exportFailed => 'No se pudo exportar la copia de seguridad';
	@override String get shareText => 'Copia de seguridad de ClashMiao';
}

// Path: settings.groups
class Translations$settings$groups$es extends Translations$settings$groups$en {
	Translations$settings$groups$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get general => 'General';
	@override String get connection => 'Conexión';
	@override String get privacy => 'Privacidad';
}

// Path: tray.status
class Translations$tray$status$es extends Translations$tray$status$en {
	Translations$tray$status$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get connect => 'Conectar';
	@override String get connecting => 'Conectando';
	@override String get disconnect => 'Desconectado';
	@override String get disconnecting => 'Desconectando';
}

// Path: failure.clash
class Translations$failure$clash$es extends Translations$failure$clash$en {
	Translations$failure$clash$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error inesperado';
	@override String core({required Object reason}) => 'Error de choque ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$es extends Translations$failure$singbox$en {
	Translations$failure$singbox$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error de servicio inesperado';
	@override String get serviceNotRunning => 'El servicio no está funcionando';
	@override String get missingPrivilege => 'Privilegio perdido';
	@override String get missingPrivilegeMsg => 'El modo VPN requiere privilegios de administrador. Reinicie la aplicación como administrador o cambie el modo de servicio.';
	@override String get missingGeoAssets => 'Recursos geográficos faltantes';
	@override String get missingGeoAssetsMsg => 'Faltan recursos geográficos. considere cambiar el activo activo o descargar uno seleccionado en la configuración.';
	@override String get invalidConfigOptions => 'Opciones de configuración no válidas';
	@override String get invalidConfig => 'Configuración no válida';
	@override String get create => 'Error de creación del servicio';
	@override String get start => 'Error de inicio del servicio';
	@override String get coreLibraryMissing => 'Biblioteca del núcleo no instalada';
	@override String get startTimeout => 'Tiempo de inicio del servicio agotado';
	@override String get kernelUnresponsive => 'El núcleo no responde. Inténtalo de nuevo o reinicia la aplicación.';
	@override String get kernelExited => 'El núcleo se cerró inesperadamente';
}

// Path: failure.connectivity
class Translations$failure$connectivity$es extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Falla inesperada';
	@override String get missingVpnPermission => 'Permiso VPN faltante';
	@override String get missingNotificationPermission => 'Permiso de notificación faltante';
	@override String get core => 'Error central';
	@override String get networkUnavailable => 'Red no disponible';
	@override String get nativeUnresponsive => 'Se perdió el contacto con el servicio en segundo plano. Inténtalo de nuevo.';
}

// Path: failure.profiles
class Translations$failure$profiles$es extends Translations$failure$profiles$en {
	Translations$failure$profiles$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error Inesperado';
	@override String get notFound => 'Perfil no encontrado';
	@override String get invalidConfig => 'Configuracion Invalida';
	@override String get invalidUrl => 'URL Invalido';
	@override String get noActive => 'Sin perfil activo';
	@override String get readOnlyUpgrade => 'Actualiza la app antes de modificar las suscripciones';
}

// Path: failure.connection
class Translations$failure$connection$es extends Translations$failure$connection$en {
	Translations$failure$connection$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error de conexión inesperado';
	@override String get timeout => 'El tiempo de conexión expiro';
	@override String get badResponse => 'Mala respuesta';
	@override String get connectionError => 'Error de conexión';
	@override String get badCertificate => 'Certificado malo';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$es extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Error inesperado';
	@override String get notUpdate => 'Actualización no disponible';
	@override String get activeNotFound => 'Activo geográfico activo no encontrado';
}

// Path: config.serviceModes
class Translations$config$serviceModes$es extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Proxy';
	@override String get systemProxy => 'Sistema Proxy';
	@override String get tun => 'VPN';
	@override String get tunService => 'Servicio VPN';
}

// Path: config.section
class Translations$config$section$es extends Translations$config$section$en {
	Translations$config$section$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get route => 'Opciones de ruta';
	@override String get dns => 'Opciones de DNS';
	@override String get inbound => 'Opciones entrantes';
	@override String get mux => 'Multiplexer';
	@override String get outbound => 'Opciones de salida';
	@override String get tlsTricks => 'Trucos TLS';
	@override String get warp => 'WARP Options';
	@override String get misc => 'Opciones varias';
}

// Path: config.warpConsent
class Translations$config$warpConsent$es extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Consentimiento WARP de Cloudflare';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP es un proveedor de VPN WireGuard gratuito. Al habilitar esta opción, acepta los '),
		tos('Términos de servicio'),
		const TextSpan(text: ' y '),
		privacy('Política de privacidad'),
		const TextSpan(text: ' de Cloudflare WARP.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$es extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Desactivar';
	@override String get enable => 'Activar';
	@override String get prefer => 'Preferido';
	@override String get only => 'Exclusivo';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$es extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get inbound => 'Detour WARP through proxies';
	@override String get outbound => 'Detour proxies through WARP';
	@override String get proxyOverWarp => 'Desviar líneas a través de WARP';
	@override String get warpOverProxy => 'Desviar WARP a través de las líneas';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$es extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Solo línea';
	@override String get systemProxy => 'Línea del sistema';
	@override String get tun => 'VPN';
	@override String get tunService => 'Servicio VPN';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$es extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'Permiso Denegado';
	@override String get unexpectedError => 'Algo salió mal';
	@override String get torchSemanticLabel => 'Linterna';
	@override String get facingSemanticLabel => 'Frente a la cámara';
	@override String get permissionRequest => 'Permiso de cámara para escanear el código QR';
}

// Path: settings.general.regions
class Translations$settings$general$regions$es extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get ir => 'Irán (ir)';
	@override String get cn => 'China (CN)';
	@override String get ru => 'Rusia (ru)';
	@override String get af => 'Afganistán (af)';
	@override String get id => 'Indonesia (id)';
	@override String get other => 'Otro';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$es extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get system => 'Seguir el tema del sistema';
	@override String get dark => 'Modo Oscuro';
	@override String get light => 'Modo Claro';
	@override String get black => 'Modo Negro';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$es extends Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Activado';
	@override String get denied => 'Desactivado';
	@override String get pending => '…';
	@override String get unknown => 'Desconocido';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$es extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'Exento';
	@override String get notExempted => 'No exento';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$es extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get off => 'Todo';
	@override String get offMsg => 'Proxy en todas las aplicaciones';
	@override String get include => 'Proxy';
	@override String get includeMsg => 'Proxy solo en aplicaciones seleccionadas';
	@override String get exclude => 'Bypass';
	@override String get excludeMsg => 'No hacer proxy de aplicaciones seleccionadas';
}

/// The flat map containing all translations for locale <es>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Renicio',
			'general.toggle.enabled' => 'Activado',
			'general.toggle.disabled' => 'Desactivado',
			'general.state.disable' => 'Desactivar',
			'general.sort' => 'Clasificar',
			'general.sortBy' => 'Ordenar por',
			'general.addToClipboard' => 'Añadir al portapapeles',
			'general.notSet' => 'No establecido',
			'general.agree' => 'Aceptar',
			'general.decline' => 'Rechazar',
			'general.unknown' => 'Desconocido',
			'general.hidden' => 'Oculto',
			'general.timeout' => 'Se acabó el tiempo',
			'general.showMore' => 'Mostrar más',
			'general.showLess' => 'Muestra menos',
			'general.grantPermission' => 'Conceder permiso',
			'general.clipboardExportSuccessMsg' => 'Copiado al portapapeles',
			'general.openAppSettings' => 'Abrir ajustes de la app',
			'general.underDevelopment' => 'En desarrollo',
			'general.confirm' => 'Confirmar',
			'general.close' => 'Cerrar',
			'general.cancel' => 'Cancelar',
			'general.clipboardEmpty' => 'El portapapeles está vacío',
			'general.clipboardReadFailed' => 'No se pudo leer el portapapeles',
			'general.moreOptions' => 'Más opciones',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'al continuar, aceptas '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => 'Comenzar',
			'home.pageTitle' => 'Hogar',
			'home.emptyProfilesMsg' => 'Comience agregando un perfil de suscripción',
			'home.noActiveProfileMsg' => 'Elige un perfil',
			'home.routingMode.global' => 'Proxy global',
			'home.routingMode.smart' => 'Enrutamiento inteligente',
			'home.failedToSwitchMode' => ({required Object error}) => 'Error al cambiar de modo: ${error}',
			'home.connectionFailedTitle' => 'Error de conexión',
			'home.coreMissingTitle' => 'No se encontró la biblioteca del núcleo',
			'home.coreMissingMsg' => 'La aplicación no pudo cargar su núcleo de red. La conexión no está disponible. Reinstala la aplicación o asegúrate de que el archivo de la biblioteca del núcleo esté junto al ejecutable.',
			'home.degradedTitle' => 'Conectado, pero sin acceso a Internet',
			'home.degradedMsg' => 'El túnel está activo pero el tráfico no pasa. Puede que el nodo esté caído: prueba otro nodo o desconéctate.',
			'home.degradedRetry' => 'Comprobar de nuevo',
			'home.egressIp.label' => 'IP de salida',
			'home.egressIp.notConnected' => 'Conéctate para ver la IP de salida',
			'home.egressIp.tapToCheck' => 'Toca para comprobar la IP de salida',
			'home.egressIp.checking' => 'Comprobando…',
			'home.egressIp.failedRetry' => 'Error al comprobar, toca para reintentar',
			'home.emptyProfilesHint' => 'Toca el botón de abajo para empezar',
			'home.noActiveProfileTitle' => 'No hay ningún perfil seleccionado',
			'profile.overviewPageTitle' => 'Perfiles',
			'profile.detailsPageTitle' => 'Perfil',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Nombre del perfil activo: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'Ver todos los perfiles',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Seleccione "${name}" como perfil activo.',
			'profile.subscription.traffic' => 'Tráfico',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => 'Actualizado ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '${duration} días restantes',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed} de ${total} Tráfico Consumido',
			'profile.subscription.expired' => 'Caducado',
			'profile.subscription.noTraffic' => 'Fuera de cuota',
			'profile.subscription.upload' => 'Subida',
			'profile.subscription.download' => 'Descarga',
			'profile.subscription.total' => 'Tráfico total',
			'profile.subscription.expireDate' => 'Fecha de vencimiento',
			'profile.sortBy.lastUpdate' => 'Recientemente actualizado',
			'profile.sortBy.name' => 'Alfabéticamente',
			'profile.add.buttonText' => 'Nuevo perfil',
			'profile.add.shortBtnTxt' => 'Nuevo perfil',
			'profile.add.fromClipboard' => 'Agregar desde el portapapeles',
			'profile.add.scanQr' => 'Escanear código QR',
			'profile.add.qrScanner.permissionDeniedError' => 'Permiso Denegado',
			'profile.add.qrScanner.unexpectedError' => 'Algo salió mal',
			'profile.add.qrScanner.torchSemanticLabel' => 'Linterna',
			'profile.add.qrScanner.facingSemanticLabel' => 'Frente a la cámara',
			'profile.add.qrScanner.permissionRequest' => 'Permiso de cámara para escanear el código QR',
			'profile.add.manually' => 'Entrada manual',
			'profile.add.addingProfileMsg' => 'Agregar perfil',
			'profile.add.failureMsg' => 'No se pudo agregar el perfil',
			'profile.add.modalSubtitle' => 'Elige cómo añadir el archivo de configuración',
			'profile.add.manuallyDescription' => 'Introduce la configuración del servidor manualmente',
			'profile.add.addWarp' => 'Añadir WARP',
			'profile.add.warpDescription' => 'Aceleración gratuita con Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'Espera mientras registramos WARP.',
			'profile.add.importedNamed' => ({required Object name}) => 'Suscripción importada: ${name}',
			'profile.add.clipboardEmpty' => 'El portapapeles está vacío; no hay nada que importar',
			'profile.add.deepLinkMissingUrl' => 'El enlace no contiene una dirección de suscripción',
			'profile.add.successMsg' => 'Perfil agregado',
			'profile.add.nameAutoHint' => 'Se detecta automáticamente (opcional)',
			'profile.update.buttonTxt' => 'Actualizar',
			'profile.update.tooltip' => 'Actualización del perfil',
			'profile.update.updateSubscriptions' => 'Actualizar suscripciones',
			'profile.update.failureMsg' => 'No se pudo actualizar el perfil',
			'profile.update.successMsg' => 'Perfil actualizado con éxito',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'No se pudo actualizar "${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" actualizado exitosamente',
			'profile.share.buttonText' => 'Compartir',
			'profile.share.exportToClipboardSuccess' => 'Exportado al portapapeles',
			'profile.share.exportSubLinkToClipboard' => 'Exportar enlace de suscripción al portapapeles',
			'profile.share.subLinkQrCode' => 'Código QR del enlace de suscripción',
			'profile.share.exportConfigToClipboard' => 'Exportar configuración al portapapeles',
			'profile.share.exportConfigToClipboardSuccess' => 'Configuración copiada al portapapeles',
			'profile.share.shareLink' => 'Compartir enlace',
			'profile.share.subscriptionLinkCopied' => 'Enlace de suscripción copiado',
			'profile.share.configCopied' => 'Configuración copiada',
			'profile.share.copyFailed' => 'Error al copiar',
			'profile.edit.buttonTxt' => 'Editar',
			'profile.edit.selectActiveTxt' => 'Seleccionar perfil activo',
			'profile.delete.buttonTxt' => 'Borrar',
			'profile.delete.confirmationMsg' => '¿Eliminar perfil permanentemente?',
			'profile.delete.successMsg' => 'Perfil eliminado exitosamente',
			'profile.delete.confirmTitle' => 'Eliminar perfil',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => '¿Eliminar "${name}"? Esta acción no se puede deshacer.',
			'profile.save.buttonText' => 'Ahorrar',
			'profile.save.successMsg' => 'Perfil guardado exitosamente',
			'profile.save.failureMsg' => 'No se pudo guardar el perfil',
			'profile.detailsForm.nameLabel' => 'Nombre',
			'profile.detailsForm.nameHint' => 'Nombre de perfil',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'URL de configuración completa',
			'profile.detailsForm.emptyNameMsg' => 'Se requiere el nombre',
			'profile.detailsForm.invalidUrlMsg' => 'URL invalida',
			'profile.detailsForm.lastUpdate' => 'Última actualización',
			'profile.detailsForm.updateInterval' => 'Actualización automática',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Intervalo de actualización automática (en horas)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Desactivado',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} h',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} d',
			'profile.actionButtons.add' => 'Añadir',
			'profile.actionButtons.updateAll' => 'Actualizar todo',
			'profile.actionButtons.sort' => 'Ordenar',
			'profile.actionButtons.copyConfigSuccess' => 'Configuración copiada',
			'profile.actionButtons.editConfig' => 'Editar configuración',
			'profile.details.basicInfo' => 'Información básica',
			'profile.details.subscriptionStatus' => 'Estado de la suscripción',
			'profile.details.options' => 'Opciones',
			'profile.details.updateNow' => 'Actualizar ahora',
			'profile.details.updateNowDescription' => 'Obtener la configuración más reciente del servidor',
			'profile.details.expireDate' => 'Fecha de vencimiento',
			'profile.details.unlimited' => 'Ilimitado',
			'profile.overview.currentlyUsing' => 'En uso',
			'profile.overview.remainingDays' => ({required Object days}) => 'Quedan ${days} días',
			'profile.remoteProfile' => 'Perfil remoto',
			'profile.defaultLocalName' => 'Importación local',
			'profile.defaultDeepLinkName' => 'Importado desde enlace',
			'profile.switchFailedMsg' => 'No se pudo cambiar de perfil',
			'proxies.pageTitle' => 'Proxies',
			'proxies.emptyProxiesMsg' => 'No proxies disponibles',
			'proxies.delayTestTooltip' => 'Prueba de Restraso',
			'proxies.sortTooltip' => 'Ordenar Proxies',
			'proxies.sortOptions.unsorted' => 'Por Defecto',
			'proxies.sortOptions.name' => 'Alfabéticamente',
			'proxies.sortOptions.delay' => 'Por retraso',
			'proxies.checkIp' => 'Comprobar IP',
			'proxies.unknownIp' => 'IP desconocida',
			'proxies.autoSelect' => 'Selección automática',
			'proxies.autoSelectDescription' => 'Conectar automáticamente al nodo más rápido',
			'proxies.sortModalTitle' => 'Elige el método de ordenación',
			'proxies.activeProxySemanticLabel' => 'Línea activa',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'Latencia: ${delay} ms',
			'proxies.delaySemantics.timeout' => 'Tiempo de prueba de latencia agotado',
			'proxies.delaySemantics.testing' => 'Latencia: probando...',
			'proxies.delaySemantics.untested' => 'Latencia: sin probar',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'Latencia: ${delay} ms (resultado anterior)',
			'proxies.ipInfoSemantics.address' => 'Dirección IP',
			'proxies.ipInfoSemantics.country' => 'País',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Probando latencia de: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'Cambiado a ${name}',
			'proxies.switchFailed' => 'No se pudo cambiar de servidor. Inténtalo de nuevo.',
			'proxies.testFailed' => 'La prueba de latencia falló. Inténtalo de nuevo.',
			'proxies.groupsLoading' => 'La lista de servidores aún se está cargando. Inténtalo en un momento.',
			'proxies.connectBeforeSwitch' => 'Conéctate antes de cambiar de línea',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'Prueba de latencia iniciada para ${count} líneas',
			'proxies.delayTestBtn' => 'Latencia',
			'proxies.delayTimeout' => 'Agotado',
			'proxies.connectBeforeTest' => 'Conéctate primero para probar la latencia',
			'proxies.lineCount' => ({required Object count}) => '${count} líneas',
			'proxies.manualSelect' => 'Selección manual',
			'proxies.autoTest' => 'Prueba automática',
			'logs.pageTitle' => 'Registros',
			'logs.filterHint' => 'Filtrar',
			'logs.allLevelsFilter' => 'Todo',
			'logs.shareCoreLogs' => 'Compartir registros principales',
			'logs.shareAppLogs' => 'Compartir registros de aplicaciones',
			'logs.pauseTooltip' => 'Pausa',
			'logs.resumeTooltip' => 'reanudar',
			'logs.clearTooltip' => 'Claro',
			'logs.logsCleared' => 'Registros borrados',
			'logs.logsCopied' => 'Registros copiados',
			'logs.logsUnderDevelopment' => 'La función de registros está en desarrollo',
			'logs.noLogsWhenDisconnected' => 'Sin conexión, no hay registros',
			'logs.loadFailed' => 'No se pudieron cargar los registros',
			'logs.empty' => 'Aún no hay registros',
			'logs.clearFailed' => 'No se pudieron borrar los registros',
			'settings.pageTitle' => 'Ajustes',
			'settings.requiresRestartMsg' => 'Para que esto surta efecto, reinicie la aplicación.',
			'settings.experimental' => 'Experimental',
			'settings.experimentalMsg' => 'Las funciones con el indicador Experimental aún están en desarrollo y pueden causar problemas.',
			'settings.general.sectionTitle' => 'General',
			'settings.general.locale' => 'Idioma',
			'settings.general.region' => 'Región',
			'settings.general.regionMsg' => 'Ayuda a configurar opciones predeterminadas para omitir direcciones nacionales',
			'settings.general.regions.ir' => 'Irán (ir)',
			'settings.general.regions.cn' => 'China (CN)',
			'settings.general.regions.ru' => 'Rusia (ru)',
			'settings.general.regions.af' => 'Afganistán (af)',
			'settings.general.regions.id' => 'Indonesia (id)',
			'settings.general.regions.other' => 'Otro',
			'settings.general.themeMode' => 'Modo temático',
			'settings.general.themeModes.system' => 'Seguir el tema del sistema',
			'settings.general.themeModes.dark' => 'Modo Oscuro',
			'settings.general.themeModes.light' => 'Modo Claro',
			'settings.general.themeModes.black' => 'Modo Negro',
			'settings.general.enableAnalytics' => 'Habilitar análisis',
			'settings.general.enableAnalyticsMsg' => 'Dar permiso para recopilar análisis y enviar informes de fallos para mejorar la aplicación.',
			'settings.general.autoStart' => 'Inicie en el arranque',
			'settings.general.silentStart' => 'Inicio Silencioso',
			'settings.general.openWorkingDir' => 'Abrir directorio de trabajo',
			'settings.general.ignoreBatteryOptimizations' => 'Deshabilitar la optimización de la batería',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Elimine las restricciones para un rendimiento VPN óptimo',
			'settings.general.dynamicNotification' => 'Mostrar velocidad en la notificación',
			'settings.general.hapticFeedback' => 'Respuesta háptica',
			'settings.general.autoIpCheck' => 'Comprobar automáticamente la IP de conexión',
			'settings.general.autoStartPermission' => 'Permitir inicio automático',
			'settings.general.autoStartPermissionMsg' => 'Si se activa, la conexión se restablece automáticamente tras reiniciar el teléfono o actualizar la app',
			'settings.general.autoStartPermissionStatus.allowed' => 'Activado',
			'settings.general.autoStartPermissionStatus.denied' => 'Desactivado',
			'settings.general.autoStartPermissionStatus.pending' => '…',
			'settings.general.autoStartPermissionStatus.unknown' => 'Desconocido',
			'settings.general.batteryOptimizationStatus.exempted' => 'Exento',
			'settings.general.batteryOptimizationStatus.notExempted' => 'No exento',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Avanzado',
			'settings.advanced.debugMode' => 'Modo de depuración',
			'settings.advanced.debugModeMsg' => 'Reinicie la aplicación para aplicar este cambio.',
			'settings.advanced.memoryLimit' => 'Limite de memoria',
			'settings.advanced.memoryLimitMsg' => 'Habilítelo si experimenta errores de falta de memoria o fallas frecuentes de la aplicación',
			'settings.advanced.resetTunnel' => 'Restablecer perfil VPN',
			'settings.advanced.resetTunnelSuccess' => 'Perfil VPN restablecido',
			'settings.network.perAppProxyPageTitle' => 'Proxy por aplicación',
			'settings.network.perAppProxyModes.off' => 'Todo',
			'settings.network.perAppProxyModes.offMsg' => 'Proxy en todas las aplicaciones',
			'settings.network.perAppProxyModes.include' => 'Proxy',
			'settings.network.perAppProxyModes.includeMsg' => 'Proxy solo en aplicaciones seleccionadas',
			'settings.network.perAppProxyModes.exclude' => 'Bypass',
			'settings.network.perAppProxyModes.excludeMsg' => 'No hacer proxy de aplicaciones seleccionadas',
			'settings.network.showSystemApps' => 'Mostrar aplicaciones del sistema',
			'settings.network.hideSystemApps' => 'Ocultar aplicaciones del sistema',
			'settings.network.clearSelection' => 'Selección clara',
			'settings.network.perAppProxyLoadFailedMsg' => 'Error al cargar la lista de aplicaciones',
			'settings.network.perAppProxyRetry' => 'Reintentar',
			'settings.network.perAppProxyEmptyMsg' => 'No se encontraron resultados',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'El modo de línea por aplicación solo es compatible con Android',
			'settings.geoAssets.pageTitle' => 'Activos de enrutamiento',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geosite',
			'settings.geoAssets.version' => ({required Object version}) => 'Versión ${version}',
			'settings.geoAssets.fileMissing' => 'Archivo faltante',
			'settings.geoAssets.update' => 'Actualizar',
			'settings.geoAssets.download' => 'Descargar',
			'settings.geoAssets.failureMsg' => 'No se pudo actualizar el activo',
			'settings.geoAssets.successMsg' => 'Activo actualizado correctamente',
			'settings.geoAssets.addRecommended' => 'Agregar activos recomendados',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Faltan los archivos de los recursos de enrutamiento seleccionados. Descárgalos o elige los existentes.',
			'settings.exportOptions' => 'Copiar opciones anónimas al portapapeles',
			'settings.exportAllOptions' => 'Copiar todas las opciones al portapapeles',
			'settings.importOptions' => 'Importar opciones desde el portapapeles',
			'settings.importOptionsMsg' => 'Esto sobrescribirá todas las opciones de configuración con los valores proporcionados. ¿Continuar?',
			'settings.backup.importConfirmTitle' => 'Importar copia de seguridad',
			'settings.backup.importConfirmMsg' => 'Esto reemplaza tus suscripciones por las de la copia de seguridad y aplica sus ajustes. Antes se guarda una instantánea de los datos actuales, que se restaura automáticamente si la importación falla.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '${count} suscripción(es) de este dispositivo no están en la copia de seguridad y se eliminarán.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => 'Se importaron ${profiles} suscripción(es) y ${settings} ajuste(s).',
			'settings.backup.reportDropped' => ({required Object count}) => 'Se omitieron ${count} suscripción(es) de la copia de seguridad porque sus datos no eran válidos.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => 'Se omitieron ${count} ajuste(s); se conservan tus valores actuales.',
			'settings.backup.reportWarpOff' => 'La importación desactivó WARP. Vuelve a activarlo en este dispositivo.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} suscripción(es) se descargarán en segundo plano.',
			'settings.backup.errInvalidFile' => 'Este no es un archivo de copia de seguridad de ClashMiao válido.',
			'settings.backup.errUnsupportedVersion' => 'Este formato de copia de seguridad no es compatible.',
			'settings.backup.errNewerSchema' => 'Esta copia de seguridad fue creada por una versión más reciente de la aplicación. Actualiza la aplicación primero.',
			'settings.backup.errNoUsableProfiles' => 'Ninguna de las suscripciones de esta copia de seguridad se puede importar.',
			'settings.backup.errSnapshotFailed' => 'No se pudo guardar una instantánea de los datos actuales, así que no se cambió nada.',
			'settings.backup.errUnresolvedPrevious' => 'Una importación anterior se interrumpió y aún no se pudo deshacer. No se cambió nada. Reinicia la aplicación e inténtalo de nuevo.',
			'settings.backup.errRolledBack' => 'La importación falló. Se han restaurado tus datos anteriores.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'La importación falló y la restauración automática no terminó. Reinicia la aplicación para reintentarla. Hay una instantánea guardada en ${path}.',
			'settings.backup.errFailed' => 'La importación falló.',
			'settings.backup.errBusy' => 'Ya hay otra importación en curso. Espera a que termine.',
			'settings.backup.recoveryFailedTitle' => 'La restauración automática no terminó',
			'settings.backup.recoveryFailedMsg' => 'La última importación de la copia de seguridad se interrumpió y la aplicación no pudo devolver tus datos a su estado anterior. Es posible que algunos datos se hayan importado a medias. Reintenta la restauración automática ahora.',
			'settings.backup.recoveryUnrecoverableTitle' => 'No se pudo deshacer la importación interrumpida',
			'settings.backup.recoveryUnrecoverableMsg' => 'La última importación de la copia de seguridad se interrumpió, pero su instantánea falta o no se puede leer, así que no se puede deshacer. Revisa tus suscripciones y ajustes.',
			'settings.backup.recoveryRetry' => 'Reintentar',
			'settings.backup.recoveryClose' => 'Cerrar',
			'settings.backup.recoveryRetried' => 'Tus datos se restauraron al estado anterior a la importación interrumpida.',
			'settings.backup.exportAction' => 'Exportar copia de seguridad',
			'settings.backup.importAction' => 'Importar copia de seguridad',
			'settings.backup.exportFailed' => 'No se pudo exportar la copia de seguridad',
			'settings.backup.shareText' => 'Copia de seguridad de ClashMiao',
			'settings.systemProxyEnabled' => 'Proxy del sistema activado',
			'settings.systemProxyDisabled' => 'Proxy del sistema desactivado (reconecta para aplicar)',
			'settings.adminPrivilegesRequired' => 'Se requieren privilegios de administrador en macOS',
			'settings.portChangeNotice' => 'Los cambios de puerto requieren reconectar para aplicarse',
			'settings.groups.general' => 'General',
			'settings.groups.connection' => 'Conexión',
			'settings.groups.privacy' => 'Privacidad',
			'settings.importOptionsInvalid' => 'El portapapeles no contiene un JSON de ajustes válido',
			'settings.importOptionsNothing' => 'No se encontraron ajustes importables',
			'settings.importOptionsDone' => ({required Object count}) => 'Se importaron ${count} ajustes',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => 'Se importaron ${applied} ajustes; se omitieron ${skipped} por no ser válidos',
			'about.pageTitle' => 'Acerca de',
			'about.version' => 'Versión',
			'about.sourceCode' => 'Código fuente',
			'about.telegramChannel' => 'Canal de telegramas',
			'about.checkForUpdate' => 'Buscar actualizaciones',
			'about.privacyPolicy' => 'Política de privacidad',
			'about.termsAndConditions' => 'Términos y condiciones',
			'about.appDescription' => 'Un cliente proxy multiplataforma basado en el núcleo sing-box',
			'about.openSourceLicenses' => 'Licencias de código abierto',
			'appUpdate.notAvailableMsg' => 'Ya estas usando la última versión.',
			'appUpdate.dialogTitle' => 'Actualización disponible',
			'appUpdate.updateMsg' => 'Hay disponible una nueva versión de ${_root.general.appTitle}. ¿Te gustaría actualizar ahora?',
			'appUpdate.currentVersionLbl' => 'Versión actual',
			'appUpdate.newVersionLbl' => 'Nueva versión',
			'appUpdate.updateNowBtnTxt' => 'Actualizar ahora',
			'appUpdate.laterBtnTxt' => 'Más tarde',
			'appUpdate.ignoreBtnTxt' => 'Ignorar',
			'appUpdate.checkFailedMsg' => 'No se pudo buscar actualizaciones. Revisa tu red e inténtalo de nuevo.',
			'tray.dashboard' => 'Panel',
			'tray.quit' => 'Abandonar',
			'tray.open' => 'Abierto',
			'tray.status.connect' => 'Conectar',
			'tray.status.connecting' => 'Conectando',
			'tray.status.disconnect' => 'Desconectado',
			'tray.status.disconnecting' => 'Desconectando',
			'tray.hide' => 'Ocultar',
			'tray.proxyModeMenu' => 'Modo de proxy',
			'failure.unexpected' => 'Error inesperado',
			'failure.clash.unexpected' => 'Error inesperado',
			'failure.clash.core' => ({required Object reason}) => 'Error de choque ${reason}',
			'failure.singbox.unexpected' => 'Error de servicio inesperado',
			'failure.singbox.serviceNotRunning' => 'El servicio no está funcionando',
			'failure.singbox.missingPrivilege' => 'Privilegio perdido',
			'failure.singbox.missingPrivilegeMsg' => 'El modo VPN requiere privilegios de administrador. Reinicie la aplicación como administrador o cambie el modo de servicio.',
			'failure.singbox.missingGeoAssets' => 'Recursos geográficos faltantes',
			'failure.singbox.missingGeoAssetsMsg' => 'Faltan recursos geográficos. considere cambiar el activo activo o descargar uno seleccionado en la configuración.',
			'failure.singbox.invalidConfigOptions' => 'Opciones de configuración no válidas',
			'failure.singbox.invalidConfig' => 'Configuración no válida',
			'failure.singbox.create' => 'Error de creación del servicio',
			'failure.singbox.start' => 'Error de inicio del servicio',
			'failure.singbox.coreLibraryMissing' => 'Biblioteca del núcleo no instalada',
			'failure.singbox.startTimeout' => 'Tiempo de inicio del servicio agotado',
			'failure.singbox.kernelUnresponsive' => 'El núcleo no responde. Inténtalo de nuevo o reinicia la aplicación.',
			'failure.singbox.kernelExited' => 'El núcleo se cerró inesperadamente',
			'failure.connectivity.unexpected' => 'Falla inesperada',
			'failure.connectivity.missingVpnPermission' => 'Permiso VPN faltante',
			'failure.connectivity.missingNotificationPermission' => 'Permiso de notificación faltante',
			'failure.connectivity.core' => 'Error central',
			'failure.connectivity.networkUnavailable' => 'Red no disponible',
			'failure.connectivity.nativeUnresponsive' => 'Se perdió el contacto con el servicio en segundo plano. Inténtalo de nuevo.',
			'failure.profiles.unexpected' => 'Error Inesperado',
			'failure.profiles.notFound' => 'Perfil no encontrado',
			'failure.profiles.invalidConfig' => 'Configuracion Invalida',
			'failure.profiles.invalidUrl' => 'URL Invalido',
			'failure.profiles.noActive' => 'Sin perfil activo',
			'failure.profiles.readOnlyUpgrade' => 'Actualiza la app antes de modificar las suscripciones',
			'failure.connection.unexpected' => 'Error de conexión inesperado',
			'failure.connection.timeout' => 'El tiempo de conexión expiro',
			'failure.connection.badResponse' => 'Mala respuesta',
			'failure.connection.connectionError' => 'Error de conexión',
			'failure.connection.badCertificate' => 'Certificado malo',
			'failure.geoAssets.unexpected' => 'Error inesperado',
			'failure.geoAssets.notUpdate' => 'Actualización no disponible',
			'failure.geoAssets.activeNotFound' => 'Activo geográfico activo no encontrado',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Toque para conectarse',
			'connection.connecting' => 'Conectando',
			'connection.disconnecting' => 'Desconectando',
			'connection.connected' => 'Conectado',
			'connection.experimentalNotice' => 'Funciones experimentales en uso',
			'connection.experimentalNoticeMsg' => 'Ha habilitado algunas funciones experimentales que podrían afectar la calidad de la conexión y provocar errores inesperados. Siempre puede cambiar o restablecer estas opciones desde la página de opciones de configuración.',
			'connection.disableExperimentalNotice' => 'No volver a mostrar',
			'connection.reconnect' => 'Reconectar',
			'connection.connectAnyWay' => 'Conectar de todos modos',
			'connection.reconnectMsg' => 'Reconectando para aplicar los cambios...',
			'connection.staleSystemProxyCleaned' => 'Se limpiaron los ajustes de proxy del sistema que quedaron de una salida anómala',
			'config.resetBtn' => 'Restablecer opciones',
			'config.serviceMode' => 'Modo de servicio',
			'config.serviceModes.proxy' => 'Proxy',
			'config.serviceModes.systemProxy' => 'Sistema Proxy',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'Servicio VPN',
			'config.section.route' => 'Opciones de ruta',
			'config.section.dns' => 'Opciones de DNS',
			'config.section.inbound' => 'Opciones entrantes',
			'config.section.mux' => 'Multiplexer',
			'config.section.outbound' => 'Opciones de salida',
			'config.section.tlsTricks' => 'Trucos TLS',
			'config.section.warp' => 'WARP Options',
			'config.section.misc' => 'Opciones varias',
			'config.warpConsent.title' => 'Consentimiento WARP de Cloudflare',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP es un proveedor de VPN WireGuard gratuito. Al habilitar esta opción, acepta los '), tos('Términos de servicio'), const TextSpan(text: ' y '), privacy('Política de privacidad'), const TextSpan(text: ' de Cloudflare WARP.'), ]), 
			'config.pageTitle' => 'Opciones de configuración',
			'config.logLevel' => 'Registro del Nivel',
			'config.resolveDestination' => 'Resolver Destino',
			'config.ipv6Mode' => 'Ruta IPv6',
			'config.ipv6Modes.disable' => 'Desactivar',
			'config.ipv6Modes.enable' => 'Activar',
			'config.ipv6Modes.prefer' => 'Preferido',
			'config.ipv6Modes.only' => 'Exclusivo',
			'config.remoteDnsAddress' => 'DNS Remoto',
			'config.remoteDnsDomainStrategy' => 'Estrategia de dominio DNS remoto',
			'config.directDnsAddress' => 'DNS Directo',
			'config.directDnsDomainStrategy' => 'Estrategia de dominio DNS directo',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'No aplicado: el enrutamiento IPv6 está desactivado pero "${field}" es solo IPv6, así que no se podría resolver ningún dominio. Activa primero el enrutamiento IPv6 o elige otra estrategia.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'No aplicado: el enrutamiento IPv6 es solo IPv6 pero "${field}" es solo IPv4, así que no se podría resolver ningún dominio. Ajusta primero uno de los dos.',
			'config.dnsStrategyReset' => ({required Object field}) => '"${field}" entraba en conflicto con el enrutamiento IPv6 (no se podría resolver ningún dominio) y se restableció a automático.',
			'config.mixedPort' => 'Puerto Mixto',
			'config.localDnsPort' => 'Puerto DNS local',
			'config.allowConnectionFromLan' => 'Permitir conexión desde LAN',
			'config.tunImplementation' => 'Implementación de TUN',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'URL de prueba de conexión',
			'config.urlTestInterval' => 'URL Prueba de Intervalo',
			'config.enableClashApi' => 'Habilitar API de choque',
			'config.clashApiPort' => 'Puerto API de choque',
			'config.enableTun' => 'Habilitar sintonización',
			'config.setSystemProxy' => 'stablecer proxy del sistema',
			'config.enableDnsRouting' => 'Habilitar enrutamiento DNS',
			'config.enableFakeDns' => 'Habilitar DNS falso',
			'config.bypassLan' => 'Omitir LAN',
			'config.strictRoute' => 'Ruta estricta',
			'config.enableTlsFragment' => 'Habilitar fragmento TLS',
			'config.tlsFragmentSize' => 'Tamaño del fragmento TLS',
			'config.tlsFragmentSleep' => 'Sueño de fragmento TLS',
			'config.enableTlsMixedSniCase' => 'Habilitar caso SNI mixto TLS',
			'config.enableTlsPadding' => 'Habilitar el relleno TLS',
			'config.tlsPaddingSize' => 'Relleno TLS',
			'config.enableMux' => 'Enable Mux',
			'config.muxProtocol' => 'Mux Protocol',
			'config.muxMaxStreams' => 'Max Concurrent Streams',
			'config.enableWarp' => 'Enable WARP',
			'config.setUpWarp' => 'Configurar WARP',
			'config.warpNotConfigured' => 'Sin configurar',
			'config.warpDetourMode' => 'Detour Mode',
			'config.warpDetourModes.inbound' => 'Detour WARP through proxies',
			'config.warpDetourModes.outbound' => 'Detour proxies through WARP',
			'config.warpDetourModes.proxyOverWarp' => 'Desviar líneas a través de WARP',
			'config.warpDetourModes.warpOverProxy' => 'Desviar WARP a través de las líneas',
			'config.warpLicenseKey' => 'License Key',
			'config.warpCleanIp' => 'Clean IP',
			'config.warpPort' => 'Port',
			'config.warpNoise' => 'Noise',
			'config.quickSettings' => 'Ajustes rápidos',
			'config.quickSettingsSubtitle' => 'Personaliza tu experiencia de conexión',
			'config.setupWarp' => 'Configurar WARP',
			'config.allOptions' => 'Todas las opciones de configuración',
			'config.allAdvancedOptions' => 'Todas las opciones avanzadas',
			'config.shortServiceModes.proxy' => 'Solo línea',
			'config.shortServiceModes.systemProxy' => 'Línea del sistema',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'Servicio VPN',
			'config.generateWarpConfig' => 'Generar configuración WARP',
			'config.missingWarpConfig' => 'Falta la configuración WARP',
			'config.warpConfigGenerated' => 'Configuración WARP generada',
			'config.blockAds' => 'Bloquear anuncios',
			'config.tproxyPort' => 'Puerto de línea transparente',
			'config.warpNoiseSize' => 'Tamaño del ruido',
			'config.warpNoiseMode' => 'Modo de ruido',
			'config.warpNoiseDelay' => 'Retardo de ruido',
			'config.desktopProxyScopeNotice' => 'En el escritorio, solo las aplicaciones que respetan el proxy del sistema pasan por el túnel. El software que lo ignora (algunos juegos, herramientas de línea de comandos, aplicaciones con su propia configuración de proxy) se conecta directamente y expone tu IP real.',
			'config.serviceModeIosVpnOnly' => 'iOS solo admite el modo VPN',
			'config.warpGenerating' => 'Generando la configuración de WARP…',
			'config.warpConfigFailed' => 'No se pudo generar la configuración de WARP. Inténtalo más tarde.',
			'config.portRangeError' => 'El puerto debe estar entre 1024 y 65535',
			'config.dnsEmptyError' => 'La dirección DNS no puede estar vacía',
			'config.rangeFormatError' => 'Introduce un número o un rango, p. ej. 10-30',
			'config.urlSchemeError' => 'La URL debe empezar por http:// o https://',
			'config.manageRuleAssets' => 'Gestionar conjuntos de reglas',
			'stats.traffic' => 'Tráfico',
			'stats.trafficLive' => 'Tráfico en vivo',
			'stats.trafficTotal' => 'Tráfico total',
			'stats.trafficUsage' => 'Uso de tráfico',
			'stats.liveSpeed' => 'Velocidad en vivo',
			'stats.uplink' => 'Subida',
			'stats.downlink' => 'Bajada',
			'stats.connection' => 'Conexión',
			'stats.speed' => 'Velocidad',
			'stats.totalTransferred' => 'Total transferido',
			'stats.sessionTraffic' => 'Tráfico de esta sesión',
			'stats.downloadSpeed' => 'Velocidad de descarga',
			_ => null,
		};
	}
}
