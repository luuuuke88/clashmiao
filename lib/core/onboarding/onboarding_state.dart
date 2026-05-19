import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _doneKey = 'onboarding_done';

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return prefs.getBool(_doneKey) ?? false;
});

Future<void> markOnboardingDone(SharedPreferences prefs) async {
  await prefs.setBool(_doneKey, true);
}
