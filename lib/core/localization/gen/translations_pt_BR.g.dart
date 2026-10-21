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
class TranslationsPtBr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsPtBr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ptBr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <pt-BR>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsPtBr _root = this; // ignore: unused_field

	@override 
	TranslationsPtBr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsPtBr(meta: meta ?? this.$meta);

	// Translations
	@override late final Translations$general$pt_BR general = Translations$general$pt_BR._(_root);
	@override late final Translations$intro$pt_BR intro = Translations$intro$pt_BR._(_root);
	@override late final Translations$home$pt_BR home = Translations$home$pt_BR._(_root);
	@override late final Translations$stats$pt_BR stats = Translations$stats$pt_BR._(_root);
	@override late final Translations$profile$pt_BR profile = Translations$profile$pt_BR._(_root);
	@override late final Translations$proxies$pt_BR proxies = Translations$proxies$pt_BR._(_root);
	@override late final Translations$logs$pt_BR logs = Translations$logs$pt_BR._(_root);
	@override late final Translations$settings$pt_BR settings = Translations$settings$pt_BR._(_root);
	@override late final Translations$about$pt_BR about = Translations$about$pt_BR._(_root);
	@override late final Translations$appUpdate$pt_BR appUpdate = Translations$appUpdate$pt_BR._(_root);
	@override late final Translations$tray$pt_BR tray = Translations$tray$pt_BR._(_root);
	@override late final Translations$failure$pt_BR failure = Translations$failure$pt_BR._(_root);
	@override late final Translations$connection$pt_BR connection = Translations$connection$pt_BR._(_root);
	@override late final Translations$config$pt_BR config = Translations$config$pt_BR._(_root);
}

// Path: general
class Translations$general$pt_BR extends Translations$general$en {
	Translations$general$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get appTitle => 'ClashMiao';
	@override String get reset => 'Restaurar';
	@override late final Translations$general$toggle$pt_BR toggle = Translations$general$toggle$pt_BR._(_root);
	@override late final Translations$general$state$pt_BR state = Translations$general$state$pt_BR._(_root);
	@override String get sort => 'Ordernar';
	@override String get sortBy => 'Ordenar Por';
	@override String get addToClipboard => 'Adicionar à área de transferência';
	@override String get notSet => 'Não configurado';
	@override String get agree => 'Aceitar';
	@override String get decline => 'Recusar';
	@override String get unknown => 'Desconhecido';
	@override String get hidden => 'Escondido';
	@override String get timeout => 'Tempo Esgotado';
	@override String get showMore => 'Mostre mais';
	@override String get showLess => 'Mostre menos';
	@override String get grantPermission => 'Conceder permissão';
	@override String get clipboardExportSuccessMsg => 'Copiado para a área de transferência';
	@override String get openAppSettings => 'Abrir configurações do app';
	@override String get underDevelopment => 'Em desenvolvimento';
	@override String get confirm => 'Confirmar';
	@override String get close => 'Fechar';
	@override String get cancel => 'Cancelar';
	@override String get clipboardEmpty => 'A área de transferência está vazia';
	@override String get clipboardReadFailed => 'Não foi possível ler a área de transferência';
	@override String get moreOptions => 'Mais opções';
}

// Path: intro
class Translations$intro$pt_BR extends Translations$intro$en {
	Translations$intro$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'ao continuar você concorda com '),
		tap(' ${_root.about.termsAndConditions}'),
	]);
	@override String get start => 'Começar';
}

// Path: home
class Translations$home$pt_BR extends Translations$home$en {
	Translations$home$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Inicio';
	@override String get emptyProfilesMsg => 'Comece adicionando um perfil de assinatura';
	@override String get noActiveProfileMsg => 'Escolha um perfil';
	@override late final Translations$home$routingMode$pt_BR routingMode = Translations$home$routingMode$pt_BR._(_root);
	@override String failedToSwitchMode({required Object error}) => 'Falha ao alternar o modo: ${error}';
	@override String get connectionFailedTitle => 'Falha na conexão';
	@override String get coreMissingTitle => 'Biblioteca do núcleo não encontrada';
	@override String get coreMissingMsg => 'O aplicativo não conseguiu carregar seu núcleo de rede. A conexão não está disponível. Reinstale o aplicativo ou verifique se o arquivo da biblioteca do núcleo está junto do executável.';
	@override String get degradedTitle => 'Conectado, mas sem acesso à internet';
	@override String get degradedMsg => 'O túnel está ativo, mas o tráfego não passa. O nó pode estar fora do ar — tente outro nó ou desconecte.';
	@override String get degradedRetry => 'Verificar novamente';
	@override late final Translations$home$egressIp$pt_BR egressIp = Translations$home$egressIp$pt_BR._(_root);
	@override String get emptyProfilesHint => 'Toque no botão abaixo para começar';
	@override String get noActiveProfileTitle => 'Nenhum perfil selecionado';
}

// Path: stats
class Translations$stats$pt_BR extends Translations$stats$en {
	Translations$stats$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get trafficLive => 'Tráfego ao vivo';
	@override String get trafficTotal => 'Tráfego total';
	@override String get uplink => 'Ligação ascendente';
	@override String get downlink => 'Link descendente';
	@override String get connection => 'Conexão';
	@override String get speed => 'Velocidade';
	@override String get totalTransferred => 'Total Transferido';
	@override String get traffic => 'Tráfego';
	@override String get trafficUsage => 'Uso de tráfego';
	@override String get liveSpeed => 'Velocidade ao vivo';
	@override String get sessionTraffic => 'Tráfego da sessão';
	@override String get downloadSpeed => 'Velocidade de download';
}

// Path: profile
class Translations$profile$pt_BR extends Translations$profile$en {
	Translations$profile$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get overviewPageTitle => 'Perfis';
	@override String get detailsPageTitle => 'Perfil';
	@override String activeProfileNameSemanticLabel({required Object name}) => 'Nome do perfil ativo: "${name}".';
	@override String get activeProfileBtnSemanticLabel => 'Ver todos os perfis';
	@override String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Selecione "${name}" como perfil ativo.';
	@override late final Translations$profile$subscription$pt_BR subscription = Translations$profile$subscription$pt_BR._(_root);
	@override late final Translations$profile$sortBy$pt_BR sortBy = Translations$profile$sortBy$pt_BR._(_root);
	@override late final Translations$profile$add$pt_BR add = Translations$profile$add$pt_BR._(_root);
	@override late final Translations$profile$update$pt_BR update = Translations$profile$update$pt_BR._(_root);
	@override late final Translations$profile$share$pt_BR share = Translations$profile$share$pt_BR._(_root);
	@override late final Translations$profile$edit$pt_BR edit = Translations$profile$edit$pt_BR._(_root);
	@override late final Translations$profile$delete$pt_BR delete = Translations$profile$delete$pt_BR._(_root);
	@override late final Translations$profile$save$pt_BR save = Translations$profile$save$pt_BR._(_root);
	@override late final Translations$profile$detailsForm$pt_BR detailsForm = Translations$profile$detailsForm$pt_BR._(_root);
	@override late final Translations$profile$actionButtons$pt_BR actionButtons = Translations$profile$actionButtons$pt_BR._(_root);
	@override late final Translations$profile$details$pt_BR details = Translations$profile$details$pt_BR._(_root);
	@override late final Translations$profile$overview$pt_BR overview = Translations$profile$overview$pt_BR._(_root);
	@override String get remoteProfile => 'Perfil remoto';
	@override String get defaultLocalName => 'Importação local';
	@override String get defaultDeepLinkName => 'Importado por link';
	@override String get switchFailedMsg => 'Não foi possível trocar de perfil';
}

// Path: proxies
class Translations$proxies$pt_BR extends Translations$proxies$en {
	Translations$proxies$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Proxies';
	@override String get emptyProxiesMsg => 'Nenhum proxy disponível';
	@override String get delayTestTooltip => 'Atraso de teste';
	@override String get sortTooltip => 'Ordenar proxies';
	@override String get checkIp => 'Verifique o IP';
	@override String get unknownIp => 'IP desconhecido';
	@override late final Translations$proxies$sortOptions$pt_BR sortOptions = Translations$proxies$sortOptions$pt_BR._(_root);
	@override String get activeProxySemanticLabel => 'Proxy ativo';
	@override late final Translations$proxies$delaySemantics$pt_BR delaySemantics = Translations$proxies$delaySemantics$pt_BR._(_root);
	@override late final Translations$proxies$ipInfoSemantics$pt_BR ipInfoSemantics = Translations$proxies$ipInfoSemantics$pt_BR._(_root);
	@override String get autoSelect => 'Seleção automática';
	@override String get autoSelectDescription => 'Conectar automaticamente ao nó mais rápido';
	@override String get sortModalTitle => 'Escolha o método de ordenação';
	@override String testingDelayInfo({required Object name}) => 'Testando latência de: ${name}';
	@override String switchedTo({required Object name}) => 'Alterado para ${name}';
	@override String get switchFailed => 'Não foi possível trocar de servidor. Tente novamente.';
	@override String get testFailed => 'O teste de latência falhou. Tente novamente.';
	@override String get groupsLoading => 'A lista de servidores ainda está carregando. Tente novamente em instantes.';
	@override String get connectBeforeSwitch => 'Conecte-se antes de trocar de linha';
	@override String startDelayTestForGroups({required Object count}) => 'Teste de latência iniciado para ${count} linhas';
	@override String get delayTestBtn => 'Latência';
	@override String get delayTimeout => 'Esgotado';
	@override String get connectBeforeTest => 'Conecte primeiro para testar o atraso';
	@override String lineCount({required Object count}) => '${count} linhas';
	@override String get manualSelect => 'Seleção manual';
	@override String get autoTest => 'Teste automático';
}

