import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/temp_dirs.dart';

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录（同
/// test/core/providers/connection_controller_test.dart 里的写法）。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp('box_log_stream_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('boxLogStreamProvider is autoDispose', () {
    expect(
      boxLogStreamProvider,
      isA<AutoDisposeStreamProvider<List<String>>>(),
    );
  });

  test('离开日志页（最后一个 listener 消失）后，桌面端文件轮询循环应该真正停止，'
      '不应该继续调度新的定时器', () async {
    final tmp = await _mockPathProvider();
    addTearDown(() => deleteTempDirBestEffort(tmp));
    final logFile = File('${tmp.path}/box.log');
    await logFile.writeAsString('line1');

    // 只用这个 zone 包住 provider 的创建/首次 listen——box.log 轮询循环
    // 内部所有 Future.delayed 创建的 Timer 永远绑定在"生成器函数开始
    // 执行时"所在的 zone 上，跟测试代码之后在哪个 zone 里 await 无关。
    // 这样测试自己的等待（_waitUntil / 最后的长等待）就不会污染计数。
    var timerCount = 0;
    final zoneSpec = ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timerCount++;
        return parent.createTimer(zone, duration, callback);
      },
    );

    late ProviderContainer container;
    final values = <List<String>>[];
    late ProviderSubscription<AsyncValue<List<String>>> sub;
    runZoned(() {
      container = ProviderContainer();
      sub = container.listen(boxLogStreamProvider, (_, next) {
        next.whenData(values.add);
      });
    }, zoneSpecification: zoneSpec);
    addTearDown(container.dispose);

    await _waitUntil(() => values.isNotEmpty);
    expect(values.single, ['line1']);

    // 模拟用户离开日志页：最后一个 listener 消失。
    sub.close();
    await container.pump();

    final timerCountAtDispose = timerCount;
    // 等待超过一个完整轮询间隔（1.5s），文件内容保持不变——这正是
    // async* 的"取消时在下一个 yield 处停止"机制救不了的场景：只要
    // 内容不变，循环体里就不会再走到任何 yield，只能靠显式的
    // disposed 标记才能让循环真正 return。
    await Future<void>.delayed(const Duration(milliseconds: 3200));

    expect(
      timerCount,
      timerCountAtDispose,
      reason:
          'provider 被 dispose 后，桌面端轮询循环应该在下一次 tick 就 return，'
          '不应该再调度新的 Future.delayed 定时器（否则即使没人监听也会'
          '永远消耗 CPU 和文件 IO）',
    );
  });
}
