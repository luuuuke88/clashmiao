import 'dart:io';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:clashmiao/features/assets/state/geo_update_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 暴露一个绑定到当前 container 的真实 [Ref]，跟
/// `test/core/egress_ip/egress_ip_service_test.dart` 建立的模式一致——
/// `GeoUpdateNotifier` 现在需要 `Ref` 来读取 `networkSettingsProvider` 的
/// mixed 端口配置。
final _refExposerProvider = Provider<Ref>((ref) => ref);

/// 构造一个 mixedPort 配置就绪、可以安全传给 `GeoUpdateNotifier` 的 [Ref]。
Future<Ref> _testRef() async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWith((_) => Future.value(sp))],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return container.read(_refExposerProvider);
}

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录，跟
/// test/core/providers/connection_controller_test.dart 里 `_mockPathProvider()`
/// 的写法一致。GeoUpdateNotifier 构造函数里的 `_loadExistingFiles()` 会调
/// getApplicationDocumentsDirectory()，劫持后行为确定（拿到一个保证不存在
/// geoip-cn.srs / geosite-cn.srs 的空目录），不依赖"平台插件缺失时那条
/// try/catch 兜底路径"这种隐式行为。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp(
    'geo_update_notifier_test_',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeoUpdateNotifier.addRecommended', () {
    test(
      '调用后 geoip / geosite 应同时立刻进入 isUpdating:true —— '
      '证明真的触发了 update()，而不是把 state 用 ?? 现有值重建一遍的恒等占位操作',
      () async {
        await _mockPathProvider();
        // 不在这里 dispose：addRecommended() 触发的 update() 在 cdnUrl 为空时
        // 走 catch 分支还会再写一次 state，如果测试结束时提前 dispose()，
        // 那次迟到的写入会撞上 state_notifier 包里 `_debugIsMounted()` 的
        // assert，抛出一个跟本测试无关、可能串到下一个 test 的 StateError。
        // test/core/auto_start/auto_start_notifier_test.dart 里同样不 dispose。
        final notifier = GeoUpdateNotifier(await _testRef());

        // 等构造函数里异步的 _loadExistingFiles() 跑完并让 state 收敛。
        // 它最后会执行一次 `state = next;`（整体替换，不是 spread 合并），
        // 如果这一步跟 addRecommended() 的写入产生竞争，刚设的
        // isUpdating:true 会被这次赋值覆盖掉——所以必须先等它落定，
        // 这里沿用 test/core/auto_start/auto_start_notifier_test.dart
        // 里等待异步构造函数完成的同款 50ms 写法。
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(notifier.state[GeoAssetType.geoip]!.isUpdating, isFalse);
        expect(notifier.state[GeoAssetType.geosite]!.isUpdating, isFalse);

        notifier.addRecommended();

        // update(asset) 把 `state = {...isUpdating:true}` 写在方法体第一个
        // await 之前——按 Dart 语义，调用一个 async 函数时，函数体会同步
        // 执行到第一个 await 为止。所以只要 addRecommended() 是并发触发
        // 两个 update()（unawaited / Future.wait 字面量式启动），而不是
        // `await update(geoip); await update(geosite);` 那种顺序等待，
        // 这里不需要任何 await 就应该能同时看到两个资源都已进入 isUpdating。
        // 如果实现退化成顺序等待，这个断言会先第一个资源变 true，第二个
        // 还停在 false，从而在这里就能抓到。
        expect(notifier.state[GeoAssetType.geoip]!.isUpdating, isTrue);
        expect(notifier.state[GeoAssetType.geosite]!.isUpdating, isTrue);
      },
    );

    test(
      'CDN URL 未配置（当前构建下 GeoAsset.geoip/geosite.cdnUrl 恒为空串）时，'
      '两个资源最终应收敛为 error 状态，而不是卡在 isUpdating 或抛出未捕获异常',
      () async {
        await _mockPathProvider();
        final notifier = GeoUpdateNotifier(await _testRef());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        notifier.addRecommended();
        // GeoUpdateService.update() 在 cdnUrl 为空时，会在发起任何真实网络
        // 请求之前就同步 throw（geo_update_service.dart 里 `if
        // (asset.cdnUrl.isEmpty) throw ...` 在第一个 await 之前），所以不需要
        // 等真实网络超时，很快就能收敛，这里给 50ms 足够冗余。
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(notifier.state[GeoAssetType.geoip]!.isUpdating, isFalse);
        expect(notifier.state[GeoAssetType.geosite]!.isUpdating, isFalse);
        expect(notifier.state[GeoAssetType.geoip]!.error, isNotNull);
        expect(notifier.state[GeoAssetType.geosite]!.error, isNotNull);
      },
    );
  });
}
