// 「检查更新」的 provider：把 UpdateChecker 的一次性检查接到 Riverpod 上。
//
// 返回完整的 [UpdateCheckResult] 而不是 `String?`：关于页手动点「检查更新」
// 要区分「已是最新」和「检查失败」，折成 null 就分不开了。

import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final updateCheckProvider = FutureProvider<UpdateCheckResult>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final mixedPort = ref.read(networkSettingsProvider).mixedPort;
  return UpdateChecker.check(prefs, mixedPort: mixedPort);
});