// Path: logs
class Translations$logs$pt_BR extends Translations$logs$en {
	Translations$logs$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Histórico';
	@override String get filterHint => 'Filtro';
	@override String get allLevelsFilter => 'Todos';
	@override String get shareCoreLogs => 'Compartilhe registros principais';
	@override String get shareAppLogs => 'Compartilhe registros de aplicativos';
	@override String get pauseTooltip => 'Pausar';
	@override String get resumeTooltip => 'Resumir';
	@override String get clearTooltip => 'Limpar';
	@override String get logsCleared => 'Registros limpos';
	@override String get logsCopied => 'Registros copiados';
	@override String get logsUnderDevelopment => 'O recurso de registros está em desenvolvimento';
	@override String get noLogsWhenDisconnected => 'Desconectado, sem registros';
	@override String get loadFailed => 'Não foi possível carregar os logs';
	@override String get empty => 'Ainda não há logs';
	@override String get clearFailed => 'Não foi possível limpar os logs';
}

// Path: settings
class Translations$settings$pt_BR extends Translations$settings$en {
	Translations$settings$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Configurações';
	@override String get requiresRestartMsg => 'Para que isso tenha efeito, reinicie o aplicativo';
	@override String get experimental => 'Experimental';
	@override String get experimentalMsg => 'Os recursos com sinalização Experimental ainda estão em desenvolvimento e podem causar problemas.';
	@override late final Translations$settings$general$pt_BR general = Translations$settings$general$pt_BR._(_root);
	@override late final Translations$settings$advanced$pt_BR advanced = Translations$settings$advanced$pt_BR._(_root);
	@override late final Translations$settings$network$pt_BR network = Translations$settings$network$pt_BR._(_root);
	@override late final Translations$settings$geoAssets$pt_BR geoAssets = Translations$settings$geoAssets$pt_BR._(_root);
	@override String get exportOptions => 'Copiar opções anônimas para a área de transferência';
	@override String get exportAllOptions => 'Copiar todas as opções para a área de transferência';
	@override String get importOptions => 'Importar opções da área de transferência';
	@override String get importOptionsMsg => 'Isso substituirá todas as opções de configuração pelos valores fornecidos. Tem certeza?';
	@override late final Translations$settings$backup$pt_BR backup = Translations$settings$backup$pt_BR._(_root);
	@override String get systemProxyEnabled => 'Proxy do sistema ativado';
	@override String get systemProxyDisabled => 'Proxy do sistema desativado (reconecte para aplicar)';
	@override String get adminPrivilegesRequired => 'Requer privilégios de administrador no macOS';
	@override String get portChangeNotice => 'Alterações de porta exigem reconexão para serem aplicadas';
	@override late final Translations$settings$groups$pt_BR groups = Translations$settings$groups$pt_BR._(_root);
	@override String get importOptionsInvalid => 'A área de transferência não contém um JSON de configurações válido';
	@override String get importOptionsNothing => 'Nenhuma configuração importável encontrada';
	@override String importOptionsDone({required Object count}) => '${count} configurações importadas';
	@override String importOptionsPartial({required Object applied, required Object skipped}) => '${applied} configurações importadas; ${skipped} ignoradas por serem inválidas';
}

// Path: about
class Translations$about$pt_BR extends Translations$about$en {
	Translations$about$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Sobre';
	@override String get version => 'Versão';
	@override String get sourceCode => 'Código fonte';
	@override String get telegramChannel => 'Canal Telegram';
	@override String get checkForUpdate => 'Verifique atualizações';
	@override String get privacyPolicy => 'Política de Privacidade';
	@override String get termsAndConditions => 'Termos e Condições';
	@override String get appDescription => 'Um cliente proxy multiplataforma baseado no núcleo sing-box';
	@override String get openSourceLicenses => 'Licenças de código aberto';
}

// Path: appUpdate
class Translations$appUpdate$pt_BR extends Translations$appUpdate$en {
	Translations$appUpdate$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get notAvailableMsg => 'Já usando a versão mais recente';
	@override String get dialogTitle => 'Atualização disponível';
	@override String get updateMsg => 'Uma nova versão de ${_root.general.appTitle} está disponível. Gostaria de atualizar agora?';
	@override String get currentVersionLbl => 'Versão Atual';
	@override String get newVersionLbl => 'Nova versão';
	@override String get updateNowBtnTxt => 'Atualizar agora';
	@override String get laterBtnTxt => 'Mais tarde';
	@override String get ignoreBtnTxt => 'Ignorar';
	@override String get checkFailedMsg => 'Não foi possível verificar atualizações. Verifique sua rede e tente novamente.';
}

// Path: tray
class Translations$tray$pt_BR extends Translations$tray$en {
	Translations$tray$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get dashboard => 'Painel';
	@override String get quit => 'Sair';
	@override String get open => 'Abrir';
	@override late final Translations$tray$status$pt_BR status = Translations$tray$status$pt_BR._(_root);
	@override String get hide => 'Ocultar';
	@override String get proxyModeMenu => 'Modo de proxy';
}

// Path: failure
class Translations$failure$pt_BR extends Translations$failure$en {
	Translations$failure$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro inesperado';
	@override late final Translations$failure$clash$pt_BR clash = Translations$failure$clash$pt_BR._(_root);
	@override late final Translations$failure$singbox$pt_BR singbox = Translations$failure$singbox$pt_BR._(_root);
	@override late final Translations$failure$connectivity$pt_BR connectivity = Translations$failure$connectivity$pt_BR._(_root);
	@override late final Translations$failure$profiles$pt_BR profiles = Translations$failure$profiles$pt_BR._(_root);
	@override late final Translations$failure$connection$pt_BR connection = Translations$failure$connection$pt_BR._(_root);
	@override late final Translations$failure$geoAssets$pt_BR geoAssets = Translations$failure$geoAssets$pt_BR._(_root);
	@override String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$pt_BR extends Translations$connection$en {
	Translations$connection$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get tapToConnect => 'Toque para conectar';
	@override String get connecting => 'Conectando';
	@override String get disconnecting => 'Desconectando';
	@override String get connected => 'Conectado';
	@override String get experimentalNotice => 'Recursos experimentais em uso';
	@override String get experimentalNoticeMsg => 'Você ativou alguns recursos experimentais que podem afetar a qualidade da conexão e causar erros inesperados. Você sempre pode alterar ou redefinir essas opções na página de opções de configuração.';
	@override String get disableExperimentalNotice => 'Não mostrar novamente';
	@override String get reconnect => 'Reconectar';
	@override String get connectAnyWay => 'Conectar mesmo assim';
	@override String get reconnectMsg => 'Reconectando para aplicar as alterações...';
	@override String get staleSystemProxyCleaned => 'Configurações de proxy do sistema deixadas por um encerramento anormal foram limpas';
}

// Path: config
class Translations$config$pt_BR extends Translations$config$en {
	Translations$config$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get resetBtn => 'Redefinir opções';
	@override String get serviceMode => 'Modo de serviço';
	@override late final Translations$config$serviceModes$pt_BR serviceModes = Translations$config$serviceModes$pt_BR._(_root);
	@override late final Translations$config$section$pt_BR section = Translations$config$section$pt_BR._(_root);
	@override late final Translations$config$warpConsent$pt_BR warpConsent = Translations$config$warpConsent$pt_BR._(_root);
	@override String get generateWarpConfig => 'Gerar configuração WARP';
	@override String get missingWarpConfig => 'Configuração WARP ausente';
	@override String get warpConfigGenerated => 'Configuração WARP gerada';
	@override String get pageTitle => 'Opções de configuração';
	@override String get logLevel => 'Nível de registro';
	@override String get resolveDestination => 'Resolver destino';
	@override String get ipv6Mode => 'Rota IPv6';
	@override late final Translations$config$ipv6Modes$pt_BR ipv6Modes = Translations$config$ipv6Modes$pt_BR._(_root);
	@override String get remoteDnsAddress => 'DNS remoto';
	@override String get remoteDnsDomainStrategy => 'Estratégia de Domínio DNS Remoto';
	@override String get directDnsAddress => 'DNS direto';
	@override String get directDnsDomainStrategy => 'Estratégia de Domínio DNS Direto';
	@override String dnsStrategyBlockedIpv6Off({required Object field}) => 'Não aplicado: o roteamento IPv6 está desativado, mas "${field}" é somente IPv6, então nenhum domínio seria resolvido. Ative primeiro o roteamento IPv6 ou escolha outra estratégia.';
	@override String dnsStrategyBlockedIpv6Only({required Object field}) => 'Não aplicado: o roteamento IPv6 é somente IPv6, mas "${field}" é somente IPv4, então nenhum domínio seria resolvido. Ajuste primeiro um dos dois.';
	@override String dnsStrategyReset({required Object field}) => '"${field}" entrava em conflito com o roteamento IPv6 (nenhum domínio seria resolvido) e foi redefinido para automático.';
	@override String get mixedPort => 'Porta Mista';
	@override String get localDnsPort => 'Porta DNS local';
	@override String get allowConnectionFromLan => 'Permitir conexão da LAN';
	@override String get tunImplementation => 'Implementação TUN';
	@override String get mtu => 'MTU';
	@override String get connectionTestUrl => 'URL de teste de conexão';
	@override String get urlTestInterval => 'Intervalo de teste de URL';
	@override String get enableClashApi => 'Ativar API Clash';
	@override String get clashApiPort => 'Porta da API Clash';
	@override String get enableTun => 'Ativar TUN';
	@override String get setSystemProxy => 'Definir proxy do sistema';
	@override String get enableDnsRouting => 'Habilitar roteamento DNS';
	@override String get enableFakeDns => 'Habilitar DNS falso';
	@override String get bypassLan => 'Ignorar LAN';
	@override String get strictRoute => 'Rota Estrita';
	@override String get enableTlsFragment => 'Habilitar fragmento TLS';
	@override String get tlsFragmentSize => 'Tamanho do fragmento TLS';
	@override String get tlsFragmentSleep => 'Suspensão do fragmento TLS';
	@override String get enableTlsMixedSniCase => 'Habilitar caso SNI misto TLS';
	@override String get enableTlsPadding => 'Habilitar preenchimento TLS';
	@override String get tlsPaddingSize => 'Preenchimento TLS';
	@override String get enableMux => 'Habilitar Mux';
	@override String get muxProtocol => 'Protocolo Mux';
	@override String get muxMaxStreams => 'Máximo de fluxos simultâneos';
	@override String get enableWarp => 'Habilitar WARP';
	@override String get setUpWarp => 'Configurar WARP';
	@override String get warpNotConfigured => 'Não configurado';
	@override String get warpDetourMode => 'Modo de desvio';
	@override late final Translations$config$warpDetourModes$pt_BR warpDetourModes = Translations$config$warpDetourModes$pt_BR._(_root);
	@override String get warpLicenseKey => 'Chave de licença';
	@override String get warpCleanIp => 'Limpar IP';
	@override String get warpPort => 'Porta';
	@override String get warpNoise => 'Contagem de ruído';
	@override String get warpNoiseDelay => 'Atraso de ruído';
	@override String get quickSettings => 'Configurações rápidas';
	@override String get quickSettingsSubtitle => 'Personalize sua experiência de conexão';
	@override String get setupWarp => 'Configurar WARP';
	@override String get allOptions => 'Todas as opções de configuração';
	@override String get allAdvancedOptions => 'Todas as opções avançadas';
	@override late final Translations$config$shortServiceModes$pt_BR shortServiceModes = Translations$config$shortServiceModes$pt_BR._(_root);
	@override String get blockAds => 'Bloquear anúncios';
	@override String get tproxyPort => 'Porta de linha transparente';
	@override String get warpNoiseSize => 'Tamanho do ruído';
	@override String get warpNoiseMode => 'Modo de ruído';
	@override String get desktopProxyScopeNotice => 'No desktop, apenas aplicativos que respeitam o proxy do sistema passam pelo túnel. Softwares que o ignoram (alguns jogos, ferramentas de linha de comando, apps com configuração de proxy própria) conectam diretamente e expõem seu IP real.';
	@override String get serviceModeIosVpnOnly => 'O iOS só oferece suporte ao modo VPN';
	@override String get warpGenerating => 'Gerando a configuração do WARP…';
	@override String get warpConfigFailed => 'Não foi possível gerar a configuração do WARP. Tente novamente mais tarde.';
	@override String get portRangeError => 'A porta deve estar entre 1024 e 65535';
	@override String get dnsEmptyError => 'O endereço DNS não pode ficar vazio';
	@override String get rangeFormatError => 'Digite um número ou um intervalo, por exemplo 10-30';
	@override String get urlSchemeError => 'A URL deve começar com http:// ou https://';
	@override String get manageRuleAssets => 'Gerenciar conjuntos de regras';
}

// Path: general.toggle
class Translations$general$toggle$pt_BR extends Translations$general$toggle$en {
	Translations$general$toggle$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get enabled => 'Habilitado';
	@override String get disabled => 'Desabilitado';
}

// Path: general.state
class Translations$general$state$pt_BR extends Translations$general$state$en {
	Translations$general$state$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Desabilitar';
}

// Path: home.routingMode
class Translations$home$routingMode$pt_BR extends Translations$home$routingMode$en {
	Translations$home$routingMode$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get global => 'Proxy global';
	@override String get smart => 'Roteamento inteligente';
}

// Path: home.egressIp
class Translations$home$egressIp$pt_BR extends Translations$home$egressIp$en {
	Translations$home$egressIp$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get label => 'IP de saída';
	@override String get notConnected => 'Conecte para ver o IP de saída';
	@override String get tapToCheck => 'Toque para verificar o IP de saída';
	@override String get checking => 'Verificando…';
	@override String get failedRetry => 'Falha na verificação, toque para tentar novamente';
}

// Path: profile.subscription
class Translations$profile$subscription$pt_BR extends Translations$profile$subscription$en {
	Translations$profile$subscription$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get traffic => 'Tráfego';
	@override String updatedTimeAgo({required Object timeago}) => 'Atualizado ${timeago}';
	@override String remainingDuration({required Object duration}) => '${duration} dias restantes';
	@override String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed} de ${total} tráfego consumido';
	@override String get expired => 'Expirado';
	@override String get noTraffic => 'Fora da cota';
	@override String get upload => 'Upload';
	@override String get download => 'Download';
	@override String get total => 'Tráfego total';
	@override String get expireDate => 'Data de validade';
}

