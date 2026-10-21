///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'translations.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$general$en general = Translations$general$en.internal(_root);
	late final Translations$intro$en intro = Translations$intro$en.internal(_root);
	late final Translations$home$en home = Translations$home$en.internal(_root);
	late final Translations$stats$en stats = Translations$stats$en.internal(_root);
	late final Translations$profile$en profile = Translations$profile$en.internal(_root);
	late final Translations$proxies$en proxies = Translations$proxies$en.internal(_root);
	late final Translations$logs$en logs = Translations$logs$en.internal(_root);
	late final Translations$settings$en settings = Translations$settings$en.internal(_root);
	late final Translations$about$en about = Translations$about$en.internal(_root);
	late final Translations$appUpdate$en appUpdate = Translations$appUpdate$en.internal(_root);
	late final Translations$tray$en tray = Translations$tray$en.internal(_root);
	late final Translations$failure$en failure = Translations$failure$en.internal(_root);
	late final Translations$connection$en connection = Translations$connection$en.internal(_root);
	late final Translations$config$en config = Translations$config$en.internal(_root);
}

// Path: general
class Translations$general$en {
	Translations$general$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'ClashMiao'
	String get appTitle => 'ClashMiao';

	/// en: 'Reset'
	String get reset => 'Reset';

	late final Translations$general$toggle$en toggle = Translations$general$toggle$en.internal(_root);
	late final Translations$general$state$en state = Translations$general$state$en.internal(_root);

	/// en: 'Sort'
	String get sort => 'Sort';

	/// en: 'Sort by'
	String get sortBy => 'Sort by';

	/// en: 'Add To Clipboard'
	String get addToClipboard => 'Add To Clipboard';

	/// en: 'Not Set'
	String get notSet => 'Not Set';

	/// en: 'Agree'
	String get agree => 'Agree';

	/// en: 'Decline'
	String get decline => 'Decline';

	/// en: 'Unknown'
	String get unknown => 'Unknown';

	/// en: 'Hidden'
	String get hidden => 'Hidden';

	/// en: 'Timeout'
	String get timeout => 'Timeout';

	/// en: 'Added To Clipboard'
	String get clipboardExportSuccessMsg => 'Added To Clipboard';

	/// en: 'Show More'
	String get showMore => 'Show More';

	/// en: 'Show Less'
	String get showLess => 'Show Less';

	/// en: 'Open App Settings'
	String get openAppSettings => 'Open App Settings';

	/// en: 'Grant Permission'
	String get grantPermission => 'Grant Permission';

	/// en: 'Under Development'
	String get underDevelopment => 'Under Development';

	/// en: 'Confirm'
	String get confirm => 'Confirm';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Clipboard is empty'
	String get clipboardEmpty => 'Clipboard is empty';

	/// en: 'Couldn't read the clipboard'
	String get clipboardReadFailed => 'Couldn\'t read the clipboard';

	/// en: 'More options'
	String get moreOptions => 'More options';
}

// Path: intro
class Translations$intro$en {
	Translations$intro$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'By Continuing You Agree With ${tap(Terms and Conditions)}'
	TextSpan termsAndPolicyCaution({required InlineSpanBuilder tap}) => TextSpan(children: [
		const TextSpan(text: 'By Continuing You Agree With '),
		tap(_root.about.termsAndConditions),
	]);

	/// en: 'Start'
	String get start => 'Start';
}

// Path: home
class Translations$home$en {
	Translations$home$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Home'
	String get pageTitle => 'Home';

	/// en: 'No lines yet'
	String get emptyProfilesMsg => 'No lines yet';

	/// en: 'Choose a Profile'
	String get noActiveProfileMsg => 'Choose a Profile';

	late final Translations$home$routingMode$en routingMode = Translations$home$routingMode$en.internal(_root);

	/// en: 'Failed to switch mode: ${error}'
	String failedToSwitchMode({required Object error}) => 'Failed to switch mode: ${error}';

	/// en: 'Connection Failed'
	String get connectionFailedTitle => 'Connection Failed';

	/// en: 'Core Library Not Found'
	String get coreMissingTitle => 'Core Library Not Found';

	/// en: 'The app could not load its networking core. Connecting is unavailable. Reinstall the app, or make sure the core library file sits next to the executable.'
	String get coreMissingMsg => 'The app could not load its networking core. Connecting is unavailable. Reinstall the app, or make sure the core library file sits next to the executable.';

	/// en: 'Connected, but no internet access'
	String get degradedTitle => 'Connected, but no internet access';

	/// en: 'The tunnel is up but traffic is not getting through. The node may be down — try another node, or disconnect.'
	String get degradedMsg => 'The tunnel is up but traffic is not getting through. The node may be down — try another node, or disconnect.';

	/// en: 'Check again'
	String get degradedRetry => 'Check again';

	late final Translations$home$egressIp$en egressIp = Translations$home$egressIp$en.internal(_root);

	/// en: 'Tap the button below to get started'
	String get emptyProfilesHint => 'Tap the button below to get started';

	/// en: 'No profile selected'
	String get noActiveProfileTitle => 'No profile selected';
}

// Path: stats
class Translations$stats$en {
	Translations$stats$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Traffic'
	String get traffic => 'Traffic';

	/// en: 'Live Traffic'
	String get trafficLive => 'Live Traffic';

	/// en: 'Total Traffic'
	String get trafficTotal => 'Total Traffic';

	/// en: 'Traffic Usage'
	String get trafficUsage => 'Traffic Usage';

	/// en: 'Live Speed'
	String get liveSpeed => 'Live Speed';

	/// en: 'Uplink'
	String get uplink => 'Uplink';

	/// en: 'Downlink'
	String get downlink => 'Downlink';

	/// en: 'Connection'
	String get connection => 'Connection';

	/// en: 'Speed'
	String get speed => 'Speed';

	/// en: 'Total Transferred'
	String get totalTransferred => 'Total Transferred';

	/// en: 'Session traffic'
	String get sessionTraffic => 'Session traffic';

	/// en: 'Download speed'
	String get downloadSpeed => 'Download speed';
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Profiles'
	String get overviewPageTitle => 'Profiles';

	/// en: 'Profile'
	String get detailsPageTitle => 'Profile';

	/// en: 'Active Profile Name: "${name}".'
	String activeProfileNameSemanticLabel({required Object name}) => 'Active Profile Name: "${name}".';

	/// en: 'View All Profiles'
	String get activeProfileBtnSemanticLabel => 'View All Profiles';

	/// en: 'Select "${name}" as Active Profile'
	String nonActiveProfileBtnSemanticLabel({required Object name}) => 'Select "${name}" as Active Profile';

	late final Translations$profile$subscription$en subscription = Translations$profile$subscription$en.internal(_root);
	late final Translations$profile$sortBy$en sortBy = Translations$profile$sortBy$en.internal(_root);
	late final Translations$profile$actionButtons$en actionButtons = Translations$profile$actionButtons$en.internal(_root);
	late final Translations$profile$add$en add = Translations$profile$add$en.internal(_root);
	late final Translations$profile$details$en details = Translations$profile$details$en.internal(_root);
	late final Translations$profile$share$en share = Translations$profile$share$en.internal(_root);
	late final Translations$profile$overview$en overview = Translations$profile$overview$en.internal(_root);
	late final Translations$profile$update$en update = Translations$profile$update$en.internal(_root);
	late final Translations$profile$edit$en edit = Translations$profile$edit$en.internal(_root);
	late final Translations$profile$delete$en delete = Translations$profile$delete$en.internal(_root);
	late final Translations$profile$save$en save = Translations$profile$save$en.internal(_root);
	late final Translations$profile$detailsForm$en detailsForm = Translations$profile$detailsForm$en.internal(_root);

	/// en: 'Remote Profile'
	String get remoteProfile => 'Remote Profile';

	/// en: 'Local import'
	String get defaultLocalName => 'Local import';

	/// en: 'Link import'
	String get defaultDeepLinkName => 'Link import';

	/// en: 'Couldn't switch profile'
	String get switchFailedMsg => 'Couldn\'t switch profile';
}

// Path: proxies
class Translations$proxies$en {
	Translations$proxies$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Lines'
	String get pageTitle => 'Lines';

	/// en: 'No Lines Available'
	String get emptyProxiesMsg => 'No Lines Available';

	/// en: 'Test Delay'
	String get delayTestTooltip => 'Test Delay';

	/// en: 'Sort Lines'
	String get sortTooltip => 'Sort Lines';

	/// en: 'Check IP'
	String get checkIp => 'Check IP';

	/// en: 'Unknown IP'
	String get unknownIp => 'Unknown IP';

	/// en: 'Auto Select'
	String get autoSelect => 'Auto Select';

	/// en: 'Auto connect to the fastest node'
	String get autoSelectDescription => 'Auto connect to the fastest node';

	late final Translations$proxies$sortOptions$en sortOptions = Translations$proxies$sortOptions$en.internal(_root);

	/// en: 'Choose sort method'
	String get sortModalTitle => 'Choose sort method';

	/// en: 'Active Line'
	String get activeProxySemanticLabel => 'Active Line';

	late final Translations$proxies$delaySemantics$en delaySemantics = Translations$proxies$delaySemantics$en.internal(_root);
	late final Translations$proxies$ipInfoSemantics$en ipInfoSemantics = Translations$proxies$ipInfoSemantics$en.internal(_root);

	/// en: 'Testing delay for: ${name}'
	String testingDelayInfo({required Object name}) => 'Testing delay for: ${name}';

	/// en: 'Switched to ${name}'
	String switchedTo({required Object name}) => 'Switched to ${name}';

	/// en: 'Couldn't switch the server. Please try again.'
	String get switchFailed => 'Couldn\'t switch the server. Please try again.';

	/// en: 'Latency test failed. Please try again.'
	String get testFailed => 'Latency test failed. Please try again.';

	/// en: 'Server list is still loading. Please try again in a moment.'
	String get groupsLoading => 'Server list is still loading. Please try again in a moment.';

	/// en: 'Please connect before switching lines'
	String get connectBeforeSwitch => 'Please connect before switching lines';

	/// en: 'Started delay test for ${count} lines'
	String startDelayTestForGroups({required Object count}) => 'Started delay test for ${count} lines';

	/// en: 'Delay'
	String get delayTestBtn => 'Delay';

	/// en: 'Timeout'
	String get delayTimeout => 'Timeout';

	/// en: 'Connect first to test delay'
	String get connectBeforeTest => 'Connect first to test delay';

	/// en: '${count} lines'
	String lineCount({required Object count}) => '${count} lines';

	/// en: 'Manual Select'
	String get manualSelect => 'Manual Select';

	/// en: 'Auto Test'
	String get autoTest => 'Auto Test';
}

// Path: logs
class Translations$logs$en {
	Translations$logs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Logs'
	String get pageTitle => 'Logs';

	/// en: 'Filter'
	String get filterHint => 'Filter';

	/// en: 'All'
	String get allLevelsFilter => 'All';

	/// en: 'Share Core Logs'
	String get shareCoreLogs => 'Share Core Logs';

	/// en: 'Share App Logs'
	String get shareAppLogs => 'Share App Logs';

	/// en: 'Pause'
	String get pauseTooltip => 'Pause';

	/// en: 'Resume'
	String get resumeTooltip => 'Resume';

	/// en: 'Clear'
	String get clearTooltip => 'Clear';

	/// en: 'Logs cleared'
	String get logsCleared => 'Logs cleared';

	/// en: 'Logs copied'
	String get logsCopied => 'Logs copied';

	/// en: 'Log feature is under development'
	String get logsUnderDevelopment => 'Log feature is under development';

	/// en: 'Not connected, no logs'
	String get noLogsWhenDisconnected => 'Not connected, no logs';

