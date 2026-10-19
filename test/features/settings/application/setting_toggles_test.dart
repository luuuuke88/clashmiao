import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/features/settings/application/setting_toggles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const spec = (key: 'clashmiao_auto_ip_check', defaultValue: true);

  Future<(ProviderContainer, SharedPreferences)> setup(
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWith((ref) async => prefs)],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    return (container, prefs);
  }

  test('没存过用默认值；存过用存的值', () async {
    var (container, _) = await setup({});
    expect(container.read(boolPreferenceProvider(spec)), isTrue);
    (container, _) = await setup({'clashmiao_auto_ip_check': false});
    expect(container.read(boolPreferenceProvider(spec)), isFalse);
  });

  test('update 写进偏好并更新状态', () async {
    final (container, prefs) = await setup({});
    final sub = container.listen(boolPreferenceProvider(spec), (_, _) {});
    await container.read(boolPreferenceProvider(spec).notifier).update(false);
    expect(sub.read(), isFalse);
    expect(prefs.getBool('clashmiao_auto_ip_check'), false);
  });

  test('偏好在别处被改（备份恢复）后，失效整个 family 才会重读', () async {
    final (container, prefs) = await setup({});
    const other = (key: 'clashmiao_haptic_feedback', defaultValue: true);
    final a = container.listen(boolPreferenceProvider(spec), (_, _) {});
    final b = container.listen(boolPreferenceProvider(other), (_, _) {});
    await prefs.setBool('clashmiao_auto_ip_check', false);
    await prefs.setBool('clashmiao_haptic_feedback', false);
    // 没失效前读到的是缓存。
    expect(a.read(), isTrue);
    expect(b.read(), isTrue);

    container.invalidate(boolPreferenceProvider);
    expect(a.read(), isFalse);
    expect(b.read(), isFalse);
  });
}
