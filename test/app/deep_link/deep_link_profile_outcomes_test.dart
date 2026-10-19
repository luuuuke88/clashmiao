import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/profile_harness.dart';

final _refProvider = Provider<Ref>((ref) => ref);

String _installUrl(String subUrl, {String? name}) =>
    'clashmiao://install-sub?url=${Uri.encodeComponent(subUrl)}'
    '${name == null ? '' : '&name=${Uri.encodeComponent(name)}'}';

/// 深链导入遇到「订阅刷新被取代」与「存储只读」时的反馈。
void main() {
  late ProfileHarness h;
  late ProviderContainer container;

  setUp(() async {
    h = await ProfileHarness.create(initialPrefs: {'locale': 'zhCn'});
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) async => h.prefs),
        profileRepositoryProvider.overrideWith((_) async => h.repo),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await h.dispose();
  });

  test('重复导入已有订阅，刷新途中该订阅被改动：仍报告导入成功（订阅存在）', () async {
    final a = await h.repo.addByUrl('http://sub.test/a');
    final gate = h.adapter.hold('http://sub.test/a');

    final handling = handleDeepLink(
      Uri.parse(_installUrl('http://sub.test/a', name: '深链名字')),
      container.read(_refProvider),
    );
    await h.adapter.waitForRequests(2);
    await h.repo.editProfile(a.id, newUrl: 'http://sub.test/a2');
    gate.complete();
    await handling;

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportSuccess>());
    expect((result as DeepLinkImportSuccess).profileName, '深链名字');
  });

  test('存储只读（用户降级运行）：深链导入给出本地化的升级提示，而不是异常原文', () async {
    await h.prefs.setInt(kStorageSchemaKey, kCurrentStorageSchema + 1);

    await handleDeepLink(
      Uri.parse(_installUrl('http://sub.test/new')),
      container.read(_refProvider),
    );

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportFailure>());
    expect((result as DeepLinkImportFailure).message, '请升级 App 后再修改订阅');
    expect(h.ids, isEmpty);
    expect(h.strayFiles(), isEmpty);
  });

  test('其它失败仍展示原因，不被误当成只读', () async {
    h.adapter.bodyFor = (url, nth) => throw StateError('network down');
    await handleDeepLink(
      Uri.parse(_installUrl('http://sub.test/new')),
      container.read(_refProvider),
    );
    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportFailure>());
    expect((result as DeepLinkImportFailure).message, isNot('请升级 App 后再修改订阅'));
  });
}
