import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/counting_box_service.dart';

/// 实现了可选生命周期接口的假 service。
class _DisposableFake extends CountingBoxService
    implements DisposableBoxService {
  int disposeCalls = 0;
  Object? disposeError;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeError != null) throw disposeError!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoxService 资源释放契约', () {
    test('容器销毁时，实现了 DisposableBoxService 的实例会被释放', () {
      final fake = _DisposableFake();
      final provider = Provider<BoxService>((ref) {
        wireBoxServiceDisposal(ref, fake);
        return fake;
      });
      final container = ProviderContainer();
      container.read(provider);
      expect(fake.disposeCalls, 0, reason: '前提：还没销毁');

      container.dispose();

      expect(
        fake.disposeCalls,
        1,
        reason:
            '没有释放。FFIBoxService 持有 StreamController 和 ReceivePort，'
            '不释放的话 ReceivePort 对应的 isolate 端口会一直存活',
      );
    });

    test('没实现该接口的实例不受影响（不会因为缺 dispose 而出错）', () {
      final plain = CountingBoxService();
      final provider = Provider<BoxService>((ref) {
        wireBoxServiceDisposal(ref, plain);
        return plain;
      });
      final container = ProviderContainer();
      container.read(provider);
      // 只要销毁不抛就算通过：14 个测试替身都没实现这个可选接口，
      // 这条锁住"可选"这个语义不会哪天被改成必选。
      container.dispose();
    });

    test('dispose 抛异常不能变成没人接的异步异常，也不能阻断销毁', () async {
      final fake = _DisposableFake()..disposeError = StateError('模拟释放失败');
      final provider = Provider<BoxService>((ref) {
        wireBoxServiceDisposal(ref, fake);
        return fake;
      });
      final container = ProviderContainer();
      container.read(provider);

      container.dispose();
      // 让 catchError 那条链跑完。如果异常没被接住，测试框架会在这里报
      // 未处理的异步异常。
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposeCalls, 1);
    });
  });
}
