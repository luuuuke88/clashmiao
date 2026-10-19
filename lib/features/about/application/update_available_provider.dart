// 「有新版本可用」的 provider：把 UpdateChecker 的一次性检查接到 Riverpod 上。

import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final updateAvailableProvider = FutureProvider<String?>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final mixedPort = ref.read(networkSettingsProvider).mixedPort;
  return UpdateChecker.checkOnce(prefs, mixedPort: mixedPort);
});