// Path: profile.sortBy
class Translations$profile$sortBy$pt_BR extends Translations$profile$sortBy$en {
	Translations$profile$sortBy$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get lastUpdate => 'Atualizado recentemente';
	@override String get name => 'Alfabeticamente';
}

// Path: profile.add
class Translations$profile$add$pt_BR extends Translations$profile$add$en {
	Translations$profile$add$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Novo Perfil';
	@override String get shortBtnTxt => 'Novo Perfil';
	@override String get fromClipboard => 'Adicionar da área de transferência';
	@override String get scanQr => 'Digitalize o código QR';
	@override late final Translations$profile$add$qrScanner$pt_BR qrScanner = Translations$profile$add$qrScanner$pt_BR._(_root);
	@override String get manually => 'Entrada manual';
	@override String get addingProfileMsg => 'Adicionando Perfil';
	@override String get failureMsg => 'Falha ao adicionar perfil';
	@override String get modalSubtitle => 'Escolha como adicionar o arquivo de configuração';
	@override String get manuallyDescription => 'Insira a configuração do servidor manualmente';
	@override String get addWarp => 'Adicionar WARP';
	@override String get warpDescription => 'Aceleração gratuita com Cloudflare WARP';
	@override String get addingWarpMsg => 'Aguarde enquanto registramos o WARP.';
	@override String importedNamed({required Object name}) => 'Assinatura importada: ${name}';
	@override String get clipboardEmpty => 'A área de transferência está vazia; não há nada para importar';
	@override String get deepLinkMissingUrl => 'O link não contém um endereço de assinatura';
	@override String get successMsg => 'Perfil adicionado';
	@override String get nameAutoHint => 'Detectado automaticamente (opcional)';
}

// Path: profile.update
class Translations$profile$update$pt_BR extends Translations$profile$update$en {
	Translations$profile$update$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Atualizar';
	@override String get tooltip => 'Atualizar Perfil';
	@override String get updateSubscriptions => 'Atualizar assinaturas';
	@override String get failureMsg => 'Falha ao atualizar perfil';
	@override String get successMsg => 'Perfil atualizado com sucesso';
	@override String namedFailureMsg({required Object name}) => 'Falha ao atualizar "${name}"';
	@override String namedSuccessMsg({required Object name}) => '"${name}" atualizado com sucesso';
}

// Path: profile.share
class Translations$profile$share$pt_BR extends Translations$profile$share$en {
	Translations$profile$share$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Compartilhar';
	@override String get exportToClipboardSuccess => 'Exportado para a área de transferência';
	@override String get exportSubLinkToClipboard => 'Exportar link de assinatura para a área de transferência';
	@override String get subLinkQrCode => 'Código QR do link de assinatura';
	@override String get exportConfigToClipboard => 'Exportar configuração para a área de transferência';
	@override String get exportConfigToClipboardSuccess => 'Configuração copiada para a área de transferência';
	@override String get shareLink => 'Compartilhar link';
	@override String get subscriptionLinkCopied => 'Link de assinatura copiado';
	@override String get configCopied => 'Configuração copiada';
	@override String get copyFailed => 'Falha ao copiar';
}

// Path: profile.edit
class Translations$profile$edit$pt_BR extends Translations$profile$edit$en {
	Translations$profile$edit$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Editar';
	@override String get selectActiveTxt => 'Selecionar perfil ativo';
}

// Path: profile.delete
class Translations$profile$delete$pt_BR extends Translations$profile$delete$en {
	Translations$profile$delete$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonTxt => 'Deletar';
	@override String get confirmationMsg => 'Deletar perfil permanentemente?';
	@override String get successMsg => 'Perfil deletado com sucesso';
	@override String get confirmTitle => 'Excluir perfil';
	@override String namedConfirmMsg({required Object name}) => 'Excluir "${name}"? Essa ação não pode ser desfeita.';
}

// Path: profile.save
class Translations$profile$save$pt_BR extends Translations$profile$save$en {
	Translations$profile$save$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get buttonText => 'Salvar';
	@override String get successMsg => 'Perfil salvo com sucesso';
	@override String get failureMsg => 'Falha ao salvar perfil';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$pt_BR extends Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get nameLabel => 'Nome';
	@override String get nameHint => 'Nome do Perfil';
	@override String get urlLabel => 'URL';
	@override String get urlHint => 'URL de configuração completo';
	@override String get emptyNameMsg => 'Nome é obrigatório ';
	@override String get invalidUrlMsg => 'URL inválido';
	@override String get lastUpdate => 'Ultima Atualização';
	@override String get updateInterval => 'Atualização Automática ';
	@override String get updateIntervalDialogTitle => 'Intervalo de atualização automática (em horas)';
	@override String get userAgent => 'User-Agent';
	@override String get userAgentNotSet => 'Not Set';
	@override String get mux => 'Mux';
	@override String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';
	@override String get updateIntervalOff => 'Desativado';
	@override String updateIntervalHours({required Object hours}) => '${hours} h';
	@override String updateIntervalDays({required Object days}) => '${days} d';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$pt_BR extends Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get add => 'Adicionar';
	@override String get updateAll => 'Atualizar tudo';
	@override String get sort => 'Ordenar';
	@override String get copyConfigSuccess => 'Configuração copiada';
	@override String get editConfig => 'Editar configuração';
}

// Path: profile.details
class Translations$profile$details$pt_BR extends Translations$profile$details$en {
	Translations$profile$details$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get basicInfo => 'Informações básicas';
	@override String get subscriptionStatus => 'Status da assinatura';
	@override String get options => 'Opções';
	@override String get updateNow => 'Atualizar agora';
	@override String get updateNowDescription => 'Buscar a configuração mais recente no servidor';
	@override String get expireDate => 'Data de expiração';
	@override String get unlimited => 'Ilimitado';
}