	/// en: 'Couldn't load logs'
	String get loadFailed => 'Couldn\'t load logs';

	/// en: 'No logs yet'
	String get empty => 'No logs yet';

	/// en: 'Couldn't clear logs'
	String get clearFailed => 'Couldn\'t clear logs';
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings'
	String get pageTitle => 'Settings';

	/// en: 'For this to take effect restart the app'
	String get requiresRestartMsg => 'For this to take effect restart the app';

	/// en: 'Experimental'
	String get experimental => 'Experimental';

	/// en: 'Features with Experimental flag are still in development and might cause issues.'
	String get experimentalMsg => 'Features with Experimental flag are still in development and might cause issues.';

	/// en: 'Copy Anonymous Options to Clipboard'
	String get exportOptions => 'Copy Anonymous Options to Clipboard';

	/// en: 'Copy All Options to Clipboard'
	String get exportAllOptions => 'Copy All Options to Clipboard';

	/// en: 'Import Options From Clipboard'
	String get importOptions => 'Import Options From Clipboard';

	/// en: 'This will rewrite all config options with provided values. Are you sure?'
	String get importOptionsMsg => 'This will rewrite all config options with provided values. Are you sure?';

	late final Translations$settings$backup$en backup = Translations$settings$backup$en.internal(_root);
	late final Translations$settings$general$en general = Translations$settings$general$en.internal(_root);
	late final Translations$settings$advanced$en advanced = Translations$settings$advanced$en.internal(_root);
	late final Translations$settings$network$en network = Translations$settings$network$en.internal(_root);
	late final Translations$settings$geoAssets$en geoAssets = Translations$settings$geoAssets$en.internal(_root);

	/// en: 'System proxy enabled'
	String get systemProxyEnabled => 'System proxy enabled';

	/// en: 'System proxy disabled (Reconnect to apply)'
	String get systemProxyDisabled => 'System proxy disabled (Reconnect to apply)';

	/// en: 'Administrator privileges required on macOS'
	String get adminPrivilegesRequired => 'Administrator privileges required on macOS';

	/// en: 'Port changes require reconnect to apply'
	String get portChangeNotice => 'Port changes require reconnect to apply';

	late final Translations$settings$groups$en groups = Translations$settings$groups$en.internal(_root);

	/// en: 'The clipboard doesn't contain valid settings JSON'
	String get importOptionsInvalid => 'The clipboard doesn\'t contain valid settings JSON';

	/// en: 'No importable settings found'
	String get importOptionsNothing => 'No importable settings found';

	/// en: 'Imported ${count} settings'
	String importOptionsDone({required Object count}) => 'Imported ${count} settings';

	/// en: 'Imported ${applied} settings; ${skipped} were skipped because they were invalid'
	String importOptionsPartial({required Object applied, required Object skipped}) => 'Imported ${applied} settings; ${skipped} were skipped because they were invalid';
}

// Path: about
class Translations$about$en {
	Translations$about$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'About'
	String get pageTitle => 'About';

	/// en: 'Version'
	String get version => 'Version';

	/// en: 'Source Code'
	String get sourceCode => 'Source Code';

	/// en: 'Telegram Channel'
	String get telegramChannel => 'Telegram Channel';

	/// en: 'Check For Update'
	String get checkForUpdate => 'Check For Update';

	/// en: 'Privacy Policy'
	String get privacyPolicy => 'Privacy Policy';

	/// en: 'Terms and Conditions'
	String get termsAndConditions => 'Terms and Conditions';

	/// en: 'A cross-platform proxy client based on sing-box core'
	String get appDescription => 'A cross-platform proxy client based on sing-box core';

	/// en: 'Open-source licenses'
	String get openSourceLicenses => 'Open-source licenses';
}

// Path: appUpdate
class Translations$appUpdate$en {
	Translations$appUpdate$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Already Using The Latest Version'
	String get notAvailableMsg => 'Already Using The Latest Version';

	/// en: 'Update Available'
	String get dialogTitle => 'Update Available';

	/// en: 'A new version of ClashMiao is available. Would you like to update now?'
	String get updateMsg => 'A new version of ${_root.general.appTitle} is available. Would you like to update now?';

	/// en: 'Current Version'
	String get currentVersionLbl => 'Current Version';

	/// en: 'New Version'
	String get newVersionLbl => 'New Version';

	/// en: 'Update Now'
	String get updateNowBtnTxt => 'Update Now';

	/// en: 'Later'
	String get laterBtnTxt => 'Later';

	/// en: 'Ignore'
	String get ignoreBtnTxt => 'Ignore';

	/// en: 'Couldn't check for updates. Check your network and try again.'
	String get checkFailedMsg => 'Couldn\'t check for updates. Check your network and try again.';
}

// Path: tray
class Translations$tray$en {
	Translations$tray$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Dashboard'
	String get dashboard => 'Dashboard';

	/// en: 'Quit'
	String get quit => 'Quit';

	/// en: 'Open'
	String get open => 'Open';

	/// en: 'Hide to Tray'
	String get hide => 'Hide to Tray';

	late final Translations$tray$status$en status = Translations$tray$status$en.internal(_root);

	/// en: 'Proxy Mode'
	String get proxyModeMenu => 'Proxy Mode';
}

// Path: failure
class Translations$failure$en {
	Translations$failure$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Error'
	String get unexpected => 'Unexpected Error';

	late final Translations$failure$clash$en clash = Translations$failure$clash$en.internal(_root);
	late final Translations$failure$singbox$en singbox = Translations$failure$singbox$en.internal(_root);
	late final Translations$failure$connectivity$en connectivity = Translations$failure$connectivity$en.internal(_root);
	late final Translations$failure$profiles$en profiles = Translations$failure$profiles$en.internal(_root);
	late final Translations$failure$connection$en connection = Translations$failure$connection$en.internal(_root);
	late final Translations$failure$geoAssets$en geoAssets = Translations$failure$geoAssets$en.internal(_root);

	/// en: '${message}: ${reason}'
	String withReason({required Object message, required Object reason}) => '${message}: ${reason}';
}

// Path: connection
class Translations$connection$en {
	Translations$connection$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Tap To Connect'
	String get tapToConnect => 'Tap To Connect';

	/// en: 'Connecting'
	String get connecting => 'Connecting';

	/// en: 'Disconnecting'
	String get disconnecting => 'Disconnecting';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Reconnect'
	String get reconnect => 'Reconnect';

	/// en: 'Connect Anyway'
	String get connectAnyWay => 'Connect Anyway';

	/// en: 'Experimental Features In Use'
	String get experimentalNotice => 'Experimental Features In Use';

	/// en: 'You've enabled some experimental features which might affect connection quality and cause unexpected errors. You can always change or reset these options from Config options page.'
	String get experimentalNoticeMsg => 'You\'ve enabled some experimental features which might affect connection quality and cause unexpected errors. You can always change or reset these options from Config options page.';

	/// en: 'Don't Show Again'
	String get disableExperimentalNotice => 'Don\'t Show Again';

	/// en: 'Reconnecting for taking into account the changes...'
	String get reconnectMsg => 'Reconnecting for taking into account the changes...';

	/// en: 'Cleaned up system proxy settings left behind by an abnormal exit last time'
	String get staleSystemProxyCleaned => 'Cleaned up system proxy settings left behind by an abnormal exit last time';
}

// Path: config
class Translations$config$en {
	Translations$config$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Reset Options'
	String get resetBtn => 'Reset Options';

	/// en: 'Service Mode'
	String get serviceMode => 'Service Mode';

	/// en: 'Quick Settings'
	String get quickSettings => 'Quick Settings';

	/// en: 'Customize your connection experience'
	String get quickSettingsSubtitle => 'Customize your connection experience';

	/// en: 'Setup WARP'
	String get setupWarp => 'Setup WARP';

	/// en: 'All Config Options'
	String get allOptions => 'All Config Options';

	/// en: 'All Advanced Options'
	String get allAdvancedOptions => 'All Advanced Options';

	late final Translations$config$serviceModes$en serviceModes = Translations$config$serviceModes$en.internal(_root);
	late final Translations$config$shortServiceModes$en shortServiceModes = Translations$config$shortServiceModes$en.internal(_root);
	late final Translations$config$section$en section = Translations$config$section$en.internal(_root);
	late final Translations$config$warpConsent$en warpConsent = Translations$config$warpConsent$en.internal(_root);

	/// en: 'Generate WARP Config'
	String get generateWarpConfig => 'Generate WARP Config';

	/// en: 'Missing WARP Config'
	String get missingWarpConfig => 'Missing WARP Config';

	/// en: 'WARP Config Generated'
	String get warpConfigGenerated => 'WARP Config Generated';

	/// en: 'Config Options'
	String get pageTitle => 'Config Options';

	/// en: 'Log Level'
	String get logLevel => 'Log Level';

	/// en: 'Block Advertisements'
	String get blockAds => 'Block Advertisements';

	/// en: 'Resolve Destination'
	String get resolveDestination => 'Resolve Destination';

	/// en: 'IPv6 Route'
	String get ipv6Mode => 'IPv6 Route';

	late final Translations$config$ipv6Modes$en ipv6Modes = Translations$config$ipv6Modes$en.internal(_root);

	/// en: 'Remote DNS'
	String get remoteDnsAddress => 'Remote DNS';

	/// en: 'Remote DNS Domain Strategy'
	String get remoteDnsDomainStrategy => 'Remote DNS Domain Strategy';

	/// en: 'Direct DNS'
	String get directDnsAddress => 'Direct DNS';

	/// en: 'Direct DNS Domain Strategy'
	String get directDnsDomainStrategy => 'Direct DNS Domain Strategy';

	/// en: 'Not applied: IPv6 routing is disabled but "${field}" is IPv6-only, so no domain could be resolved. Enable IPv6 routing first, or choose another strategy.'
	String dnsStrategyBlockedIpv6Off({required Object field}) => 'Not applied: IPv6 routing is disabled but "${field}" is IPv6-only, so no domain could be resolved. Enable IPv6 routing first, or choose another strategy.';

	/// en: 'Not applied: IPv6 routing is IPv6-only but "${field}" is IPv4-only, so no domain could be resolved. Adjust one of them first.'
	String dnsStrategyBlockedIpv6Only({required Object field}) => 'Not applied: IPv6 routing is IPv6-only but "${field}" is IPv4-only, so no domain could be resolved. Adjust one of them first.';

	/// en: '"${field}" conflicted with the IPv6 routing setting (no domain could be resolved) and was reset to auto.'
	String dnsStrategyReset({required Object field}) => '"${field}" conflicted with the IPv6 routing setting (no domain could be resolved) and was reset to auto.';

	/// en: 'Mixed Port'
	String get mixedPort => 'Mixed Port';

	/// en: 'Transparent Line Port'
	String get tproxyPort => 'Transparent Line Port';

	/// en: 'Local DNS Port'
	String get localDnsPort => 'Local DNS Port';

	/// en: 'Share VPN in Local Network'
	String get allowConnectionFromLan => 'Share VPN in Local Network';

	/// en: 'TUN Implementation'
	String get tunImplementation => 'TUN Implementation';

	/// en: 'MTU'
	String get mtu => 'MTU';

	/// en: 'Connection Test URL'
	String get connectionTestUrl => 'Connection Test URL';

	/// en: 'URL Test Interval'
	String get urlTestInterval => 'URL Test Interval';

	/// en: 'Enable Clash API'
	String get enableClashApi => 'Enable Clash API';

	/// en: 'Clash API Port'
	String get clashApiPort => 'Clash API Port';

	/// en: 'Enable TUN'
	String get enableTun => 'Enable TUN';

