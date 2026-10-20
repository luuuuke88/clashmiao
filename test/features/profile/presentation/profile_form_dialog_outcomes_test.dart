import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/scripted_profile_repository.dart';
import '../../../support/toast_pump.dart';

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

/// 添加 / 编辑入口（`doAddProfile` / `doEditProfile`）对存储只读的反馈。
/// 相邻两条 toast 文案必须不同（AppToast 对同一文案 800ms 内去重），所以中间
/// 穿插一条普通失败。
void main() {
  testWidgets('添加与编辑：只读 → 本地化升级提示；普通失败照旧', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    late Future<void> Function() add;
    late Future<void> Function() edit;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: Consumer(
              builder: (context, ref, _) {
                add = () => doAddProfile(context, ref, 'ss://abc@h:1#x');
                edit = () => doEditProfile(context, ref, 'p1', name: '新名字');
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        ),
      ),
    );

    const upgrade = '请升级 App 后再修改订阅';

    repo.addError = const StoreReadOnlyException(9);
    await add();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text(upgrade), findsOneWidget);
    expect(find.textContaining('添加配置文件失败'), findsNothing);
    await _drainToasts(tester);

    repo.editError = Exception('disk full');
    await edit();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text('配置文件保存失败'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing, reason: '原文只进日志');
    await _drainToasts(tester);

    repo.editError = const StoreReadOnlyException(9);
    await edit();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text(upgrade), findsOneWidget);
    await _drainToasts(tester);

    repo.addError = Exception('boom');
    await add();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text('添加配置文件失败'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing, reason: '原文只进日志');
    await _drainToasts(tester);
  });
}