// Path: profile.overview
class Translations$profile$overview$pt_BR extends Translations$profile$overview$en {
	Translations$profile$overview$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get currentlyUsing => 'Em uso';
	@override String remainingDays({required Object days}) => 'Restam ${days} dias';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$pt_BR extends Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unsorted => 'Padrão';
	@override String get name => 'Alfabeticamente';
	@override String get delay => 'Por atraso';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$pt_BR extends Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String result({required Object delay}) => 'atraso: ${delay}ms';
	@override String get timeout => 'atrasar o tempo limite do teste';
	@override String get testing => 'atraso: testando...';
	@override String get untested => 'atraso: não testado';
	@override String stale({required Object delay}) => 'atraso: ${delay}ms (resultado anterior)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$pt_BR extends Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get address => 'Endereço de IP';
	@override String get country => 'País';
}

// Path: settings.general
class Translations$settings$general$pt_BR extends Translations$settings$general$en {
	Translations$settings$general$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Geral';
	@override String get locale => 'Linguagem';
	@override String get region => 'Região';
	@override String get regionMsg => 'Ajuda a definir opções padrão para ignorar endereços domésticos';
	@override late final Translations$settings$general$regions$pt_BR regions = Translations$settings$general$regions$pt_BR._(_root);
	@override String get themeMode => 'Modo de Tema';
	@override late final Translations$settings$general$themeModes$pt_BR themeModes = Translations$settings$general$themeModes$pt_BR._(_root);
	@override String get enableAnalytics => 'Habilitar Análise';
	@override String get enableAnalyticsMsg => 'Dê permissão para coletar análises e enviar relatórios de falhas para melhorar o aplicativo';
	@override String get autoStart => 'Inicializar no login';
	@override String get silentStart => 'Inicializar minimizado';
	@override String get openWorkingDir => 'Abra o diretório de trabalho';
	@override String get ignoreBatteryOptimizations => 'Desative a otimização da bateria';
	@override String get ignoreBatteryOptimizationsMsg => 'Remova as restrições para obter o desempenho ideal da VPN';
	@override String get dynamicNotification => 'Exibir velocidade na notificação';
	@override String get hapticFeedback => 'Feedback tátil';
	@override String get autoIpCheck => 'Verifique automaticamente o IP da conexão';
	@override String get autoStartPermission => 'Permitir inicialização automática';
	@override String get autoStartPermissionMsg => 'Quando ativado, a conexão é restabelecida automaticamente após reiniciar o celular ou atualizar o app';
	@override late final Translations$settings$general$autoStartPermissionStatus$pt_BR autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$pt_BR._(_root);
	@override late final Translations$settings$general$batteryOptimizationStatus$pt_BR batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$pt_BR._(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$pt_BR extends Translations$settings$advanced$en {
	Translations$settings$advanced$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Avançado';
	@override String get debugMode => 'Modo de desenvolvedor';
	@override String get debugModeMsg => 'Reinicie o aplicativo para aplicar esta alteração';
	@override String get memoryLimit => 'Limite de memória';
	@override String get memoryLimitMsg => 'Ative se você estiver enfrentando erros de falta de memória ou travamentos frequentes do aplicativo';
	@override String get resetTunnel => 'Redefinir perfil VPN';
	@override String get resetTunnelSuccess => 'Perfil de VPN redefinido';
}

// Path: settings.network
class Translations$settings$network$pt_BR extends Translations$settings$network$en {
	Translations$settings$network$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get perAppProxyPageTitle => 'Proxy por aplicativo';
	@override late final Translations$settings$network$perAppProxyModes$pt_BR perAppProxyModes = Translations$settings$network$perAppProxyModes$pt_BR._(_root);
	@override String get showSystemApps => 'Mostrar aplicativos do sistema';
	@override String get hideSystemApps => 'Ocultar aplicativos do sistema';
	@override String get clearSelection => 'Limpar seleção';
	@override String get perAppProxyLoadFailedMsg => 'Falha ao carregar a lista de aplicativos';
	@override String get perAppProxyRetry => 'Tentar novamente';
	@override String get perAppProxyEmptyMsg => 'Nenhum resultado encontrado';
	@override String get perAppProxyAndroidOnlyMsg => 'O modo de linha por aplicativo é compatível apenas com Android';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$pt_BR extends Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pageTitle => 'Ativos de roteamento';
	@override String get geoip => 'GeoIP';
	@override String get geosite => 'Geossítio';
	@override String version({required Object version}) => 'Versão ${version}';
	@override String get fileMissing => 'Arquivo faltando';
	@override String get update => 'Atualizar';
	@override String get download => 'Download';
	@override String get failureMsg => 'Falha ao atualizar o recurso';
	@override String get successMsg => 'Recurso atualizado com sucesso';
	@override String get addRecommended => 'Adicionar recursos recomendados';
	@override String get missingGeoAssetsMsg => 'Os arquivos dos ativos de roteamento selecionados estão ausentes. Baixe-os ou escolha os existentes.';
}

// Path: settings.backup
class Translations$settings$backup$pt_BR extends Translations$settings$backup$en {
	Translations$settings$backup$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get importConfirmTitle => 'Importar backup';
	@override String get importConfirmMsg => 'Isto substitui suas assinaturas pelas do backup e aplica as configurações dele. Antes, um instantâneo dos dados atuais é salvo e restaurado automaticamente se a importação falhar.';
	@override String importRemovesMsg({required Object count}) => '${count} assinatura(s) deste dispositivo não estão no backup e serão removidas.';
	@override String reportImported({required Object profiles, required Object settings}) => '${profiles} assinatura(s) e ${settings} configuração(ões) importadas.';
	@override String reportDropped({required Object count}) => '${count} assinatura(s) do backup foram ignoradas porque os dados eram inválidos.';
	@override String reportSettingsSkipped({required Object count}) => '${count} configuração(ões) foram ignoradas; seus valores atuais foram mantidos.';
	@override String get reportWarpOff => 'A importação desativou o WARP. Ative-o novamente neste dispositivo.';
	@override String reportBackfill({required Object count}) => '${count} assinatura(s) serão baixadas em segundo plano.';
	@override String get errInvalidFile => 'Este não é um arquivo de backup válido do ClashMiao.';
	@override String get errUnsupportedVersion => 'Este formato de backup não é compatível.';
	@override String get errNewerSchema => 'Este backup foi criado por uma versão mais recente do app. Atualize o app primeiro.';
	@override String get errNoUsableProfiles => 'Nenhuma das assinaturas deste backup pode ser importada.';
	@override String get errSnapshotFailed => 'Não foi possível salvar um instantâneo dos dados atuais, então nada foi alterado.';
	@override String get errUnresolvedPrevious => 'Uma importação anterior foi interrompida e ainda não pôde ser desfeita. Nada foi alterado. Reinicie o app e tente novamente.';
	@override String get errRolledBack => 'A importação falhou. Seus dados anteriores foram restaurados.';
	@override String errNotRolledBack({required Object path}) => 'A importação falhou e a restauração automática não terminou. Reinicie o app para tentar novamente. Um instantâneo foi salvo em ${path}.';
	@override String get errFailed => 'A importação falhou.';
	@override String get errBusy => 'Já há outra importação em andamento. Aguarde ela terminar.';
	@override String get recoveryFailedTitle => 'A restauração automática não terminou';
	@override String get recoveryFailedMsg => 'A última importação de backup foi interrompida e o app não conseguiu devolver seus dados ao estado anterior. Alguns dados podem ter sido importados pela metade. Tente a restauração automática novamente agora.';
	@override String get recoveryUnrecoverableTitle => 'Não foi possível desfazer a importação interrompida';
	@override String get recoveryUnrecoverableMsg => 'A última importação de backup foi interrompida, mas o instantâneo dela está ausente ou ilegível, então não pode ser desfeita. Verifique suas assinaturas e configurações.';
	@override String get recoveryRetry => 'Tentar novamente';
	@override String get recoveryClose => 'Fechar';
	@override String get recoveryRetried => 'Seus dados foram restaurados ao estado anterior à importação interrompida.';
	@override String get exportAction => 'Exportar backup';
	@override String get importAction => 'Importar backup';
	@override String get exportFailed => 'Não foi possível exportar o backup';
	@override String get shareText => 'Backup do ClashMiao';
}

// Path: settings.groups
class Translations$settings$groups$pt_BR extends Translations$settings$groups$en {
	Translations$settings$groups$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get general => 'Geral';
	@override String get connection => 'Conexão';
	@override String get privacy => 'Privacidade';
}

// Path: tray.status
class Translations$tray$status$pt_BR extends Translations$tray$status$en {
	Translations$tray$status$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get connect => 'Conectar';
	@override String get connecting => 'Conectando';
	@override String get disconnect => 'desconectar';
	@override String get disconnecting => 'Desconectando';
}

// Path: failure.clash
class Translations$failure$clash$pt_BR extends Translations$failure$clash$en {
	Translations$failure$clash$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro inesperado';
	@override String core({required Object reason}) => 'Erro de conflito ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$pt_BR extends Translations$failure$singbox$en {
	Translations$failure$singbox$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro de serviço inesperado';
	@override String get serviceNotRunning => 'O serviço não está em execução';
	@override String get missingPrivilege => 'Privilégio ausente';
	@override String get missingPrivilegeMsg => 'O modo VPN requer privilégios de administrador. Reinicie o aplicativo como administrador ou altere o modo de serviço.';
	@override String get missingGeoAssets => 'Recursos geográficos ausentes';
	@override String get missingGeoAssetsMsg => 'Os recursos geográficos estão faltando. considere alterar o recurso ativo ou baixar um selecionado nas configurações.';
	@override String get invalidConfigOptions => 'Opções de configuração inválidas';
	@override String get invalidConfig => 'Configuração inválida';
	@override String get create => 'Erro ao criar serviço';
	@override String get start => 'Erro de inicialização do serviço';
	@override String get coreLibraryMissing => 'Biblioteca do núcleo não instalada';
	@override String get startTimeout => 'Tempo de inicialização do serviço esgotado';
	@override String get kernelUnresponsive => 'O núcleo não está respondendo. Tente novamente ou reinicie o aplicativo.';
	@override String get kernelExited => 'O núcleo foi encerrado inesperadamente';
}

// Path: failure.connectivity
class Translations$failure$connectivity$pt_BR extends Translations$failure$connectivity$en {
	Translations$failure$connectivity$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Falha inesperada';
	@override String get missingVpnPermission => 'Permissão VPN ausente';
	@override String get missingNotificationPermission => 'Permissão de notificação ausente';
	@override String get core => 'Erro central';
	@override String get networkUnavailable => 'Rede indisponível';
	@override String get nativeUnresponsive => 'Perdeu-se o contato com o serviço em segundo plano. Tente novamente.';
}

// Path: failure.profiles
class Translations$failure$profiles$pt_BR extends Translations$failure$profiles$en {
	Translations$failure$profiles$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro inesperado';
	@override String get notFound => 'Perfil Não Encontrado';
	@override String get invalidConfig => 'Configurações inválidas';
	@override String get invalidUrl => 'URL inválida';
	@override String get noActive => 'Nenhum perfil ativo';
	@override String get readOnlyUpgrade => 'Atualize o app antes de alterar as assinaturas';
}

// Path: failure.connection
class Translations$failure$connection$pt_BR extends Translations$failure$connection$en {
	Translations$failure$connection$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro de conexão inesperado';
	@override String get timeout => 'Tempo limite de conexão';
	@override String get badResponse => 'Erro na Resposta';
	@override String get connectionError => 'Erro de conexão';
	@override String get badCertificate => 'Erro no certificado';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$pt_BR extends Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unexpected => 'Erro inesperado';
	@override String get notUpdate => 'Nenhuma atualização disponível';
	@override String get activeNotFound => 'Recurso geográfico ativo não encontrado';
}

// Path: config.serviceModes
class Translations$config$serviceModes$pt_BR extends Translations$config$serviceModes$en {
	Translations$config$serviceModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Somente serviço de proxy';
	@override String get systemProxy => 'Definir proxy do sistema';
	@override String get tun => 'VPN';
	@override String get tunService => 'Serviço VPN';
}

// Path: config.section
class Translations$config$section$pt_BR extends Translations$config$section$en {
	Translations$config$section$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get route => 'Opções de rota';
	@override String get dns => 'Opções de DNS';
	@override String get inbound => 'Opções de entrada';
	@override String get mux => 'Multiplexador';
	@override String get outbound => 'Opções de saída';
	@override String get tlsTricks => 'Truques TLS';
	@override String get warp => 'Opções de WARP';
	@override String get misc => 'Opções diversas';
}

// Path: config.warpConsent
class Translations$config$warpConsent$pt_BR extends Translations$config$warpConsent$en {
	Translations$config$warpConsent$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Consentimento WARP da Cloudflare';
	@override TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP é um provedor VPN WireGuard gratuito. Ao ativar esta opção, você concorda com os '),
		tos('Termos de Serviço'),
		const TextSpan(text: ' e '),
		privacy('Política de Privacidade'),
		const TextSpan(text: ' do WARP da Cloudflare.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$pt_BR extends Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get disable => 'Desabilitar';
	@override String get enable => 'Habilitar';
	@override String get prefer => 'Preferido';
	@override String get only => 'Exclusivo';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$pt_BR extends Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get inbound => 'Desvie o WARP através de proxies';
	@override String get outbound => 'Desviar proxies através do WARP';
	@override String get proxyOverWarp => 'Desviar linhas através do WARP';
	@override String get warpOverProxy => 'Desviar WARP através das linhas';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$pt_BR extends Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get proxy => 'Somente linha';
	@override String get systemProxy => 'Linha do sistema';
	@override String get tun => 'VPN';
	@override String get tunService => 'Serviço VPN';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$pt_BR extends Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get permissionDeniedError => 'Permissão Negada';
	@override String get unexpectedError => 'Algo deu errado';
	@override String get torchSemanticLabel => 'Luz do flash';
	@override String get facingSemanticLabel => 'Câmera voltada';
	@override String get permissionRequest => 'Permissão de câmera para ler o código QR';
}

// Path: settings.general.regions
class Translations$settings$general$regions$pt_BR extends Translations$settings$general$regions$en {
	Translations$settings$general$regions$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get ir => 'Irã (ir)';
	@override String get cn => 'China (cn)';
	@override String get ru => 'Rússia (ru)';
	@override String get af => 'Afeganistão (af)';
	@override String get id => 'Indonesia (id)';
	@override String get other => 'Outro';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$pt_BR extends Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get system => 'Seguir o tema do sistema';
	@override String get dark => 'Modo Escuro';
	@override String get light => 'Modo Claro';
	@override String get black => 'Modo Preto';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$pt_BR extends Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Ativado';
	@override String get denied => 'Desativado';
	@override String get unknown => 'Desconhecido';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$pt_BR extends Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get exempted => 'Isento';
	@override String get notExempted => 'Não isento';
	@override String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$pt_BR extends Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get off => 'Tudo';
	@override String get offMsg => 'Proxy de todos os aplicativos';
	@override String get include => 'Proxy';
	@override String get includeMsg => 'Aplicativos selecionados apenas por proxy';
	@override String get exclude => 'Ignorar';
	@override String get excludeMsg => 'Não faça proxy de aplicativos selecionados';
}

/// The flat map containing all translations for locale <pt-BR>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsPtBr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Restaurar',
			'general.toggle.enabled' => 'Habilitado',
			'general.toggle.disabled' => 'Desabilitado',
			'general.state.disable' => 'Desabilitar',
			'general.sort' => 'Ordernar',
			'general.sortBy' => 'Ordenar Por',
			'general.addToClipboard' => 'Adicionar à área de transferência',
			'general.notSet' => 'Não configurado',
			'general.agree' => 'Aceitar',
			'general.decline' => 'Recusar',
			'general.unknown' => 'Desconhecido',
			'general.hidden' => 'Escondido',
			'general.timeout' => 'Tempo Esgotado',
			'general.showMore' => 'Mostre mais',
			'general.showLess' => 'Mostre menos',
			'general.grantPermission' => 'Conceder permissão',
			'general.clipboardExportSuccessMsg' => 'Copiado para a área de transferência',
			'general.openAppSettings' => 'Abrir configurações do app',
			'general.underDevelopment' => 'Em desenvolvimento',
			'general.confirm' => 'Confirmar',
			'general.close' => 'Fechar',
			'general.cancel' => 'Cancelar',
			'general.clipboardEmpty' => 'A área de transferência está vazia',
			'general.clipboardReadFailed' => 'Não foi possível ler a área de transferência',
			'general.moreOptions' => 'Mais opções',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'ao continuar você concorda com '), tap(' ${_root.about.termsAndConditions}'), ]), 
			'intro.start' => 'Começar',
			'home.pageTitle' => 'Inicio',
			'home.emptyProfilesMsg' => 'Comece adicionando um perfil de assinatura',
			'home.noActiveProfileMsg' => 'Escolha um perfil',
			'home.routingMode.global' => 'Proxy global',
			'home.routingMode.smart' => 'Roteamento inteligente',
			'home.failedToSwitchMode' => ({required Object error}) => 'Falha ao alternar o modo: ${error}',
			'home.connectionFailedTitle' => 'Falha na conexão',
			'home.coreMissingTitle' => 'Biblioteca do núcleo não encontrada',
			'home.coreMissingMsg' => 'O aplicativo não conseguiu carregar seu núcleo de rede. A conexão não está disponível. Reinstale o aplicativo ou verifique se o arquivo da biblioteca do núcleo está junto do executável.',
			'home.degradedTitle' => 'Conectado, mas sem acesso à internet',
			'home.degradedMsg' => 'O túnel está ativo, mas o tráfego não passa. O nó pode estar fora do ar — tente outro nó ou desconecte.',
			'home.degradedRetry' => 'Verificar novamente',
			'home.egressIp.label' => 'IP de saída',
			'home.egressIp.notConnected' => 'Conecte para ver o IP de saída',
			'home.egressIp.tapToCheck' => 'Toque para verificar o IP de saída',
			'home.egressIp.checking' => 'Verificando…',
			'home.egressIp.failedRetry' => 'Falha na verificação, toque para tentar novamente',
			'home.emptyProfilesHint' => 'Toque no botão abaixo para começar',
			'home.noActiveProfileTitle' => 'Nenhum perfil selecionado',
			'stats.trafficLive' => 'Tráfego ao vivo',
			'stats.trafficTotal' => 'Tráfego total',
			'stats.uplink' => 'Ligação ascendente',
			'stats.downlink' => 'Link descendente',
			'stats.connection' => 'Conexão',
			'stats.speed' => 'Velocidade',
			'stats.totalTransferred' => 'Total Transferido',
			'stats.traffic' => 'Tráfego',
			'stats.trafficUsage' => 'Uso de tráfego',
			'stats.liveSpeed' => 'Velocidade ao vivo',
			'stats.sessionTraffic' => 'Tráfego da sessão',
			'stats.downloadSpeed' => 'Velocidade de download',
			'profile.overviewPageTitle' => 'Perfis',
			'profile.detailsPageTitle' => 'Perfil',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Nome do perfil ativo: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'Ver todos os perfis',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Selecione "${name}" como perfil ativo.',
			'profile.subscription.traffic' => 'Tráfego',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => 'Atualizado ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '${duration} dias restantes',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed} de ${total} tráfego consumido',
			'profile.subscription.expired' => 'Expirado',
			'profile.subscription.noTraffic' => 'Fora da cota',
			'profile.subscription.upload' => 'Upload',
			'profile.subscription.download' => 'Download',
			'profile.subscription.total' => 'Tráfego total',
			'profile.subscription.expireDate' => 'Data de validade',
			'profile.sortBy.lastUpdate' => 'Atualizado recentemente',
			'profile.sortBy.name' => 'Alfabeticamente',
			'profile.add.buttonText' => 'Novo Perfil',
			'profile.add.shortBtnTxt' => 'Novo Perfil',
			'profile.add.fromClipboard' => 'Adicionar da área de transferência',
			'profile.add.scanQr' => 'Digitalize o código QR',
			'profile.add.qrScanner.permissionDeniedError' => 'Permissão Negada',
			'profile.add.qrScanner.unexpectedError' => 'Algo deu errado',
			'profile.add.qrScanner.torchSemanticLabel' => 'Luz do flash',
			'profile.add.qrScanner.facingSemanticLabel' => 'Câmera voltada',
			'profile.add.qrScanner.permissionRequest' => 'Permissão de câmera para ler o código QR',
			'profile.add.manually' => 'Entrada manual',
			'profile.add.addingProfileMsg' => 'Adicionando Perfil',
			'profile.add.failureMsg' => 'Falha ao adicionar perfil',
			'profile.add.modalSubtitle' => 'Escolha como adicionar o arquivo de configuração',
			'profile.add.manuallyDescription' => 'Insira a configuração do servidor manualmente',
			'profile.add.addWarp' => 'Adicionar WARP',
			'profile.add.warpDescription' => 'Aceleração gratuita com Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'Aguarde enquanto registramos o WARP.',
			'profile.add.importedNamed' => ({required Object name}) => 'Assinatura importada: ${name}',
			'profile.add.clipboardEmpty' => 'A área de transferência está vazia; não há nada para importar',
			'profile.add.deepLinkMissingUrl' => 'O link não contém um endereço de assinatura',
			'profile.add.successMsg' => 'Perfil adicionado',
			'profile.add.nameAutoHint' => 'Detectado automaticamente (opcional)',
			'profile.update.buttonTxt' => 'Atualizar',
			'profile.update.tooltip' => 'Atualizar Perfil',
			'profile.update.updateSubscriptions' => 'Atualizar assinaturas',
			'profile.update.failureMsg' => 'Falha ao atualizar perfil',
			'profile.update.successMsg' => 'Perfil atualizado com sucesso',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'Falha ao atualizar "${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" atualizado com sucesso',
			'profile.share.buttonText' => 'Compartilhar',
			'profile.share.exportToClipboardSuccess' => 'Exportado para a área de transferência',
			'profile.share.exportSubLinkToClipboard' => 'Exportar link de assinatura para a área de transferência',
			'profile.share.subLinkQrCode' => 'Código QR do link de assinatura',
			'profile.share.exportConfigToClipboard' => 'Exportar configuração para a área de transferência',
			'profile.share.exportConfigToClipboardSuccess' => 'Configuração copiada para a área de transferência',
			'profile.share.shareLink' => 'Compartilhar link',
			'profile.share.subscriptionLinkCopied' => 'Link de assinatura copiado',
			'profile.share.configCopied' => 'Configuração copiada',
			'profile.share.copyFailed' => 'Falha ao copiar',
			'profile.edit.buttonTxt' => 'Editar',
			'profile.edit.selectActiveTxt' => 'Selecionar perfil ativo',
			'profile.delete.buttonTxt' => 'Deletar',
			'profile.delete.confirmationMsg' => 'Deletar perfil permanentemente?',
			'profile.delete.successMsg' => 'Perfil deletado com sucesso',
			'profile.delete.confirmTitle' => 'Excluir perfil',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => 'Excluir "${name}"? Essa ação não pode ser desfeita.',
			'profile.save.buttonText' => 'Salvar',
			'profile.save.successMsg' => 'Perfil salvo com sucesso',
			'profile.save.failureMsg' => 'Falha ao salvar perfil',
			'profile.detailsForm.nameLabel' => 'Nome',
			'profile.detailsForm.nameHint' => 'Nome do Perfil',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'URL de configuração completo',
			'profile.detailsForm.emptyNameMsg' => 'Nome é obrigatório ',
			'profile.detailsForm.invalidUrlMsg' => 'URL inválido',
			'profile.detailsForm.lastUpdate' => 'Ultima Atualização',
			'profile.detailsForm.updateInterval' => 'Atualização Automática ',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Intervalo de atualização automática (em horas)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Desativado',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} h',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} d',
			'profile.actionButtons.add' => 'Adicionar',
			'profile.actionButtons.updateAll' => 'Atualizar tudo',
			'profile.actionButtons.sort' => 'Ordenar',
			'profile.actionButtons.copyConfigSuccess' => 'Configuração copiada',
			'profile.actionButtons.editConfig' => 'Editar configuração',
			'profile.details.basicInfo' => 'Informações básicas',
			'profile.details.subscriptionStatus' => 'Status da assinatura',
			'profile.details.options' => 'Opções',
			'profile.details.updateNow' => 'Atualizar agora',
			'profile.details.updateNowDescription' => 'Buscar a configuração mais recente no servidor',
			'profile.details.expireDate' => 'Data de expiração',
			'profile.details.unlimited' => 'Ilimitado',
			'profile.overview.currentlyUsing' => 'Em uso',
			'profile.overview.remainingDays' => ({required Object days}) => 'Restam ${days} dias',
			'profile.remoteProfile' => 'Perfil remoto',
			'profile.defaultLocalName' => 'Importação local',
			'profile.defaultDeepLinkName' => 'Importado por link',
			'profile.switchFailedMsg' => 'Não foi possível trocar de perfil',
			'proxies.pageTitle' => 'Proxies',
			'proxies.emptyProxiesMsg' => 'Nenhum proxy disponível',
			'proxies.delayTestTooltip' => 'Atraso de teste',
			'proxies.sortTooltip' => 'Ordenar proxies',
			'proxies.checkIp' => 'Verifique o IP',
			'proxies.unknownIp' => 'IP desconhecido',
			'proxies.sortOptions.unsorted' => 'Padrão',
			'proxies.sortOptions.name' => 'Alfabeticamente',
			'proxies.sortOptions.delay' => 'Por atraso',
			'proxies.activeProxySemanticLabel' => 'Proxy ativo',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'atraso: ${delay}ms',
			'proxies.delaySemantics.timeout' => 'atrasar o tempo limite do teste',
			'proxies.delaySemantics.testing' => 'atraso: testando...',
			'proxies.delaySemantics.untested' => 'atraso: não testado',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'atraso: ${delay}ms (resultado anterior)',
			'proxies.ipInfoSemantics.address' => 'Endereço de IP',
			'proxies.ipInfoSemantics.country' => 'País',
			'proxies.autoSelect' => 'Seleção automática',
			'proxies.autoSelectDescription' => 'Conectar automaticamente ao nó mais rápido',
			'proxies.sortModalTitle' => 'Escolha o método de ordenação',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Testando latência de: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'Alterado para ${name}',
			'proxies.switchFailed' => 'Não foi possível trocar de servidor. Tente novamente.',
			'proxies.testFailed' => 'O teste de latência falhou. Tente novamente.',
			'proxies.groupsLoading' => 'A lista de servidores ainda está carregando. Tente novamente em instantes.',
			'proxies.connectBeforeSwitch' => 'Conecte-se antes de trocar de linha',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'Teste de latência iniciado para ${count} linhas',
			'proxies.delayTestBtn' => 'Latência',
			'proxies.delayTimeout' => 'Esgotado',
			'proxies.connectBeforeTest' => 'Conecte primeiro para testar o atraso',
			'proxies.lineCount' => ({required Object count}) => '${count} linhas',
			'proxies.manualSelect' => 'Seleção manual',
			'proxies.autoTest' => 'Teste automático',
			'logs.pageTitle' => 'Histórico',
			'logs.filterHint' => 'Filtro',
			'logs.allLevelsFilter' => 'Todos',
			'logs.shareCoreLogs' => 'Compartilhe registros principais',
			'logs.shareAppLogs' => 'Compartilhe registros de aplicativos',
			'logs.pauseTooltip' => 'Pausar',
			'logs.resumeTooltip' => 'Resumir',
			'logs.clearTooltip' => 'Limpar',
			'logs.logsCleared' => 'Registros limpos',
			'logs.logsCopied' => 'Registros copiados',
			'logs.logsUnderDevelopment' => 'O recurso de registros está em desenvolvimento',
			'logs.noLogsWhenDisconnected' => 'Desconectado, sem registros',
			'logs.loadFailed' => 'Não foi possível carregar os logs',
			'logs.empty' => 'Ainda não há logs',
			'logs.clearFailed' => 'Não foi possível limpar os logs',
			'settings.pageTitle' => 'Configurações',
			'settings.requiresRestartMsg' => 'Para que isso tenha efeito, reinicie o aplicativo',
			'settings.experimental' => 'Experimental',
			'settings.experimentalMsg' => 'Os recursos com sinalização Experimental ainda estão em desenvolvimento e podem causar problemas.',
			'settings.general.sectionTitle' => 'Geral',
			'settings.general.locale' => 'Linguagem',
			'settings.general.region' => 'Região',
			'settings.general.regionMsg' => 'Ajuda a definir opções padrão para ignorar endereços domésticos',
			'settings.general.regions.ir' => 'Irã (ir)',
			'settings.general.regions.cn' => 'China (cn)',
			'settings.general.regions.ru' => 'Rússia (ru)',
			'settings.general.regions.af' => 'Afeganistão (af)',
			'settings.general.regions.id' => 'Indonesia (id)',
			'settings.general.regions.other' => 'Outro',
			'settings.general.themeMode' => 'Modo de Tema',
			'settings.general.themeModes.system' => 'Seguir o tema do sistema',
			'settings.general.themeModes.dark' => 'Modo Escuro',
			'settings.general.themeModes.light' => 'Modo Claro',
			'settings.general.themeModes.black' => 'Modo Preto',
			'settings.general.enableAnalytics' => 'Habilitar Análise',
			'settings.general.enableAnalyticsMsg' => 'Dê permissão para coletar análises e enviar relatórios de falhas para melhorar o aplicativo',
			'settings.general.autoStart' => 'Inicializar no login',
			'settings.general.silentStart' => 'Inicializar minimizado',
			'settings.general.openWorkingDir' => 'Abra o diretório de trabalho',
			'settings.general.ignoreBatteryOptimizations' => 'Desative a otimização da bateria',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Remova as restrições para obter o desempenho ideal da VPN',
			'settings.general.dynamicNotification' => 'Exibir velocidade na notificação',
			'settings.general.hapticFeedback' => 'Feedback tátil',
			'settings.general.autoIpCheck' => 'Verifique automaticamente o IP da conexão',
			'settings.general.autoStartPermission' => 'Permitir inicialização automática',
			'settings.general.autoStartPermissionMsg' => 'Quando ativado, a conexão é restabelecida automaticamente após reiniciar o celular ou atualizar o app',
			'settings.general.autoStartPermissionStatus.allowed' => 'Ativado',
			'settings.general.autoStartPermissionStatus.denied' => 'Desativado',
			'settings.general.autoStartPermissionStatus.unknown' => 'Desconhecido',
			'settings.general.batteryOptimizationStatus.exempted' => 'Isento',
			'settings.general.batteryOptimizationStatus.notExempted' => 'Não isento',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Avançado',
			'settings.advanced.debugMode' => 'Modo de desenvolvedor',
			'settings.advanced.debugModeMsg' => 'Reinicie o aplicativo para aplicar esta alteração',
			'settings.advanced.memoryLimit' => 'Limite de memória',
			'settings.advanced.memoryLimitMsg' => 'Ative se você estiver enfrentando erros de falta de memória ou travamentos frequentes do aplicativo',
			'settings.advanced.resetTunnel' => 'Redefinir perfil VPN',
			'settings.advanced.resetTunnelSuccess' => 'Perfil de VPN redefinido',
			'settings.network.perAppProxyPageTitle' => 'Proxy por aplicativo',
			'settings.network.perAppProxyModes.off' => 'Tudo',
			'settings.network.perAppProxyModes.offMsg' => 'Proxy de todos os aplicativos',
			'settings.network.perAppProxyModes.include' => 'Proxy',
			'settings.network.perAppProxyModes.includeMsg' => 'Aplicativos selecionados apenas por proxy',
			'settings.network.perAppProxyModes.exclude' => 'Ignorar',
			'settings.network.perAppProxyModes.excludeMsg' => 'Não faça proxy de aplicativos selecionados',
			'settings.network.showSystemApps' => 'Mostrar aplicativos do sistema',
			'settings.network.hideSystemApps' => 'Ocultar aplicativos do sistema',
			'settings.network.clearSelection' => 'Limpar seleção',
			'settings.network.perAppProxyLoadFailedMsg' => 'Falha ao carregar a lista de aplicativos',
			'settings.network.perAppProxyRetry' => 'Tentar novamente',
			'settings.network.perAppProxyEmptyMsg' => 'Nenhum resultado encontrado',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'O modo de linha por aplicativo é compatível apenas com Android',
			'settings.geoAssets.pageTitle' => 'Ativos de roteamento',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'Geossítio',
			'settings.geoAssets.version' => ({required Object version}) => 'Versão ${version}',
			'settings.geoAssets.fileMissing' => 'Arquivo faltando',
			'settings.geoAssets.update' => 'Atualizar',
			'settings.geoAssets.download' => 'Download',
			'settings.geoAssets.failureMsg' => 'Falha ao atualizar o recurso',
			'settings.geoAssets.successMsg' => 'Recurso atualizado com sucesso',
			'settings.geoAssets.addRecommended' => 'Adicionar recursos recomendados',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Os arquivos dos ativos de roteamento selecionados estão ausentes. Baixe-os ou escolha os existentes.',
			'settings.exportOptions' => 'Copiar opções anônimas para a área de transferência',
			'settings.exportAllOptions' => 'Copiar todas as opções para a área de transferência',
			'settings.importOptions' => 'Importar opções da área de transferência',
			'settings.importOptionsMsg' => 'Isso substituirá todas as opções de configuração pelos valores fornecidos. Tem certeza?',
			'settings.backup.importConfirmTitle' => 'Importar backup',
			'settings.backup.importConfirmMsg' => 'Isto substitui suas assinaturas pelas do backup e aplica as configurações dele. Antes, um instantâneo dos dados atuais é salvo e restaurado automaticamente se a importação falhar.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '${count} assinatura(s) deste dispositivo não estão no backup e serão removidas.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => '${profiles} assinatura(s) e ${settings} configuração(ões) importadas.',
			'settings.backup.reportDropped' => ({required Object count}) => '${count} assinatura(s) do backup foram ignoradas porque os dados eram inválidos.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '${count} configuração(ões) foram ignoradas; seus valores atuais foram mantidos.',
			'settings.backup.reportWarpOff' => 'A importação desativou o WARP. Ative-o novamente neste dispositivo.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} assinatura(s) serão baixadas em segundo plano.',
			'settings.backup.errInvalidFile' => 'Este não é um arquivo de backup válido do ClashMiao.',
			'settings.backup.errUnsupportedVersion' => 'Este formato de backup não é compatível.',
			'settings.backup.errNewerSchema' => 'Este backup foi criado por uma versão mais recente do app. Atualize o app primeiro.',
			'settings.backup.errNoUsableProfiles' => 'Nenhuma das assinaturas deste backup pode ser importada.',
			'settings.backup.errSnapshotFailed' => 'Não foi possível salvar um instantâneo dos dados atuais, então nada foi alterado.',
			'settings.backup.errUnresolvedPrevious' => 'Uma importação anterior foi interrompida e ainda não pôde ser desfeita. Nada foi alterado. Reinicie o app e tente novamente.',
			'settings.backup.errRolledBack' => 'A importação falhou. Seus dados anteriores foram restaurados.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'A importação falhou e a restauração automática não terminou. Reinicie o app para tentar novamente. Um instantâneo foi salvo em ${path}.',
			'settings.backup.errFailed' => 'A importação falhou.',
			'settings.backup.errBusy' => 'Já há outra importação em andamento. Aguarde ela terminar.',
			'settings.backup.recoveryFailedTitle' => 'A restauração automática não terminou',
			'settings.backup.recoveryFailedMsg' => 'A última importação de backup foi interrompida e o app não conseguiu devolver seus dados ao estado anterior. Alguns dados podem ter sido importados pela metade. Tente a restauração automática novamente agora.',
			'settings.backup.recoveryUnrecoverableTitle' => 'Não foi possível desfazer a importação interrompida',
			'settings.backup.recoveryUnrecoverableMsg' => 'A última importação de backup foi interrompida, mas o instantâneo dela está ausente ou ilegível, então não pode ser desfeita. Verifique suas assinaturas e configurações.',
			'settings.backup.recoveryRetry' => 'Tentar novamente',
			'settings.backup.recoveryClose' => 'Fechar',
			'settings.backup.recoveryRetried' => 'Seus dados foram restaurados ao estado anterior à importação interrompida.',
			'settings.backup.exportAction' => 'Exportar backup',
			'settings.backup.importAction' => 'Importar backup',
			'settings.backup.exportFailed' => 'Não foi possível exportar o backup',
			'settings.backup.shareText' => 'Backup do ClashMiao',
			'settings.systemProxyEnabled' => 'Proxy do sistema ativado',
			'settings.systemProxyDisabled' => 'Proxy do sistema desativado (reconecte para aplicar)',
			'settings.adminPrivilegesRequired' => 'Requer privilégios de administrador no macOS',
			'settings.portChangeNotice' => 'Alterações de porta exigem reconexão para serem aplicadas',
			'settings.groups.general' => 'Geral',
			'settings.groups.connection' => 'Conexão',
			'settings.groups.privacy' => 'Privacidade',
			'settings.importOptionsInvalid' => 'A área de transferência não contém um JSON de configurações válido',
			'settings.importOptionsNothing' => 'Nenhuma configuração importável encontrada',
			'settings.importOptionsDone' => ({required Object count}) => '${count} configurações importadas',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => '${applied} configurações importadas; ${skipped} ignoradas por serem inválidas',
			'about.pageTitle' => 'Sobre',
			'about.version' => 'Versão',
			'about.sourceCode' => 'Código fonte',
			'about.telegramChannel' => 'Canal Telegram',
			'about.checkForUpdate' => 'Verifique atualizações',
			'about.privacyPolicy' => 'Política de Privacidade',
			'about.termsAndConditions' => 'Termos e Condições',
			'about.appDescription' => 'Um cliente proxy multiplataforma baseado no núcleo sing-box',
			'about.openSourceLicenses' => 'Licenças de código aberto',
			'appUpdate.notAvailableMsg' => 'Já usando a versão mais recente',
			'appUpdate.dialogTitle' => 'Atualização disponível',
			'appUpdate.updateMsg' => 'Uma nova versão de ${_root.general.appTitle} está disponível. Gostaria de atualizar agora?',
			'appUpdate.currentVersionLbl' => 'Versão Atual',
			'appUpdate.newVersionLbl' => 'Nova versão',
			'appUpdate.updateNowBtnTxt' => 'Atualizar agora',
			'appUpdate.laterBtnTxt' => 'Mais tarde',
			'appUpdate.ignoreBtnTxt' => 'Ignorar',
			'appUpdate.checkFailedMsg' => 'Não foi possível verificar atualizações. Verifique sua rede e tente novamente.',
			'tray.dashboard' => 'Painel',
			'tray.quit' => 'Sair',
			'tray.open' => 'Abrir',
			'tray.status.connect' => 'Conectar',
			'tray.status.connecting' => 'Conectando',
			'tray.status.disconnect' => 'desconectar',
			'tray.status.disconnecting' => 'Desconectando',
			'tray.hide' => 'Ocultar',
			'tray.proxyModeMenu' => 'Modo de proxy',
			'failure.unexpected' => 'Erro inesperado',
			'failure.clash.unexpected' => 'Erro inesperado',
			'failure.clash.core' => ({required Object reason}) => 'Erro de conflito ${reason}',
			'failure.singbox.unexpected' => 'Erro de serviço inesperado',
			'failure.singbox.serviceNotRunning' => 'O serviço não está em execução',
			'failure.singbox.missingPrivilege' => 'Privilégio ausente',
			'failure.singbox.missingPrivilegeMsg' => 'O modo VPN requer privilégios de administrador. Reinicie o aplicativo como administrador ou altere o modo de serviço.',
			'failure.singbox.missingGeoAssets' => 'Recursos geográficos ausentes',
			'failure.singbox.missingGeoAssetsMsg' => 'Os recursos geográficos estão faltando. considere alterar o recurso ativo ou baixar um selecionado nas configurações.',
			'failure.singbox.invalidConfigOptions' => 'Opções de configuração inválidas',
			'failure.singbox.invalidConfig' => 'Configuração inválida',
			'failure.singbox.create' => 'Erro ao criar serviço',
			'failure.singbox.start' => 'Erro de inicialização do serviço',
			'failure.singbox.coreLibraryMissing' => 'Biblioteca do núcleo não instalada',
			'failure.singbox.startTimeout' => 'Tempo de inicialização do serviço esgotado',
			'failure.singbox.kernelUnresponsive' => 'O núcleo não está respondendo. Tente novamente ou reinicie o aplicativo.',
			'failure.singbox.kernelExited' => 'O núcleo foi encerrado inesperadamente',
			'failure.connectivity.unexpected' => 'Falha inesperada',
			'failure.connectivity.missingVpnPermission' => 'Permissão VPN ausente',
			'failure.connectivity.missingNotificationPermission' => 'Permissão de notificação ausente',
			'failure.connectivity.core' => 'Erro central',
			'failure.connectivity.networkUnavailable' => 'Rede indisponível',
			'failure.connectivity.nativeUnresponsive' => 'Perdeu-se o contato com o serviço em segundo plano. Tente novamente.',
			'failure.profiles.unexpected' => 'Erro inesperado',
			'failure.profiles.notFound' => 'Perfil Não Encontrado',
			'failure.profiles.invalidConfig' => 'Configurações inválidas',
			'failure.profiles.invalidUrl' => 'URL inválida',
			'failure.profiles.noActive' => 'Nenhum perfil ativo',
			'failure.profiles.readOnlyUpgrade' => 'Atualize o app antes de alterar as assinaturas',
			'failure.connection.unexpected' => 'Erro de conexão inesperado',
			'failure.connection.timeout' => 'Tempo limite de conexão',
			'failure.connection.badResponse' => 'Erro na Resposta',
			'failure.connection.connectionError' => 'Erro de conexão',
			'failure.connection.badCertificate' => 'Erro no certificado',
			'failure.geoAssets.unexpected' => 'Erro inesperado',
			'failure.geoAssets.notUpdate' => 'Nenhuma atualização disponível',
			'failure.geoAssets.activeNotFound' => 'Recurso geográfico ativo não encontrado',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Toque para conectar',
			'connection.connecting' => 'Conectando',
			'connection.disconnecting' => 'Desconectando',
			'connection.connected' => 'Conectado',
			'connection.experimentalNotice' => 'Recursos experimentais em uso',
			'connection.experimentalNoticeMsg' => 'Você ativou alguns recursos experimentais que podem afetar a qualidade da conexão e causar erros inesperados. Você sempre pode alterar ou redefinir essas opções na página de opções de configuração.',
			'connection.disableExperimentalNotice' => 'Não mostrar novamente',
			'connection.reconnect' => 'Reconectar',
			'connection.connectAnyWay' => 'Conectar mesmo assim',
			'connection.reconnectMsg' => 'Reconectando para aplicar as alterações...',
			'connection.staleSystemProxyCleaned' => 'Configurações de proxy do sistema deixadas por um encerramento anormal foram limpas',
			'config.resetBtn' => 'Redefinir opções',
			'config.serviceMode' => 'Modo de serviço',
			'config.serviceModes.proxy' => 'Somente serviço de proxy',
			'config.serviceModes.systemProxy' => 'Definir proxy do sistema',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'Serviço VPN',
			'config.section.route' => 'Opções de rota',
			'config.section.dns' => 'Opções de DNS',
			'config.section.inbound' => 'Opções de entrada',
			'config.section.mux' => 'Multiplexador',
			'config.section.outbound' => 'Opções de saída',
			'config.section.tlsTricks' => 'Truques TLS',
			'config.section.warp' => 'Opções de WARP',
			'config.section.misc' => 'Opções diversas',
			'config.warpConsent.title' => 'Consentimento WARP da Cloudflare',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP é um provedor VPN WireGuard gratuito. Ao ativar esta opção, você concorda com os '), tos('Termos de Serviço'), const TextSpan(text: ' e '), privacy('Política de Privacidade'), const TextSpan(text: ' do WARP da Cloudflare.'), ]), 
			'config.generateWarpConfig' => 'Gerar configuração WARP',
			'config.missingWarpConfig' => 'Configuração WARP ausente',
			'config.warpConfigGenerated' => 'Configuração WARP gerada',
			'config.pageTitle' => 'Opções de configuração',
			'config.logLevel' => 'Nível de registro',
			'config.resolveDestination' => 'Resolver destino',
			'config.ipv6Mode' => 'Rota IPv6',
			'config.ipv6Modes.disable' => 'Desabilitar',
			'config.ipv6Modes.enable' => 'Habilitar',
			'config.ipv6Modes.prefer' => 'Preferido',
			'config.ipv6Modes.only' => 'Exclusivo',
			'config.remoteDnsAddress' => 'DNS remoto',
			'config.remoteDnsDomainStrategy' => 'Estratégia de Domínio DNS Remoto',
			'config.directDnsAddress' => 'DNS direto',
			'config.directDnsDomainStrategy' => 'Estratégia de Domínio DNS Direto',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'Não aplicado: o roteamento IPv6 está desativado, mas "${field}" é somente IPv6, então nenhum domínio seria resolvido. Ative primeiro o roteamento IPv6 ou escolha outra estratégia.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'Não aplicado: o roteamento IPv6 é somente IPv6, mas "${field}" é somente IPv4, então nenhum domínio seria resolvido. Ajuste primeiro um dos dois.',
			'config.dnsStrategyReset' => ({required Object field}) => '"${field}" entrava em conflito com o roteamento IPv6 (nenhum domínio seria resolvido) e foi redefinido para automático.',
			'config.mixedPort' => 'Porta Mista',
			'config.localDnsPort' => 'Porta DNS local',
			'config.allowConnectionFromLan' => 'Permitir conexão da LAN',
			'config.tunImplementation' => 'Implementação TUN',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'URL de teste de conexão',
			'config.urlTestInterval' => 'Intervalo de teste de URL',
			'config.enableClashApi' => 'Ativar API Clash',
			'config.clashApiPort' => 'Porta da API Clash',
			'config.enableTun' => 'Ativar TUN',
			'config.setSystemProxy' => 'Definir proxy do sistema',
			'config.enableDnsRouting' => 'Habilitar roteamento DNS',
			'config.enableFakeDns' => 'Habilitar DNS falso',
			'config.bypassLan' => 'Ignorar LAN',
			'config.strictRoute' => 'Rota Estrita',
			'config.enableTlsFragment' => 'Habilitar fragmento TLS',
			'config.tlsFragmentSize' => 'Tamanho do fragmento TLS',
			'config.tlsFragmentSleep' => 'Suspensão do fragmento TLS',
			'config.enableTlsMixedSniCase' => 'Habilitar caso SNI misto TLS',
			'config.enableTlsPadding' => 'Habilitar preenchimento TLS',
			'config.tlsPaddingSize' => 'Preenchimento TLS',
			'config.enableMux' => 'Habilitar Mux',
			'config.muxProtocol' => 'Protocolo Mux',
			'config.muxMaxStreams' => 'Máximo de fluxos simultâneos',
			'config.enableWarp' => 'Habilitar WARP',
			'config.setUpWarp' => 'Configurar WARP',
			'config.warpNotConfigured' => 'Não configurado',
			'config.warpDetourMode' => 'Modo de desvio',
			'config.warpDetourModes.inbound' => 'Desvie o WARP através de proxies',
			'config.warpDetourModes.outbound' => 'Desviar proxies através do WARP',
			'config.warpDetourModes.proxyOverWarp' => 'Desviar linhas através do WARP',
			'config.warpDetourModes.warpOverProxy' => 'Desviar WARP através das linhas',
			'config.warpLicenseKey' => 'Chave de licença',
			'config.warpCleanIp' => 'Limpar IP',
			'config.warpPort' => 'Porta',
			'config.warpNoise' => 'Contagem de ruído',
			'config.warpNoiseDelay' => 'Atraso de ruído',
			'config.quickSettings' => 'Configurações rápidas',
			'config.quickSettingsSubtitle' => 'Personalize sua experiência de conexão',
			'config.setupWarp' => 'Configurar WARP',
			'config.allOptions' => 'Todas as opções de configuração',
			'config.allAdvancedOptions' => 'Todas as opções avançadas',
			'config.shortServiceModes.proxy' => 'Somente linha',
			'config.shortServiceModes.systemProxy' => 'Linha do sistema',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'Serviço VPN',
			'config.blockAds' => 'Bloquear anúncios',
			'config.tproxyPort' => 'Porta de linha transparente',
			'config.warpNoiseSize' => 'Tamanho do ruído',
			'config.warpNoiseMode' => 'Modo de ruído',
			'config.desktopProxyScopeNotice' => 'No desktop, apenas aplicativos que respeitam o proxy do sistema passam pelo túnel. Softwares que o ignoram (alguns jogos, ferramentas de linha de comando, apps com configuração de proxy própria) conectam diretamente e expõem seu IP real.',
			'config.serviceModeIosVpnOnly' => 'O iOS só oferece suporte ao modo VPN',
			'config.warpGenerating' => 'Gerando a configuração do WARP…',
			'config.warpConfigFailed' => 'Não foi possível gerar a configuração do WARP. Tente novamente mais tarde.',
			'config.portRangeError' => 'A porta deve estar entre 1024 e 65535',
			'config.dnsEmptyError' => 'O endereço DNS não pode ficar vazio',
			'config.rangeFormatError' => 'Digite um número ou um intervalo, por exemplo 10-30',
			'config.urlSchemeError' => 'A URL deve começar com http:// ou https://',
			'config.manageRuleAssets' => 'Gerenciar conjuntos de regras',
			_ => null,
		};
	}
}
