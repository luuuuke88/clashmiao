import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络设置 持久化层。
///
/// 这里的字段都会写到 SharedPreferences，并通过 ConnectionController 触发
/// `boxService.changeConfigOptions(...)` 把变更推给 sing-box。
class NetworkSettings {
  const NetworkSettings({
    this.mixedPort = 2080,
    this.setSystemProxy = true,
    this.enableTun = false,
    this.allowConnectionFromLan = false,
    this.enableDnsRouting = true,
    this.remoteDnsAddress = 'udp://1.1.1.1',
  });

  final int mixedPort;
  final bool setSystemProxy;
  final bool enableTun;
  final bool allowConnectionFromLan;
  final bool enableDnsRouting;
  final String remoteDnsAddress;

  NetworkSettings copyWith({
    int? mixedPort,
    bool? setSystemProxy,
    bool? enableTun,
    bool? allowConnectionFromLan,
    bool? enableDnsRouting,
    String? remoteDnsAddress,
  }) {
    return NetworkSettings(
      mixedPort: mixedPort ?? this.mixedPort,
      setSystemProxy: setSystemProxy ?? this.setSystemProxy,
      enableTun: enableTun ?? this.enableTun,
      allowConnectionFromLan:
          allowConnectionFromLan ?? this.allowConnectionFromLan,
      enableDnsRouting: enableDnsRouting ?? this.enableDnsRouting,
      remoteDnsAddress: remoteDnsAddress ?? this.remoteDnsAddress,
    );
  }
}

const _kMixedPort = 'clashmiao_mixed_port';
const _kSetSystemProxy = 'clashmiao_set_system_proxy';
const _kEnableTun = 'clashmiao_enable_tun';
const _kAllowLan = 'clashmiao_allow_lan';
const _kEnableDnsRouting = 'clashmiao_enable_dns_routing';
const _kRemoteDnsAddress = 'clashmiao_remote_dns_address';

final networkSettingsProvider =
    StateNotifierProvider<NetworkSettingsNotifier, NetworkSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return NetworkSettingsNotifier(prefs);
});

class NetworkSettingsNotifier extends StateNotifier<NetworkSettings> {
  NetworkSettingsNotifier(this.prefs) : super(_read(prefs));

  final SharedPreferences prefs;

  static NetworkSettings _read(SharedPreferences p) {
    return NetworkSettings(
      mixedPort: p.getInt(_kMixedPort) ?? 2080,
      setSystemProxy: p.getBool(_kSetSystemProxy) ?? true,
      enableTun: p.getBool(_kEnableTun) ?? false,
      allowConnectionFromLan: p.getBool(_kAllowLan) ?? false,
      enableDnsRouting: p.getBool(_kEnableDnsRouting) ?? true,
      remoteDnsAddress: p.getString(_kRemoteDnsAddress) ?? 'udp://1.1.1.1',
    );
  }

  Future<void> setMixedPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('port out of range: $port');
    }
    state = state.copyWith(mixedPort: port);
    await prefs.setInt(_kMixedPort, port);
  }

  Future<void> setSystemProxy(bool value) async {
    state = state.copyWith(setSystemProxy: value);
    await prefs.setBool(_kSetSystemProxy, value);
  }

  Future<void> setEnableTun(bool value) async {
    state = state.copyWith(enableTun: value);
    await prefs.setBool(_kEnableTun, value);
  }

  Future<void> setAllowLan(bool value) async {
    state = state.copyWith(allowConnectionFromLan: value);
    await prefs.setBool(_kAllowLan, value);
  }

  Future<void> setEnableDnsRouting(bool value) async {
    state = state.copyWith(enableDnsRouting: value);
    await prefs.setBool(_kEnableDnsRouting, value);
  }

  Future<void> setRemoteDnsAddress(String address) async {
    state = state.copyWith(remoteDnsAddress: address);
    await prefs.setString(_kRemoteDnsAddress, address);
  }
}