	/// en: 'Set System Line'
	String get setSystemProxy => 'Set System Line';

	/// en: 'Enable DNS Routing'
	String get enableDnsRouting => 'Enable DNS Routing';

	/// en: 'Enable Fake DNS'
	String get enableFakeDns => 'Enable Fake DNS';

	/// en: 'Bypass Lan'
	String get bypassLan => 'Bypass Lan';

	/// en: 'Strict Route'
	String get strictRoute => 'Strict Route';

	/// en: 'Enable TLS Fragment'
	String get enableTlsFragment => 'Enable TLS Fragment';

	/// en: 'TLS Fragment Size'
	String get tlsFragmentSize => 'TLS Fragment Size';

	/// en: 'TLS Fragment Sleep'
	String get tlsFragmentSleep => 'TLS Fragment Sleep';

	/// en: 'Enable TLS Mixed SNI Case'
	String get enableTlsMixedSniCase => 'Enable TLS Mixed SNI Case';

	/// en: 'Enable TLS Padding'
	String get enableTlsPadding => 'Enable TLS Padding';

	/// en: 'TLS Padding'
	String get tlsPaddingSize => 'TLS Padding';

	/// en: 'Enable Mux'
	String get enableMux => 'Enable Mux';

	/// en: 'Mux Protocol'
	String get muxProtocol => 'Mux Protocol';

	/// en: 'Max Concurrent Streams'
	String get muxMaxStreams => 'Max Concurrent Streams';

	/// en: 'Enable WARP'
	String get enableWarp => 'Enable WARP';

	/// en: 'Set up WARP'
	String get setUpWarp => 'Set up WARP';

	/// en: 'Not configured'
	String get warpNotConfigured => 'Not configured';

	/// en: 'Detour Mode'
	String get warpDetourMode => 'Detour Mode';

	late final Translations$config$warpDetourModes$en warpDetourModes = Translations$config$warpDetourModes$en.internal(_root);

	/// en: 'License Key'
	String get warpLicenseKey => 'License Key';

	/// en: 'Clean IP'
	String get warpCleanIp => 'Clean IP';

	/// en: 'Port'
	String get warpPort => 'Port';

	/// en: 'Noise Count'
	String get warpNoise => 'Noise Count';

	/// en: 'Noise Size'
	String get warpNoiseSize => 'Noise Size';

	/// en: 'Noise Mode'
	String get warpNoiseMode => 'Noise Mode';

	/// en: 'Noise Delay'
	String get warpNoiseDelay => 'Noise Delay';

	/// en: 'On desktop, only apps that honor the system proxy are routed through the tunnel. Software that ignores it (some games, CLI tools, apps with their own proxy settings) connects directly and exposes your real IP.'
	String get desktopProxyScopeNotice => 'On desktop, only apps that honor the system proxy are routed through the tunnel. Software that ignores it (some games, CLI tools, apps with their own proxy settings) connects directly and exposes your real IP.';

	/// en: 'iOS supports VPN mode only'
	String get serviceModeIosVpnOnly => 'iOS supports VPN mode only';

	/// en: 'Generating WARP configuration…'
	String get warpGenerating => 'Generating WARP configuration…';

	/// en: 'Couldn't generate the WARP configuration. Please try again later.'
	String get warpConfigFailed => 'Couldn\'t generate the WARP configuration. Please try again later.';

	/// en: 'Port must be between 1024 and 65535'
	String get portRangeError => 'Port must be between 1024 and 65535';

	/// en: 'DNS address can't be empty'
	String get dnsEmptyError => 'DNS address can\'t be empty';

	/// en: 'Enter a number or a range, e.g. 10-30'
	String get rangeFormatError => 'Enter a number or a range, e.g. 10-30';

	/// en: 'URL must start with http:// or https://'
	String get urlSchemeError => 'URL must start with http:// or https://';

	/// en: 'Manage rule sets'
	String get manageRuleAssets => 'Manage rule sets';
}

// Path: general.toggle
class Translations$general$toggle$en {
	Translations$general$toggle$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Enabled'
	String get enabled => 'Enabled';

	/// en: 'Disabled'
	String get disabled => 'Disabled';
}

// Path: general.state
class Translations$general$state$en {
	Translations$general$state$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Disable'
	String get disable => 'Disable';
}

// Path: home.routingMode
class Translations$home$routingMode$en {
	Translations$home$routingMode$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Global Proxy'
	String get global => 'Global Proxy';

	/// en: 'Smart Routing'
	String get smart => 'Smart Routing';
}

// Path: home.egressIp
class Translations$home$egressIp$en {
	Translations$home$egressIp$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Egress IP'
	String get label => 'Egress IP';

	/// en: 'Connect to show egress IP'
	String get notConnected => 'Connect to show egress IP';

	/// en: 'Tap to check egress IP'
	String get tapToCheck => 'Tap to check egress IP';

	/// en: 'Checking…'
	String get checking => 'Checking…';

	/// en: 'Check failed, tap to retry'
	String get failedRetry => 'Check failed, tap to retry';
}

// Path: profile.subscription
class Translations$profile$subscription$en {
	Translations$profile$subscription$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Traffic'
	String get traffic => 'Traffic';

	/// en: 'Updated ${timeago}'
	String updatedTimeAgo({required Object timeago}) => 'Updated ${timeago}';

	/// en: '${duration} Days Remaining'
	String remainingDuration({required Object duration}) => '${duration} Days Remaining';

	/// en: '${consumed} of ${total} Traffic Consumed'
	String remainingTrafficSemanticLabel({required Object consumed, required Object total}) => '${consumed} of ${total} Traffic Consumed';

	/// en: 'Expired'
	String get expired => 'Expired';

	/// en: 'Out of Quota'
	String get noTraffic => 'Out of Quota';

	/// en: 'Upload'
	String get upload => 'Upload';

	/// en: 'Download'
	String get download => 'Download';

	/// en: 'Total Traffic'
	String get total => 'Total Traffic';

	/// en: 'Expire Date'
	String get expireDate => 'Expire Date';
}

// Path: profile.sortBy
class Translations$profile$sortBy$en {
	Translations$profile$sortBy$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recently Updated'
	String get lastUpdate => 'Recently Updated';

	/// en: 'Alphabetically'
	String get name => 'Alphabetically';
}

// Path: profile.actionButtons
class Translations$profile$actionButtons$en {
	Translations$profile$actionButtons$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Update All'
	String get updateAll => 'Update All';

	/// en: 'Sort'
	String get sort => 'Sort';

	/// en: 'Configuration copied'
	String get copyConfigSuccess => 'Configuration copied';

	/// en: 'Edit Configuration'
	String get editConfig => 'Edit Configuration';
}

// Path: profile.add
class Translations$profile$add$en {
	Translations$profile$add$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New Profile'
	String get buttonText => 'New Profile';

	/// en: 'New Profile'
	String get shortBtnTxt => 'New Profile';

	/// en: 'Choose how to add configuration file'
	String get modalSubtitle => 'Choose how to add configuration file';

	/// en: 'Add From Clipboard'
	String get fromClipboard => 'Add From Clipboard';

	/// en: 'Scan QR Code'
	String get scanQr => 'Scan QR Code';

	late final Translations$profile$add$qrScanner$en qrScanner = Translations$profile$add$qrScanner$en.internal(_root);

	/// en: 'Manual Entry'
	String get manually => 'Manual Entry';

	/// en: 'Manually enter server configuration'
	String get manuallyDescription => 'Manually enter server configuration';

	/// en: 'Add Warp'
	String get addWarp => 'Add Warp';

	/// en: 'Free acceleration with Cloudflare WARP'
	String get warpDescription => 'Free acceleration with Cloudflare WARP';

	/// en: 'Please wait while we register WARP.'
	String get addingWarpMsg => 'Please wait while we register WARP.';

	/// en: 'Adding Profile'
	String get addingProfileMsg => 'Adding Profile';

	/// en: 'Failed to Add Profile'
	String get failureMsg => 'Failed to Add Profile';

	/// en: 'Imported subscription: ${name}'
	String importedNamed({required Object name}) => 'Imported subscription: ${name}';

	/// en: 'The clipboard is empty, nothing to import'
	String get clipboardEmpty => 'The clipboard is empty, nothing to import';

	/// en: 'The link has no subscription address'
	String get deepLinkMissingUrl => 'The link has no subscription address';

	/// en: 'Profile added'
	String get successMsg => 'Profile added';

	/// en: 'Detected automatically (optional)'
	String get nameAutoHint => 'Detected automatically (optional)';
}

// Path: profile.details
class Translations$profile$details$en {
	Translations$profile$details$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Basic Information'
	String get basicInfo => 'Basic Information';

	/// en: 'Subscription Status'
	String get subscriptionStatus => 'Subscription Status';

	/// en: 'Options'
	String get options => 'Options';

	/// en: 'Update Now'
	String get updateNow => 'Update Now';

	/// en: 'Fetch latest configuration from server'
	String get updateNowDescription => 'Fetch latest configuration from server';

	/// en: 'Expire Date'
	String get expireDate => 'Expire Date';

	/// en: 'Unlimited'
	String get unlimited => 'Unlimited';
}

// Path: profile.share
class Translations$profile$share$en {
	Translations$profile$share$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Share'
	String get buttonText => 'Share';

	/// en: 'Share Link'
	String get shareLink => 'Share Link';

	/// en: 'Subscription link copied'
	String get subscriptionLinkCopied => 'Subscription link copied';

	/// en: 'Configuration copied'
	String get configCopied => 'Configuration copied';

	/// en: 'Copy failed'
	String get copyFailed => 'Copy failed';

	/// en: 'Exported to Clipboard'
	String get exportToClipboardSuccess => 'Exported to Clipboard';

	/// en: 'Export Subscription Link to Clipboard'
	String get exportSubLinkToClipboard => 'Export Subscription Link to Clipboard';

	/// en: 'Subscription Link QR Code'
	String get subLinkQrCode => 'Subscription Link QR Code';

	/// en: 'Export Configuration to Clipboard'
	String get exportConfigToClipboard => 'Export Configuration to Clipboard';

	/// en: 'Configuration Copied to Clipboard'
	String get exportConfigToClipboardSuccess => 'Configuration Copied to Clipboard';
}

// Path: profile.overview
class Translations$profile$overview$en {
	Translations$profile$overview$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Currently Using'
	String get currentlyUsing => 'Currently Using';

	/// en: 'Remaining ${days} days'
	String remainingDays({required Object days}) => 'Remaining ${days} days';
}

// Path: profile.update
class Translations$profile$update$en {
	Translations$profile$update$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Update'
	String get buttonTxt => 'Update';

	/// en: 'Update Profile'
	String get tooltip => 'Update Profile';

	/// en: 'Update Subscriptions'
	String get updateSubscriptions => 'Update Subscriptions';

	/// en: 'Failed to Update Profile'
	String get failureMsg => 'Failed to Update Profile';

	/// en: 'Profile Updated Successfully'
	String get successMsg => 'Profile Updated Successfully';

	/// en: 'Failed to Update "${name}"'
	String namedFailureMsg({required Object name}) => 'Failed to Update "${name}"';

	/// en: '"${name}" Updated Successfully'
	String namedSuccessMsg({required Object name}) => '"${name}" Updated Successfully';
}

// Path: profile.edit
class Translations$profile$edit$en {
	Translations$profile$edit$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Edit'
	String get buttonTxt => 'Edit';

	/// en: 'Select Active Profile'
	String get selectActiveTxt => 'Select Active Profile';
}

// Path: profile.delete
class Translations$profile$delete$en {
	Translations$profile$delete$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete'
	String get buttonTxt => 'Delete';

	/// en: 'Delete Profile Permanently?'
	String get confirmationMsg => 'Delete Profile Permanently?';

