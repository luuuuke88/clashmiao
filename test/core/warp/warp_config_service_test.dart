import 'dart:convert';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/warp/warp_config_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可控行为的假 BoxService —— 只重写 generateWarpConfig，其余方法沿用
/// StubBoxService 的安全空实现（跟 profiles_page_test.dart 里
/// `boxServiceProvider.overrideWithValue(StubBoxService())` 的用法一致，
/// 这里进一步继承自定义返回值 / 异常 / 参数捕获）。
class _FakeWarpBoxService extends StubBoxService {
  _FakeWarpBoxService({this.response, this.error});

  final String? response;
  final Object? error;

  String? capturedLicenseKey;
  String? capturedPreviousAccountId;
  String? capturedPreviousAccessToken;
  int callCount = 0;

  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async {
    callCount++;
    capturedLicenseKey = licenseKey;
    capturedPreviousAccountId = previousAccountId;
    capturedPreviousAccessToken = previousAccessToken;
    if (error != null) throw error!;
    return response;
  }
}

Future<ProviderContainer> _containerWith(_FakeWarpBoxService fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(fake),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  // networkSettingsProvider 依赖 sharedPreferencesProvider.requireValue，
  // 读一次触发 provider 初始化，跟仓库里其它测试的写法一致。
  container.read(networkSettingsProvider);
  return container;
}

void main() {
  group('WarpConfigService.generateAndStore', () {
    test('成功时解析响应并写入 network settings 三个字段', () async {
      final raw = jsonEncode({
        'account-id': 'acc-new',
        'access-token': 'token-new',
        'config': {'private_key': 'pk'},
      });
      final fake = _FakeWarpBoxService(response: raw);
      final container = await _containerWith(fake);

      final credential = await container
          .read(warpConfigServiceProvider)
          .generateAndStore(licenseKey: 'license-1');

      expect(credential.accountId, 'acc-new');
      expect(credential.accessToken, 'token-new');

      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, 'acc-new');
      expect(settings.warpAccessToken, 'token-new');
      expect(jsonDecode(settings.warpWireguardConfig), {'private_key': 'pk'});
    });

    test('把当前已存的账号信息作为 previous-account-id/token 传给 native', () async {
      final fake = _FakeWarpBoxService(
        response: jsonEncode({
          'account-id': 'acc-2',
          'access-token': 'token-2',
          'config': <String, dynamic>{},
        }),
      );
      final container = await _containerWith(fake);
      await container
          .read(networkSettingsProvider.notifier)
          .setWarpAccountId('acc-existing');
      await container
          .read(networkSettingsProvider.notifier)
          .setWarpAccessToken('token-existing');

      await container
          .read(warpConfigServiceProvider)
          .generateAndStore(licenseKey: 'license-x');

      expect(fake.capturedLicenseKey, 'license-x');
      expect(fake.capturedPreviousAccountId, 'acc-existing');
      expect(fake.capturedPreviousAccessToken, 'token-existing');
    });

    test('native 返回 null 时抛 WarpConfigException，且不写入任何字段', () async {
      final fake = _FakeWarpBoxService(response: null);
      final container = await _containerWith(fake);

      await expectLater(
        () => container
            .read(warpConfigServiceProvider)
            .generateAndStore(licenseKey: ''),
        throwsA(isA<WarpConfigException>()),
      );

      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, '');
      expect(settings.warpAccessToken, '');
      expect(settings.warpWireguardConfig, '');
    });

    test('native 返回空字符串时抛 WarpConfigException', () async {
      final fake = _FakeWarpBoxService(response: '   ');
      final container = await _containerWith(fake);

      await expectLater(
        () => container
            .read(warpConfigServiceProvider)
            .generateAndStore(licenseKey: ''),
        throwsA(isA<WarpConfigException>()),
      );
    });

    test('native 返回格式错误的 JSON 时抛 WarpConfigException，不写入字段', () async {
      final fake = _FakeWarpBoxService(response: 'not json');
      final container = await _containerWith(fake);

      await expectLater(
        () => container
            .read(warpConfigServiceProvider)
            .generateAndStore(licenseKey: ''),
        throwsA(isA<WarpConfigException>()),
      );

      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, '');
    });

    test('native 抛 PlatformException 时原样透传，不包装', () async {
      final fake = _FakeWarpBoxService(
        error: PlatformException(code: 'E_KERNEL', message: 'network down'),
      );
      final container = await _containerWith(fake);

      await expectLater(
        () => container
            .read(warpConfigServiceProvider)
            .generateAndStore(licenseKey: ''),
        throwsA(isA<PlatformException>()),
      );
    });

    test('UnsupportedError（桩实现 / 核心库未加载）原样透传', () async {
      // 桌面端加载 core 库失败会回退到 StubBoxService，其
      // generateWarpConfig 会抛 UnsupportedError —— 这里验证编排层
      // 不会把它吞掉或者误包装成别的类型。
      final container = await _containerWith(
        _FakeWarpBoxService(error: UnsupportedError('核心库未加载')),
      );

      await expectLater(
        () => container
            .read(warpConfigServiceProvider)
            .generateAndStore(licenseKey: ''),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
