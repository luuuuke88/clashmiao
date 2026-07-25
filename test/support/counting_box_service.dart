import 'dart:async';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:rxdart/rxdart.dart';

import 'fake_box_service.dart';

/// 只数调用次数的 [BoxService] 假实现。
///
/// 为什么不能用 `StubBoxService`：`ConnectionController` 会把 stub 识别出来
/// （`_isStub`），`connect()`/`disconnect()` 会直接早返回，`stop()` 根本不会被
/// 调用——想验证"退出时到底有没有停内核"就必须用一个**非 stub** 的实现。
///
/// `watchStatus()` 用 `BehaviorSubject` 而不是 broadcast controller：
/// `ConnectionController` 构造时就订阅它，而测试常常在构造之后立刻 `add()`
/// 一个状态；广播流对"订阅前发出的事件"不补放，会静默丢掉。
class CountingBoxService extends FakeBoxService {
  // 测试替身的生命周期就是单个用例，进程退出即回收；为它引入一套
  // dispose + addTearDown 只会让每个用例多两行噪音。
  // ignore: close_sinks
  final statusStreamController = BehaviorSubject<BoxStatus>();

  int startCalls = 0;
  int stopCalls = 0;
  int restartCalls = 0;

  /// 若非 null，`stop()` 每次都抛它——用来验证"停内核失败也不能卡住退出"。
  Object? stopError;

  /// 为真时 `stop()` **永不返回**——模拟内核完全无响应，用来验证退出路径上的
  /// 超时保护真的生效（不然 App 会卡在退不出去的状态）。
  bool stopHangs = false;

  @override
  Future<void> start(String configPath, {String name = ''}) async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopHangs) return Completer<void>().future;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> restart(String configPath, {String name = ''}) async {
    restartCalls++;
  }

  @override
  Stream<BoxStatus> watchStatus() => statusStreamController.stream;
}