	/// en: 'Profile Deleted Successfully'
	String get successMsg => 'Profile Deleted Successfully';

	/// en: 'Delete profile'
	String get confirmTitle => 'Delete profile';

	/// en: 'Delete "${name}"? This can't be undone.'
	String namedConfirmMsg({required Object name}) => 'Delete "${name}"? This can\'t be undone.';
}

// Path: profile.save
class Translations$profile$save$en {
	Translations$profile$save$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Save'
	String get buttonText => 'Save';

	/// en: 'Profile Saved Successfully'
	String get successMsg => 'Profile Saved Successfully';

	/// en: 'Failed to Save Profile'
	String get failureMsg => 'Failed to Save Profile';
}

// Path: profile.detailsForm
class Translations$profile$detailsForm$en {
	Translations$profile$detailsForm$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Name'
	String get nameLabel => 'Name';

	/// en: 'Profile Name'
	String get nameHint => 'Profile Name';

	/// en: 'URL'
	String get urlLabel => 'URL';

	/// en: 'Full Config URL'
	String get urlHint => 'Full Config URL';

	/// en: 'Name Is Required'
	String get emptyNameMsg => 'Name Is Required';

	/// en: 'Invalid URL'
	String get invalidUrlMsg => 'Invalid URL';

	/// en: 'Last Update'
	String get lastUpdate => 'Last Update';

	/// en: 'Auto Update'
	String get updateInterval => 'Auto Update';

	/// en: 'Auto Update Interval (in Hours)'
	String get updateIntervalDialogTitle => 'Auto Update Interval (in Hours)';

	/// en: 'User-Agent'
	String get userAgent => 'User-Agent';

	/// en: 'Not Set'
	String get userAgentNotSet => 'Not Set';

	/// en: 'Mux'
	String get mux => 'Mux';

	/// en: 'Multiplex outbound connections to reduce handshake overhead'
	String get muxDescription => 'Multiplex outbound connections to reduce handshake overhead';

	/// en: 'Off'
	String get updateIntervalOff => 'Off';

	/// en: '${hours} h'
	String updateIntervalHours({required Object hours}) => '${hours} h';

	/// en: '${days} d'
	String updateIntervalDays({required Object days}) => '${days} d';
}

// Path: proxies.sortOptions
class Translations$proxies$sortOptions$en {
	Translations$proxies$sortOptions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Default'
	String get unsorted => 'Default';

	/// en: 'Alphabetically'
	String get name => 'Alphabetically';

	/// en: 'By Delay'
	String get delay => 'By Delay';
}

// Path: proxies.delaySemantics
class Translations$proxies$delaySemantics$en {
	Translations$proxies$delaySemantics$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delay: ${delay}ms'
	String result({required Object delay}) => 'Delay: ${delay}ms';

	/// en: 'Delay Test Timeout'
	String get timeout => 'Delay Test Timeout';

	/// en: 'Delay: Testing...'
	String get testing => 'Delay: Testing...';

	/// en: 'Delay: Not tested'
	String get untested => 'Delay: Not tested';

	/// en: 'Delay: ${delay}ms (earlier result)'
	String stale({required Object delay}) => 'Delay: ${delay}ms (earlier result)';
}

// Path: proxies.ipInfoSemantics
class Translations$proxies$ipInfoSemantics$en {
	Translations$proxies$ipInfoSemantics$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'IP Address'
	String get address => 'IP Address';

	/// en: 'Country'
	String get country => 'Country';
}

// Path: settings.backup
class Translations$settings$backup$en {
	Translations$settings$backup$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import Backup'
	String get importConfirmTitle => 'Import Backup';

	/// en: 'This replaces your subscriptions with the ones in the backup and applies the backup's settings. A snapshot of the current data is saved first and restored automatically if the import fails.'
	String get importConfirmMsg => 'This replaces your subscriptions with the ones in the backup and applies the backup\'s settings. A snapshot of the current data is saved first and restored automatically if the import fails.';

	/// en: '${count} subscription(s) on this device are not in the backup and will be removed.'
	String importRemovesMsg({required Object count}) => '${count} subscription(s) on this device are not in the backup and will be removed.';

	/// en: 'Imported ${profiles} subscription(s) and ${settings} setting(s).'
	String reportImported({required Object profiles, required Object settings}) => 'Imported ${profiles} subscription(s) and ${settings} setting(s).';

	/// en: '${count} subscription(s) in the backup were skipped because their data was invalid.'
	String reportDropped({required Object count}) => '${count} subscription(s) in the backup were skipped because their data was invalid.';

	/// en: '${count} setting(s) were skipped; your current values are kept.'
	String reportSettingsSkipped({required Object count}) => '${count} setting(s) were skipped; your current values are kept.';

	/// en: 'WARP was turned off by the import. Re-enable it on this device.'
	String get reportWarpOff => 'WARP was turned off by the import. Re-enable it on this device.';

	/// en: '${count} subscription(s) will be downloaded in the background.'
	String reportBackfill({required Object count}) => '${count} subscription(s) will be downloaded in the background.';

	/// en: 'This is not a valid ClashMiao backup file.'
	String get errInvalidFile => 'This is not a valid ClashMiao backup file.';

	/// en: 'This backup format is not supported.'
	String get errUnsupportedVersion => 'This backup format is not supported.';

	/// en: 'This backup was created by a newer version of the app. Please upgrade the app first.'
	String get errNewerSchema => 'This backup was created by a newer version of the app. Please upgrade the app first.';

	/// en: 'None of the subscriptions in this backup can be imported.'
	String get errNoUsableProfiles => 'None of the subscriptions in this backup can be imported.';

	/// en: 'Could not save a snapshot of the current data, so nothing was changed.'
	String get errSnapshotFailed => 'Could not save a snapshot of the current data, so nothing was changed.';

	/// en: 'A previous import was interrupted and could not be undone yet. Nothing was changed. Restart the app and try again.'
	String get errUnresolvedPrevious => 'A previous import was interrupted and could not be undone yet. Nothing was changed. Restart the app and try again.';

	/// en: 'Import failed. Your previous data has been restored.'
	String get errRolledBack => 'Import failed. Your previous data has been restored.';

	/// en: 'Import failed and the automatic restore did not finish. Restart the app to retry it. A snapshot is saved at ${path}.'
	String errNotRolledBack({required Object path}) => 'Import failed and the automatic restore did not finish. Restart the app to retry it. A snapshot is saved at ${path}.';

	/// en: 'Import failed.'
	String get errFailed => 'Import failed.';

	/// en: 'Another import is already running. Please wait for it to finish.'
	String get errBusy => 'Another import is already running. Please wait for it to finish.';

	/// en: 'Automatic restore did not finish'
	String get recoveryFailedTitle => 'Automatic restore did not finish';

	/// en: 'The last backup import was interrupted and the app could not return your data to its previous state. Some data may be partly imported. Retry the automatic restore now.'
	String get recoveryFailedMsg => 'The last backup import was interrupted and the app could not return your data to its previous state. Some data may be partly imported. Retry the automatic restore now.';

	/// en: 'Interrupted import could not be undone'
	String get recoveryUnrecoverableTitle => 'Interrupted import could not be undone';

	/// en: 'The last backup import was interrupted, but its snapshot is missing or unreadable, so it cannot be undone. Please check your subscriptions and settings.'
	String get recoveryUnrecoverableMsg => 'The last backup import was interrupted, but its snapshot is missing or unreadable, so it cannot be undone. Please check your subscriptions and settings.';

	/// en: 'Retry'
	String get recoveryRetry => 'Retry';

	/// en: 'Close'
	String get recoveryClose => 'Close';

	/// en: 'Your data was restored to before the interrupted import.'
	String get recoveryRetried => 'Your data was restored to before the interrupted import.';

	/// en: 'Export backup'
	String get exportAction => 'Export backup';

	/// en: 'Import backup'
	String get importAction => 'Import backup';

	/// en: 'Couldn't export the backup'
	String get exportFailed => 'Couldn\'t export the backup';

	/// en: 'ClashMiao backup'
	String get shareText => 'ClashMiao backup';
}

// Path: settings.general
class Translations$settings$general$en {
	Translations$settings$general$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'General'
	String get sectionTitle => 'General';

	/// en: 'Language'
	String get locale => 'Language';

	/// en: 'Region'
	String get region => 'Region';

	/// en: 'Helps set default options to bypass domestic addresses'
	String get regionMsg => 'Helps set default options to bypass domestic addresses';

	late final Translations$settings$general$regions$en regions = Translations$settings$general$regions$en.internal(_root);

	/// en: 'Theme Mode'
	String get themeMode => 'Theme Mode';

	late final Translations$settings$general$themeModes$en themeModes = Translations$settings$general$themeModes$en.internal(_root);

	/// en: 'Enable Analytics'
	String get enableAnalytics => 'Enable Analytics';

	/// en: 'Give permission to collect analytics and send crash reports to improve the app'
	String get enableAnalyticsMsg => 'Give permission to collect analytics and send crash reports to improve the app';

	/// en: 'Start At Login'
	String get autoStart => 'Start At Login';

	/// en: 'Start Minimized'
	String get silentStart => 'Start Minimized';

	/// en: 'Open Working Directory'
	String get openWorkingDir => 'Open Working Directory';

	/// en: 'Disable Battery Optimization'
	String get ignoreBatteryOptimizations => 'Disable Battery Optimization';

	/// en: 'Remove Restrictions For Optimal VPN Performance'
	String get ignoreBatteryOptimizationsMsg => 'Remove Restrictions For Optimal VPN Performance';

	/// en: 'Display Speed in Notification'
	String get dynamicNotification => 'Display Speed in Notification';

	/// en: 'Haptic Feedback'
	String get hapticFeedback => 'Haptic Feedback';

	/// en: 'Automatically Check Connection IP'
	String get autoIpCheck => 'Automatically Check Connection IP';

	/// en: 'Allow Auto-Start'
	String get autoStartPermission => 'Allow Auto-Start';

	/// en: 'When enabled, the connection resumes automatically after the phone restarts or the app updates'
	String get autoStartPermissionMsg => 'When enabled, the connection resumes automatically after the phone restarts or the app updates';

	late final Translations$settings$general$autoStartPermissionStatus$en autoStartPermissionStatus = Translations$settings$general$autoStartPermissionStatus$en.internal(_root);
	late final Translations$settings$general$batteryOptimizationStatus$en batteryOptimizationStatus = Translations$settings$general$batteryOptimizationStatus$en.internal(_root);
}

// Path: settings.advanced
class Translations$settings$advanced$en {
	Translations$settings$advanced$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Advanced'
	String get sectionTitle => 'Advanced';

	/// en: 'Debug Mode'
	String get debugMode => 'Debug Mode';

	/// en: 'Restart the app for applying this change'
	String get debugModeMsg => 'Restart the app for applying this change';

	/// en: 'Memory Limit'
	String get memoryLimit => 'Memory Limit';

	/// en: 'Enable if you're experiencing out of memory errors or frequent app crash'
	String get memoryLimitMsg => 'Enable if you\'re experiencing out of memory errors or frequent app crash';

	/// en: 'Reset VPN Profile'
	String get resetTunnel => 'Reset VPN Profile';

	/// en: 'VPN profile reset'
	String get resetTunnelSuccess => 'VPN profile reset';
}

// Path: settings.network
class Translations$settings$network$en {
	Translations$settings$network$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Per-App Line Mode'
	String get perAppProxyPageTitle => 'Per-App Line Mode';

	late final Translations$settings$network$perAppProxyModes$en perAppProxyModes = Translations$settings$network$perAppProxyModes$en.internal(_root);

	/// en: 'Failed to load app list'
	String get perAppProxyLoadFailedMsg => 'Failed to load app list';

	/// en: 'Retry'
	String get perAppProxyRetry => 'Retry';

	/// en: 'No results found'
	String get perAppProxyEmptyMsg => 'No results found';

	/// en: 'Per-app line mode is only supported on Android'
	String get perAppProxyAndroidOnlyMsg => 'Per-app line mode is only supported on Android';

	/// en: 'Show System Apps'
	String get showSystemApps => 'Show System Apps';

	/// en: 'Hide System Apps'
	String get hideSystemApps => 'Hide System Apps';

	/// en: 'Clear Selection'
	String get clearSelection => 'Clear Selection';
}

// Path: settings.geoAssets
class Translations$settings$geoAssets$en {
	Translations$settings$geoAssets$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Routing Assets'
	String get pageTitle => 'Routing Assets';

	/// en: 'GeoIP'
	String get geoip => 'GeoIP';

	/// en: 'GeoSite'
	String get geosite => 'GeoSite';

	/// en: 'Version ${version}'
	String version({required Object version}) => 'Version ${version}';

	/// en: 'File Missing'
	String get fileMissing => 'File Missing';

	/// en: 'Update'
	String get update => 'Update';

	/// en: 'Download'
	String get download => 'Download';

	/// en: 'Failed to Update Asset'
	String get failureMsg => 'Failed to Update Asset';

	/// en: 'Successfully Updated Asset'
	String get successMsg => 'Successfully Updated Asset';

	/// en: 'Add Recommended Assets'
	String get addRecommended => 'Add Recommended Assets';

	/// en: 'Selected Routing Assets' files are missing. Either download them or choose existing ones'
	String get missingGeoAssetsMsg => 'Selected Routing Assets\' files are missing. Either download them or choose existing ones';
}

// Path: settings.groups
class Translations$settings$groups$en {
	Translations$settings$groups$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'General'
	String get general => 'General';

	/// en: 'Connection'
	String get connection => 'Connection';

	/// en: 'Privacy'
	String get privacy => 'Privacy';
}

// Path: tray.status
class Translations$tray$status$en {
	Translations$tray$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connect'
	String get connect => 'Connect';

	/// en: 'Connecting'
	String get connecting => 'Connecting';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Disconnecting'
	String get disconnecting => 'Disconnecting';
}

// Path: failure.clash
class Translations$failure$clash$en {
	Translations$failure$clash$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Error'
	String get unexpected => 'Unexpected Error';

	/// en: 'Clash Error ${reason}'
	String core({required Object reason}) => 'Clash Error ${reason}';
}

// Path: failure.singbox
class Translations$failure$singbox$en {
	Translations$failure$singbox$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Service Error'
	String get unexpected => 'Unexpected Service Error';

	/// en: 'Service is Not Running'
	String get serviceNotRunning => 'Service is Not Running';

	/// en: 'Core Library Not Installed'
	String get coreLibraryMissing => 'Core Library Not Installed';

	/// en: 'Missing Privilege'
	String get missingPrivilege => 'Missing Privilege';

	/// en: 'VPN Mode Requires Administrator Privileges. Either relaunch the app as administrator or change service mode.'
	String get missingPrivilegeMsg => 'VPN Mode Requires Administrator Privileges. Either relaunch the app as administrator or change service mode.';

	/// en: 'Missing Geo Assets'
	String get missingGeoAssets => 'Missing Geo Assets';

	/// en: 'Geo Assets Are Missing. Consider changing active asset or download selected one in the settings.'
	String get missingGeoAssetsMsg => 'Geo Assets Are Missing. Consider changing active asset or download selected one in the settings.';

	/// en: 'Invalid Configuration Options'
	String get invalidConfigOptions => 'Invalid Configuration Options';

	/// en: 'Invalid Configuration'
	String get invalidConfig => 'Invalid Configuration';

	/// en: 'Service Creation Error'
	String get create => 'Service Creation Error';

	/// en: 'Service Startup Error'
	String get start => 'Service Startup Error';

	/// en: 'Service Startup Timed Out'
	String get startTimeout => 'Service Startup Timed Out';

	/// en: 'The core is not responding. Please try again, or restart the app.'
	String get kernelUnresponsive => 'The core is not responding. Please try again, or restart the app.';

	/// en: 'The core exited unexpectedly'
	String get kernelExited => 'The core exited unexpectedly';
}

// Path: failure.connectivity
class Translations$failure$connectivity$en {
	Translations$failure$connectivity$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Failure'
	String get unexpected => 'Unexpected Failure';

	/// en: 'Missing VPN Permission'
	String get missingVpnPermission => 'Missing VPN Permission';

	/// en: 'Missing Notification Permission'
	String get missingNotificationPermission => 'Missing Notification Permission';

	/// en: 'Network Unavailable'
	String get networkUnavailable => 'Network Unavailable';

	/// en: 'Core Error'
	String get core => 'Core Error';

	/// en: 'Lost contact with the background service. Please try again.'
	String get nativeUnresponsive => 'Lost contact with the background service. Please try again.';
}

// Path: failure.profiles
class Translations$failure$profiles$en {
	Translations$failure$profiles$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Error'
	String get unexpected => 'Unexpected Error';

	/// en: 'Profile Not Found'
	String get notFound => 'Profile Not Found';

	/// en: 'No Active Profile'
	String get noActive => 'No Active Profile';

	/// en: 'Invalid Configs'
	String get invalidConfig => 'Invalid Configs';

	/// en: 'Invalid URL'
	String get invalidUrl => 'Invalid URL';

	/// en: 'Please upgrade the app before changing subscriptions'
	String get readOnlyUpgrade => 'Please upgrade the app before changing subscriptions';
}

// Path: failure.connection
class Translations$failure$connection$en {
	Translations$failure$connection$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Connection Error'
	String get unexpected => 'Unexpected Connection Error';

	/// en: 'Connection Timeout'
	String get timeout => 'Connection Timeout';

	/// en: 'Bad Response'
	String get badResponse => 'Bad Response';

	/// en: 'Connection Error'
	String get connectionError => 'Connection Error';

	/// en: 'Bad Certificate'
	String get badCertificate => 'Bad Certificate';
}

// Path: failure.geoAssets
class Translations$failure$geoAssets$en {
	Translations$failure$geoAssets$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unexpected Error'
	String get unexpected => 'Unexpected Error';

	/// en: 'No Update Available'
	String get notUpdate => 'No Update Available';

	/// en: 'Active Geo Asset Not Found'
	String get activeNotFound => 'Active Geo Asset Not Found';
}

// Path: config.serviceModes
class Translations$config$serviceModes$en {
	Translations$config$serviceModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Line Service Only'
	String get proxy => 'Line Service Only';

	/// en: 'Set System Line'
	String get systemProxy => 'Set System Line';

	/// en: 'VPN'
	String get tun => 'VPN';

	/// en: 'VPN Service'
	String get tunService => 'VPN Service';
}

// Path: config.shortServiceModes
class Translations$config$shortServiceModes$en {
	Translations$config$shortServiceModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Line'
	String get proxy => 'Line';

	/// en: 'System Line'
	String get systemProxy => 'System Line';

	/// en: 'VPN'
	String get tun => 'VPN';

	/// en: 'VPN Service'
	String get tunService => 'VPN Service';
}

// Path: config.section
class Translations$config$section$en {
	Translations$config$section$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Route Options'
	String get route => 'Route Options';

	/// en: 'DNS Options'
	String get dns => 'DNS Options';

	/// en: 'Inbound Options'
	String get inbound => 'Inbound Options';

	/// en: 'MultiPlexer'
	String get mux => 'MultiPlexer';

	/// en: 'Outbound Options'
	String get outbound => 'Outbound Options';

	/// en: 'TLS Tricks'
	String get tlsTricks => 'TLS Tricks';

	/// en: 'WARP Options'
	String get warp => 'WARP Options';

	/// en: 'Misc Options'
	String get misc => 'Misc Options';
}

// Path: config.warpConsent
class Translations$config$warpConsent$en {
	Translations$config$warpConsent$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cloudflare WARP Consent'
	String get title => 'Cloudflare WARP Consent';

	/// en: 'Cloudflare WARP is a Free WireGuard VPN Provider. By enabling this option you are agreeing to the Cloudflare WARP's ${tos(Terms of Service)} and ${privacy(Privacy Policy)}.'
	TextSpan description({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [
		const TextSpan(text: 'Cloudflare WARP is a Free WireGuard VPN Provider. By enabling this option you are agreeing to the Cloudflare WARP\'s '),
		tos('Terms of Service'),
		const TextSpan(text: ' and '),
		privacy('Privacy Policy'),
		const TextSpan(text: '.'),
	]);
}

// Path: config.ipv6Modes
class Translations$config$ipv6Modes$en {
	Translations$config$ipv6Modes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Disable'
	String get disable => 'Disable';

	/// en: 'Enable'
	String get enable => 'Enable';

	/// en: 'Preferred'
	String get prefer => 'Preferred';

	/// en: 'Exclusive'
	String get only => 'Exclusive';
}

// Path: config.warpDetourModes
class Translations$config$warpDetourModes$en {
	Translations$config$warpDetourModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Detour Lines Through WARP'
	String get proxyOverWarp => 'Detour Lines Through WARP';

	/// en: 'Detour WARP Through Lines'
	String get warpOverProxy => 'Detour WARP Through Lines';

	/// en: 'Detour WARP Through Lines'
	String get inbound => 'Detour WARP Through Lines';

	/// en: 'Detour Lines Through WARP'
	String get outbound => 'Detour Lines Through WARP';
}

// Path: profile.add.qrScanner
class Translations$profile$add$qrScanner$en {
	Translations$profile$add$qrScanner$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Permission Denied'
	String get permissionDeniedError => 'Permission Denied';

	/// en: 'Something Went Wrong'
	String get unexpectedError => 'Something Went Wrong';

	/// en: 'Flash Light'
	String get torchSemanticLabel => 'Flash Light';

	/// en: 'Camera Facing'
	String get facingSemanticLabel => 'Camera Facing';

	/// en: 'Permission to camera to scan QR Code'
	String get permissionRequest => 'Permission to camera to scan QR Code';
}

// Path: settings.general.regions
class Translations$settings$general$regions$en {
	Translations$settings$general$regions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Iran (ir)'
	String get ir => 'Iran (ir)';

	/// en: 'China (cn)'
	String get cn => 'China (cn)';

	/// en: 'Russia (ru)'
	String get ru => 'Russia (ru)';

	/// en: 'Afghanistan (af)'
	String get af => 'Afghanistan (af)';

	/// en: 'Indonesia (id)'
	String get id => 'Indonesia (id)';

	/// en: 'Other'
	String get other => 'Other';
}

// Path: settings.general.themeModes
class Translations$settings$general$themeModes$en {
	Translations$settings$general$themeModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Follow System Theme'
	String get system => 'Follow System Theme';

	/// en: 'Dark Mode'
	String get dark => 'Dark Mode';

	/// en: 'Light Mode'
	String get light => 'Light Mode';

	/// en: 'Black Mode'
	String get black => 'Black Mode';
}

// Path: settings.general.autoStartPermissionStatus
class Translations$settings$general$autoStartPermissionStatus$en {
	Translations$settings$general$autoStartPermissionStatus$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'On'
	String get allowed => 'On';

	/// en: 'Off'
	String get denied => 'Off';

	/// en: 'Unknown'
	String get unknown => 'Unknown';
}

// Path: settings.general.batteryOptimizationStatus
class Translations$settings$general$batteryOptimizationStatus$en {
	Translations$settings$general$batteryOptimizationStatus$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Exempted'
	String get exempted => 'Exempted';

	/// en: 'Not Exempted'
	String get notExempted => 'Not Exempted';

	/// en: '…'
	String get pending => '…';
}

// Path: settings.network.perAppProxyModes
class Translations$settings$network$perAppProxyModes$en {
	Translations$settings$network$perAppProxyModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'All'
	String get off => 'All';

	/// en: 'Route All Apps Through Line'
	String get offMsg => 'Route All Apps Through Line';

	/// en: 'Route'
	String get include => 'Route';

	/// en: 'Route Only Selected Apps Through Line'
	String get includeMsg => 'Route Only Selected Apps Through Line';

	/// en: 'Bypass'
	String get exclude => 'Bypass';

	/// en: 'Do Not Route Selected Apps Through Line'
	String get excludeMsg => 'Do Not Route Selected Apps Through Line';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'general.appTitle' => 'ClashMiao',
			'general.reset' => 'Reset',
			'general.toggle.enabled' => 'Enabled',
			'general.toggle.disabled' => 'Disabled',
			'general.state.disable' => 'Disable',
			'general.sort' => 'Sort',
			'general.sortBy' => 'Sort by',
			'general.addToClipboard' => 'Add To Clipboard',
			'general.notSet' => 'Not Set',
			'general.agree' => 'Agree',
			'general.decline' => 'Decline',
			'general.unknown' => 'Unknown',
			'general.hidden' => 'Hidden',
			'general.timeout' => 'Timeout',
			'general.clipboardExportSuccessMsg' => 'Added To Clipboard',
			'general.showMore' => 'Show More',
			'general.showLess' => 'Show Less',
			'general.openAppSettings' => 'Open App Settings',
			'general.grantPermission' => 'Grant Permission',
			'general.underDevelopment' => 'Under Development',
			'general.confirm' => 'Confirm',
			'general.close' => 'Close',
			'general.cancel' => 'Cancel',
			'general.clipboardEmpty' => 'Clipboard is empty',
			'general.clipboardReadFailed' => 'Couldn\'t read the clipboard',
			'general.moreOptions' => 'More options',
			'intro.termsAndPolicyCaution' => ({required InlineSpanBuilder tap}) => TextSpan(children: [ const TextSpan(text: 'By Continuing You Agree With '), tap(_root.about.termsAndConditions), ]), 
			'intro.start' => 'Start',
			'home.pageTitle' => 'Home',
			'home.emptyProfilesMsg' => 'No lines yet',
			'home.noActiveProfileMsg' => 'Choose a Profile',
			'home.routingMode.global' => 'Global Proxy',
			'home.routingMode.smart' => 'Smart Routing',
			'home.failedToSwitchMode' => ({required Object error}) => 'Failed to switch mode: ${error}',
			'home.connectionFailedTitle' => 'Connection Failed',
			'home.coreMissingTitle' => 'Core Library Not Found',
			'home.coreMissingMsg' => 'The app could not load its networking core. Connecting is unavailable. Reinstall the app, or make sure the core library file sits next to the executable.',
			'home.degradedTitle' => 'Connected, but no internet access',
			'home.degradedMsg' => 'The tunnel is up but traffic is not getting through. The node may be down — try another node, or disconnect.',
			'home.degradedRetry' => 'Check again',
			'home.egressIp.label' => 'Egress IP',
			'home.egressIp.notConnected' => 'Connect to show egress IP',
			'home.egressIp.tapToCheck' => 'Tap to check egress IP',
			'home.egressIp.checking' => 'Checking…',
			'home.egressIp.failedRetry' => 'Check failed, tap to retry',
			'home.emptyProfilesHint' => 'Tap the button below to get started',
			'home.noActiveProfileTitle' => 'No profile selected',
			'stats.traffic' => 'Traffic',
			'stats.trafficLive' => 'Live Traffic',
			'stats.trafficTotal' => 'Total Traffic',
			'stats.trafficUsage' => 'Traffic Usage',
			'stats.liveSpeed' => 'Live Speed',
			'stats.uplink' => 'Uplink',
			'stats.downlink' => 'Downlink',
			'stats.connection' => 'Connection',
			'stats.speed' => 'Speed',
			'stats.totalTransferred' => 'Total Transferred',
			'stats.sessionTraffic' => 'Session traffic',
			'stats.downloadSpeed' => 'Download speed',
			'profile.overviewPageTitle' => 'Profiles',
			'profile.detailsPageTitle' => 'Profile',
			'profile.activeProfileNameSemanticLabel' => ({required Object name}) => 'Active Profile Name: "${name}".',
			'profile.activeProfileBtnSemanticLabel' => 'View All Profiles',
			'profile.nonActiveProfileBtnSemanticLabel' => ({required Object name}) => 'Select "${name}" as Active Profile',
			'profile.subscription.traffic' => 'Traffic',
			'profile.subscription.updatedTimeAgo' => ({required Object timeago}) => 'Updated ${timeago}',
			'profile.subscription.remainingDuration' => ({required Object duration}) => '${duration} Days Remaining',
			'profile.subscription.remainingTrafficSemanticLabel' => ({required Object consumed, required Object total}) => '${consumed} of ${total} Traffic Consumed',
			'profile.subscription.expired' => 'Expired',
			'profile.subscription.noTraffic' => 'Out of Quota',
			'profile.subscription.upload' => 'Upload',
			'profile.subscription.download' => 'Download',
			'profile.subscription.total' => 'Total Traffic',
			'profile.subscription.expireDate' => 'Expire Date',
			'profile.sortBy.lastUpdate' => 'Recently Updated',
			'profile.sortBy.name' => 'Alphabetically',
			'profile.actionButtons.add' => 'Add',
			'profile.actionButtons.updateAll' => 'Update All',
			'profile.actionButtons.sort' => 'Sort',
			'profile.actionButtons.copyConfigSuccess' => 'Configuration copied',
			'profile.actionButtons.editConfig' => 'Edit Configuration',
			'profile.add.buttonText' => 'New Profile',
			'profile.add.shortBtnTxt' => 'New Profile',
			'profile.add.modalSubtitle' => 'Choose how to add configuration file',
			'profile.add.fromClipboard' => 'Add From Clipboard',
			'profile.add.scanQr' => 'Scan QR Code',
			'profile.add.qrScanner.permissionDeniedError' => 'Permission Denied',
			'profile.add.qrScanner.unexpectedError' => 'Something Went Wrong',
			'profile.add.qrScanner.torchSemanticLabel' => 'Flash Light',
			'profile.add.qrScanner.facingSemanticLabel' => 'Camera Facing',
			'profile.add.qrScanner.permissionRequest' => 'Permission to camera to scan QR Code',
			'profile.add.manually' => 'Manual Entry',
			'profile.add.manuallyDescription' => 'Manually enter server configuration',
			'profile.add.addWarp' => 'Add Warp',
			'profile.add.warpDescription' => 'Free acceleration with Cloudflare WARP',
			'profile.add.addingWarpMsg' => 'Please wait while we register WARP.',
			'profile.add.addingProfileMsg' => 'Adding Profile',
			'profile.add.failureMsg' => 'Failed to Add Profile',
			'profile.add.importedNamed' => ({required Object name}) => 'Imported subscription: ${name}',
			'profile.add.clipboardEmpty' => 'The clipboard is empty, nothing to import',
			'profile.add.deepLinkMissingUrl' => 'The link has no subscription address',
			'profile.add.successMsg' => 'Profile added',
			'profile.add.nameAutoHint' => 'Detected automatically (optional)',
			'profile.details.basicInfo' => 'Basic Information',
			'profile.details.subscriptionStatus' => 'Subscription Status',
			'profile.details.options' => 'Options',
			'profile.details.updateNow' => 'Update Now',
			'profile.details.updateNowDescription' => 'Fetch latest configuration from server',
			'profile.details.expireDate' => 'Expire Date',
			'profile.details.unlimited' => 'Unlimited',
			'profile.share.buttonText' => 'Share',
			'profile.share.shareLink' => 'Share Link',
			'profile.share.subscriptionLinkCopied' => 'Subscription link copied',
			'profile.share.configCopied' => 'Configuration copied',
			'profile.share.copyFailed' => 'Copy failed',
			'profile.share.exportToClipboardSuccess' => 'Exported to Clipboard',
			'profile.share.exportSubLinkToClipboard' => 'Export Subscription Link to Clipboard',
			'profile.share.subLinkQrCode' => 'Subscription Link QR Code',
			'profile.share.exportConfigToClipboard' => 'Export Configuration to Clipboard',
			'profile.share.exportConfigToClipboardSuccess' => 'Configuration Copied to Clipboard',
			'profile.overview.currentlyUsing' => 'Currently Using',
			'profile.overview.remainingDays' => ({required Object days}) => 'Remaining ${days} days',
			'profile.update.buttonTxt' => 'Update',
			'profile.update.tooltip' => 'Update Profile',
			'profile.update.updateSubscriptions' => 'Update Subscriptions',
			'profile.update.failureMsg' => 'Failed to Update Profile',
			'profile.update.successMsg' => 'Profile Updated Successfully',
			'profile.update.namedFailureMsg' => ({required Object name}) => 'Failed to Update "${name}"',
			'profile.update.namedSuccessMsg' => ({required Object name}) => '"${name}" Updated Successfully',
			'profile.edit.buttonTxt' => 'Edit',
			'profile.edit.selectActiveTxt' => 'Select Active Profile',
			'profile.delete.buttonTxt' => 'Delete',
			'profile.delete.confirmationMsg' => 'Delete Profile Permanently?',
			'profile.delete.successMsg' => 'Profile Deleted Successfully',
			'profile.delete.confirmTitle' => 'Delete profile',
			'profile.delete.namedConfirmMsg' => ({required Object name}) => 'Delete "${name}"? This can\'t be undone.',
			'profile.save.buttonText' => 'Save',
			'profile.save.successMsg' => 'Profile Saved Successfully',
			'profile.save.failureMsg' => 'Failed to Save Profile',
			'profile.detailsForm.nameLabel' => 'Name',
			'profile.detailsForm.nameHint' => 'Profile Name',
			'profile.detailsForm.urlLabel' => 'URL',
			'profile.detailsForm.urlHint' => 'Full Config URL',
			'profile.detailsForm.emptyNameMsg' => 'Name Is Required',
			'profile.detailsForm.invalidUrlMsg' => 'Invalid URL',
			'profile.detailsForm.lastUpdate' => 'Last Update',
			'profile.detailsForm.updateInterval' => 'Auto Update',
			'profile.detailsForm.updateIntervalDialogTitle' => 'Auto Update Interval (in Hours)',
			'profile.detailsForm.userAgent' => 'User-Agent',
			'profile.detailsForm.userAgentNotSet' => 'Not Set',
			'profile.detailsForm.mux' => 'Mux',
			'profile.detailsForm.muxDescription' => 'Multiplex outbound connections to reduce handshake overhead',
			'profile.detailsForm.updateIntervalOff' => 'Off',
			'profile.detailsForm.updateIntervalHours' => ({required Object hours}) => '${hours} h',
			'profile.detailsForm.updateIntervalDays' => ({required Object days}) => '${days} d',
			'profile.remoteProfile' => 'Remote Profile',
			'profile.defaultLocalName' => 'Local import',
			'profile.defaultDeepLinkName' => 'Link import',
			'profile.switchFailedMsg' => 'Couldn\'t switch profile',
			'proxies.pageTitle' => 'Lines',
			'proxies.emptyProxiesMsg' => 'No Lines Available',
			'proxies.delayTestTooltip' => 'Test Delay',
			'proxies.sortTooltip' => 'Sort Lines',
			'proxies.checkIp' => 'Check IP',
			'proxies.unknownIp' => 'Unknown IP',
			'proxies.autoSelect' => 'Auto Select',
			'proxies.autoSelectDescription' => 'Auto connect to the fastest node',
			'proxies.sortOptions.unsorted' => 'Default',
			'proxies.sortOptions.name' => 'Alphabetically',
			'proxies.sortOptions.delay' => 'By Delay',
			'proxies.sortModalTitle' => 'Choose sort method',
			'proxies.activeProxySemanticLabel' => 'Active Line',
			'proxies.delaySemantics.result' => ({required Object delay}) => 'Delay: ${delay}ms',
			'proxies.delaySemantics.timeout' => 'Delay Test Timeout',
			'proxies.delaySemantics.testing' => 'Delay: Testing...',
			'proxies.delaySemantics.untested' => 'Delay: Not tested',
			'proxies.delaySemantics.stale' => ({required Object delay}) => 'Delay: ${delay}ms (earlier result)',
			'proxies.ipInfoSemantics.address' => 'IP Address',
			'proxies.ipInfoSemantics.country' => 'Country',
			'proxies.testingDelayInfo' => ({required Object name}) => 'Testing delay for: ${name}',
			'proxies.switchedTo' => ({required Object name}) => 'Switched to ${name}',
			'proxies.switchFailed' => 'Couldn\'t switch the server. Please try again.',
			'proxies.testFailed' => 'Latency test failed. Please try again.',
			'proxies.groupsLoading' => 'Server list is still loading. Please try again in a moment.',
			'proxies.connectBeforeSwitch' => 'Please connect before switching lines',
			'proxies.startDelayTestForGroups' => ({required Object count}) => 'Started delay test for ${count} lines',
			'proxies.delayTestBtn' => 'Delay',
			'proxies.delayTimeout' => 'Timeout',
			'proxies.connectBeforeTest' => 'Connect first to test delay',
			'proxies.lineCount' => ({required Object count}) => '${count} lines',
			'proxies.manualSelect' => 'Manual Select',
			'proxies.autoTest' => 'Auto Test',
			'logs.pageTitle' => 'Logs',
			'logs.filterHint' => 'Filter',
			'logs.allLevelsFilter' => 'All',
			'logs.shareCoreLogs' => 'Share Core Logs',
			'logs.shareAppLogs' => 'Share App Logs',
			'logs.pauseTooltip' => 'Pause',
			'logs.resumeTooltip' => 'Resume',
			'logs.clearTooltip' => 'Clear',
			'logs.logsCleared' => 'Logs cleared',
			'logs.logsCopied' => 'Logs copied',
			'logs.logsUnderDevelopment' => 'Log feature is under development',
			'logs.noLogsWhenDisconnected' => 'Not connected, no logs',
			'logs.loadFailed' => 'Couldn\'t load logs',
			'logs.empty' => 'No logs yet',
			'logs.clearFailed' => 'Couldn\'t clear logs',
			'settings.pageTitle' => 'Settings',
			'settings.requiresRestartMsg' => 'For this to take effect restart the app',
			'settings.experimental' => 'Experimental',
			'settings.experimentalMsg' => 'Features with Experimental flag are still in development and might cause issues.',
			'settings.exportOptions' => 'Copy Anonymous Options to Clipboard',
			'settings.exportAllOptions' => 'Copy All Options to Clipboard',
			'settings.importOptions' => 'Import Options From Clipboard',
			'settings.importOptionsMsg' => 'This will rewrite all config options with provided values. Are you sure?',
			'settings.backup.importConfirmTitle' => 'Import Backup',
			'settings.backup.importConfirmMsg' => 'This replaces your subscriptions with the ones in the backup and applies the backup\'s settings. A snapshot of the current data is saved first and restored automatically if the import fails.',
			'settings.backup.importRemovesMsg' => ({required Object count}) => '${count} subscription(s) on this device are not in the backup and will be removed.',
			'settings.backup.reportImported' => ({required Object profiles, required Object settings}) => 'Imported ${profiles} subscription(s) and ${settings} setting(s).',
			'settings.backup.reportDropped' => ({required Object count}) => '${count} subscription(s) in the backup were skipped because their data was invalid.',
			'settings.backup.reportSettingsSkipped' => ({required Object count}) => '${count} setting(s) were skipped; your current values are kept.',
			'settings.backup.reportWarpOff' => 'WARP was turned off by the import. Re-enable it on this device.',
			'settings.backup.reportBackfill' => ({required Object count}) => '${count} subscription(s) will be downloaded in the background.',
			'settings.backup.errInvalidFile' => 'This is not a valid ClashMiao backup file.',
			'settings.backup.errUnsupportedVersion' => 'This backup format is not supported.',
			'settings.backup.errNewerSchema' => 'This backup was created by a newer version of the app. Please upgrade the app first.',
			'settings.backup.errNoUsableProfiles' => 'None of the subscriptions in this backup can be imported.',
			'settings.backup.errSnapshotFailed' => 'Could not save a snapshot of the current data, so nothing was changed.',
			'settings.backup.errUnresolvedPrevious' => 'A previous import was interrupted and could not be undone yet. Nothing was changed. Restart the app and try again.',
			'settings.backup.errRolledBack' => 'Import failed. Your previous data has been restored.',
			'settings.backup.errNotRolledBack' => ({required Object path}) => 'Import failed and the automatic restore did not finish. Restart the app to retry it. A snapshot is saved at ${path}.',
			'settings.backup.errFailed' => 'Import failed.',
			'settings.backup.errBusy' => 'Another import is already running. Please wait for it to finish.',
			'settings.backup.recoveryFailedTitle' => 'Automatic restore did not finish',
			'settings.backup.recoveryFailedMsg' => 'The last backup import was interrupted and the app could not return your data to its previous state. Some data may be partly imported. Retry the automatic restore now.',
			'settings.backup.recoveryUnrecoverableTitle' => 'Interrupted import could not be undone',
			'settings.backup.recoveryUnrecoverableMsg' => 'The last backup import was interrupted, but its snapshot is missing or unreadable, so it cannot be undone. Please check your subscriptions and settings.',
			'settings.backup.recoveryRetry' => 'Retry',
			'settings.backup.recoveryClose' => 'Close',
			'settings.backup.recoveryRetried' => 'Your data was restored to before the interrupted import.',
			'settings.backup.exportAction' => 'Export backup',
			'settings.backup.importAction' => 'Import backup',
			'settings.backup.exportFailed' => 'Couldn\'t export the backup',
			'settings.backup.shareText' => 'ClashMiao backup',
			'settings.general.sectionTitle' => 'General',
			'settings.general.locale' => 'Language',
			'settings.general.region' => 'Region',
			'settings.general.regionMsg' => 'Helps set default options to bypass domestic addresses',
			'settings.general.regions.ir' => 'Iran (ir)',
			'settings.general.regions.cn' => 'China (cn)',
			'settings.general.regions.ru' => 'Russia (ru)',
			'settings.general.regions.af' => 'Afghanistan (af)',
			'settings.general.regions.id' => 'Indonesia (id)',
			'settings.general.regions.other' => 'Other',
			'settings.general.themeMode' => 'Theme Mode',
			'settings.general.themeModes.system' => 'Follow System Theme',
			'settings.general.themeModes.dark' => 'Dark Mode',
			'settings.general.themeModes.light' => 'Light Mode',
			'settings.general.themeModes.black' => 'Black Mode',
			'settings.general.enableAnalytics' => 'Enable Analytics',
			'settings.general.enableAnalyticsMsg' => 'Give permission to collect analytics and send crash reports to improve the app',
			'settings.general.autoStart' => 'Start At Login',
			'settings.general.silentStart' => 'Start Minimized',
			'settings.general.openWorkingDir' => 'Open Working Directory',
			'settings.general.ignoreBatteryOptimizations' => 'Disable Battery Optimization',
			'settings.general.ignoreBatteryOptimizationsMsg' => 'Remove Restrictions For Optimal VPN Performance',
			'settings.general.dynamicNotification' => 'Display Speed in Notification',
			'settings.general.hapticFeedback' => 'Haptic Feedback',
			'settings.general.autoIpCheck' => 'Automatically Check Connection IP',
			'settings.general.autoStartPermission' => 'Allow Auto-Start',
			'settings.general.autoStartPermissionMsg' => 'When enabled, the connection resumes automatically after the phone restarts or the app updates',
			'settings.general.autoStartPermissionStatus.allowed' => 'On',
			'settings.general.autoStartPermissionStatus.denied' => 'Off',
			'settings.general.autoStartPermissionStatus.unknown' => 'Unknown',
			'settings.general.batteryOptimizationStatus.exempted' => 'Exempted',
			'settings.general.batteryOptimizationStatus.notExempted' => 'Not Exempted',
			'settings.general.batteryOptimizationStatus.pending' => '…',
			'settings.advanced.sectionTitle' => 'Advanced',
			'settings.advanced.debugMode' => 'Debug Mode',
			'settings.advanced.debugModeMsg' => 'Restart the app for applying this change',
			'settings.advanced.memoryLimit' => 'Memory Limit',
			'settings.advanced.memoryLimitMsg' => 'Enable if you\'re experiencing out of memory errors or frequent app crash',
			'settings.advanced.resetTunnel' => 'Reset VPN Profile',
			'settings.advanced.resetTunnelSuccess' => 'VPN profile reset',
			'settings.network.perAppProxyPageTitle' => 'Per-App Line Mode',
			'settings.network.perAppProxyModes.off' => 'All',
			'settings.network.perAppProxyModes.offMsg' => 'Route All Apps Through Line',
			'settings.network.perAppProxyModes.include' => 'Route',
			'settings.network.perAppProxyModes.includeMsg' => 'Route Only Selected Apps Through Line',
			'settings.network.perAppProxyModes.exclude' => 'Bypass',
			'settings.network.perAppProxyModes.excludeMsg' => 'Do Not Route Selected Apps Through Line',
			'settings.network.perAppProxyLoadFailedMsg' => 'Failed to load app list',
			'settings.network.perAppProxyRetry' => 'Retry',
			'settings.network.perAppProxyEmptyMsg' => 'No results found',
			'settings.network.perAppProxyAndroidOnlyMsg' => 'Per-app line mode is only supported on Android',
			'settings.network.showSystemApps' => 'Show System Apps',
			'settings.network.hideSystemApps' => 'Hide System Apps',
			'settings.network.clearSelection' => 'Clear Selection',
			'settings.geoAssets.pageTitle' => 'Routing Assets',
			'settings.geoAssets.geoip' => 'GeoIP',
			'settings.geoAssets.geosite' => 'GeoSite',
			'settings.geoAssets.version' => ({required Object version}) => 'Version ${version}',
			'settings.geoAssets.fileMissing' => 'File Missing',
			'settings.geoAssets.update' => 'Update',
			'settings.geoAssets.download' => 'Download',
			'settings.geoAssets.failureMsg' => 'Failed to Update Asset',
			'settings.geoAssets.successMsg' => 'Successfully Updated Asset',
			'settings.geoAssets.addRecommended' => 'Add Recommended Assets',
			'settings.geoAssets.missingGeoAssetsMsg' => 'Selected Routing Assets\' files are missing. Either download them or choose existing ones',
			'settings.systemProxyEnabled' => 'System proxy enabled',
			'settings.systemProxyDisabled' => 'System proxy disabled (Reconnect to apply)',
			'settings.adminPrivilegesRequired' => 'Administrator privileges required on macOS',
			'settings.portChangeNotice' => 'Port changes require reconnect to apply',
			'settings.groups.general' => 'General',
			'settings.groups.connection' => 'Connection',
			'settings.groups.privacy' => 'Privacy',
			'settings.importOptionsInvalid' => 'The clipboard doesn\'t contain valid settings JSON',
			'settings.importOptionsNothing' => 'No importable settings found',
			'settings.importOptionsDone' => ({required Object count}) => 'Imported ${count} settings',
			'settings.importOptionsPartial' => ({required Object applied, required Object skipped}) => 'Imported ${applied} settings; ${skipped} were skipped because they were invalid',
			'about.pageTitle' => 'About',
			'about.version' => 'Version',
			'about.sourceCode' => 'Source Code',
			'about.telegramChannel' => 'Telegram Channel',
			'about.checkForUpdate' => 'Check For Update',
			'about.privacyPolicy' => 'Privacy Policy',
			'about.termsAndConditions' => 'Terms and Conditions',
			'about.appDescription' => 'A cross-platform proxy client based on sing-box core',
			'about.openSourceLicenses' => 'Open-source licenses',
			'appUpdate.notAvailableMsg' => 'Already Using The Latest Version',
			'appUpdate.dialogTitle' => 'Update Available',
			'appUpdate.updateMsg' => 'A new version of ${_root.general.appTitle} is available. Would you like to update now?',
			'appUpdate.currentVersionLbl' => 'Current Version',
			'appUpdate.newVersionLbl' => 'New Version',
			'appUpdate.updateNowBtnTxt' => 'Update Now',
			'appUpdate.laterBtnTxt' => 'Later',
			'appUpdate.ignoreBtnTxt' => 'Ignore',
			'appUpdate.checkFailedMsg' => 'Couldn\'t check for updates. Check your network and try again.',
			'tray.dashboard' => 'Dashboard',
			'tray.quit' => 'Quit',
			'tray.open' => 'Open',
			'tray.hide' => 'Hide to Tray',
			'tray.status.connect' => 'Connect',
			'tray.status.connecting' => 'Connecting',
			'tray.status.disconnect' => 'Disconnect',
			'tray.status.disconnecting' => 'Disconnecting',
			'tray.proxyModeMenu' => 'Proxy Mode',
			'failure.unexpected' => 'Unexpected Error',
			'failure.clash.unexpected' => 'Unexpected Error',
			'failure.clash.core' => ({required Object reason}) => 'Clash Error ${reason}',
			'failure.singbox.unexpected' => 'Unexpected Service Error',
			'failure.singbox.serviceNotRunning' => 'Service is Not Running',
			'failure.singbox.coreLibraryMissing' => 'Core Library Not Installed',
			'failure.singbox.missingPrivilege' => 'Missing Privilege',
			'failure.singbox.missingPrivilegeMsg' => 'VPN Mode Requires Administrator Privileges. Either relaunch the app as administrator or change service mode.',
			'failure.singbox.missingGeoAssets' => 'Missing Geo Assets',
			'failure.singbox.missingGeoAssetsMsg' => 'Geo Assets Are Missing. Consider changing active asset or download selected one in the settings.',
			'failure.singbox.invalidConfigOptions' => 'Invalid Configuration Options',
			'failure.singbox.invalidConfig' => 'Invalid Configuration',
			'failure.singbox.create' => 'Service Creation Error',
			'failure.singbox.start' => 'Service Startup Error',
			'failure.singbox.startTimeout' => 'Service Startup Timed Out',
			'failure.singbox.kernelUnresponsive' => 'The core is not responding. Please try again, or restart the app.',
			'failure.singbox.kernelExited' => 'The core exited unexpectedly',
			'failure.connectivity.unexpected' => 'Unexpected Failure',
			'failure.connectivity.missingVpnPermission' => 'Missing VPN Permission',
			'failure.connectivity.missingNotificationPermission' => 'Missing Notification Permission',
			'failure.connectivity.networkUnavailable' => 'Network Unavailable',
			'failure.connectivity.core' => 'Core Error',
			'failure.connectivity.nativeUnresponsive' => 'Lost contact with the background service. Please try again.',
			'failure.profiles.unexpected' => 'Unexpected Error',
			'failure.profiles.notFound' => 'Profile Not Found',
			'failure.profiles.noActive' => 'No Active Profile',
			'failure.profiles.invalidConfig' => 'Invalid Configs',
			'failure.profiles.invalidUrl' => 'Invalid URL',
			'failure.profiles.readOnlyUpgrade' => 'Please upgrade the app before changing subscriptions',
			'failure.connection.unexpected' => 'Unexpected Connection Error',
			'failure.connection.timeout' => 'Connection Timeout',
			'failure.connection.badResponse' => 'Bad Response',
			'failure.connection.connectionError' => 'Connection Error',
			'failure.connection.badCertificate' => 'Bad Certificate',
			'failure.geoAssets.unexpected' => 'Unexpected Error',
			'failure.geoAssets.notUpdate' => 'No Update Available',
			'failure.geoAssets.activeNotFound' => 'Active Geo Asset Not Found',
			'failure.withReason' => ({required Object message, required Object reason}) => '${message}: ${reason}',
			'connection.tapToConnect' => 'Tap To Connect',
			'connection.connecting' => 'Connecting',
			'connection.disconnecting' => 'Disconnecting',
			'connection.connected' => 'Connected',
			'connection.reconnect' => 'Reconnect',
			'connection.connectAnyWay' => 'Connect Anyway',
			'connection.experimentalNotice' => 'Experimental Features In Use',
			'connection.experimentalNoticeMsg' => 'You\'ve enabled some experimental features which might affect connection quality and cause unexpected errors. You can always change or reset these options from Config options page.',
			'connection.disableExperimentalNotice' => 'Don\'t Show Again',
			'connection.reconnectMsg' => 'Reconnecting for taking into account the changes...',
			'connection.staleSystemProxyCleaned' => 'Cleaned up system proxy settings left behind by an abnormal exit last time',
			'config.resetBtn' => 'Reset Options',
			'config.serviceMode' => 'Service Mode',
			'config.quickSettings' => 'Quick Settings',
			'config.quickSettingsSubtitle' => 'Customize your connection experience',
			'config.setupWarp' => 'Setup WARP',
			'config.allOptions' => 'All Config Options',
			'config.allAdvancedOptions' => 'All Advanced Options',
			'config.serviceModes.proxy' => 'Line Service Only',
			'config.serviceModes.systemProxy' => 'Set System Line',
			'config.serviceModes.tun' => 'VPN',
			'config.serviceModes.tunService' => 'VPN Service',
			'config.shortServiceModes.proxy' => 'Line',
			'config.shortServiceModes.systemProxy' => 'System Line',
			'config.shortServiceModes.tun' => 'VPN',
			'config.shortServiceModes.tunService' => 'VPN Service',
			'config.section.route' => 'Route Options',
			'config.section.dns' => 'DNS Options',
			'config.section.inbound' => 'Inbound Options',
			'config.section.mux' => 'MultiPlexer',
			'config.section.outbound' => 'Outbound Options',
			'config.section.tlsTricks' => 'TLS Tricks',
			'config.section.warp' => 'WARP Options',
			'config.section.misc' => 'Misc Options',
			'config.warpConsent.title' => 'Cloudflare WARP Consent',
			'config.warpConsent.description' => ({required InlineSpanBuilder tos, required InlineSpanBuilder privacy}) => TextSpan(children: [ const TextSpan(text: 'Cloudflare WARP is a Free WireGuard VPN Provider. By enabling this option you are agreeing to the Cloudflare WARP\'s '), tos('Terms of Service'), const TextSpan(text: ' and '), privacy('Privacy Policy'), const TextSpan(text: '.'), ]), 
			'config.generateWarpConfig' => 'Generate WARP Config',
			'config.missingWarpConfig' => 'Missing WARP Config',
			'config.warpConfigGenerated' => 'WARP Config Generated',
			'config.pageTitle' => 'Config Options',
			'config.logLevel' => 'Log Level',
			'config.blockAds' => 'Block Advertisements',
			'config.resolveDestination' => 'Resolve Destination',
			'config.ipv6Mode' => 'IPv6 Route',
			'config.ipv6Modes.disable' => 'Disable',
			'config.ipv6Modes.enable' => 'Enable',
			'config.ipv6Modes.prefer' => 'Preferred',
			'config.ipv6Modes.only' => 'Exclusive',
			'config.remoteDnsAddress' => 'Remote DNS',
			'config.remoteDnsDomainStrategy' => 'Remote DNS Domain Strategy',
			'config.directDnsAddress' => 'Direct DNS',
			'config.directDnsDomainStrategy' => 'Direct DNS Domain Strategy',
			'config.dnsStrategyBlockedIpv6Off' => ({required Object field}) => 'Not applied: IPv6 routing is disabled but "${field}" is IPv6-only, so no domain could be resolved. Enable IPv6 routing first, or choose another strategy.',
			'config.dnsStrategyBlockedIpv6Only' => ({required Object field}) => 'Not applied: IPv6 routing is IPv6-only but "${field}" is IPv4-only, so no domain could be resolved. Adjust one of them first.',
			'config.dnsStrategyReset' => ({required Object field}) => '"${field}" conflicted with the IPv6 routing setting (no domain could be resolved) and was reset to auto.',
			'config.mixedPort' => 'Mixed Port',
			'config.tproxyPort' => 'Transparent Line Port',
			'config.localDnsPort' => 'Local DNS Port',
			'config.allowConnectionFromLan' => 'Share VPN in Local Network',
			'config.tunImplementation' => 'TUN Implementation',
			'config.mtu' => 'MTU',
			'config.connectionTestUrl' => 'Connection Test URL',
			'config.urlTestInterval' => 'URL Test Interval',
			'config.enableClashApi' => 'Enable Clash API',
			'config.clashApiPort' => 'Clash API Port',
			'config.enableTun' => 'Enable TUN',
			'config.setSystemProxy' => 'Set System Line',
			'config.enableDnsRouting' => 'Enable DNS Routing',
			'config.enableFakeDns' => 'Enable Fake DNS',
			'config.bypassLan' => 'Bypass Lan',
			'config.strictRoute' => 'Strict Route',
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
			'config.setUpWarp' => 'Set up WARP',
			'config.warpNotConfigured' => 'Not configured',
			'config.warpDetourMode' => 'Detour Mode',
			'config.warpDetourModes.proxyOverWarp' => 'Detour Lines Through WARP',
			'config.warpDetourModes.warpOverProxy' => 'Detour WARP Through Lines',
			'config.warpDetourModes.inbound' => 'Detour WARP Through Lines',
			'config.warpDetourModes.outbound' => 'Detour Lines Through WARP',
			'config.warpLicenseKey' => 'License Key',
			'config.warpCleanIp' => 'Clean IP',
			'config.warpPort' => 'Port',
			'config.warpNoise' => 'Noise Count',
			'config.warpNoiseSize' => 'Noise Size',
			'config.warpNoiseMode' => 'Noise Mode',
			'config.warpNoiseDelay' => 'Noise Delay',
			'config.desktopProxyScopeNotice' => 'On desktop, only apps that honor the system proxy are routed through the tunnel. Software that ignores it (some games, CLI tools, apps with their own proxy settings) connects directly and exposes your real IP.',
			'config.serviceModeIosVpnOnly' => 'iOS supports VPN mode only',
			'config.warpGenerating' => 'Generating WARP configuration…',
			'config.warpConfigFailed' => 'Couldn\'t generate the WARP configuration. Please try again later.',
			'config.portRangeError' => 'Port must be between 1024 and 65535',
			'config.dnsEmptyError' => 'DNS address can\'t be empty',
			'config.rangeFormatError' => 'Enter a number or a range, e.g. 10-30',
			'config.urlSchemeError' => 'URL must start with http:// or https://',
			'config.manageRuleAssets' => 'Manage rule sets',
			_ => null,
		};
	}
}
