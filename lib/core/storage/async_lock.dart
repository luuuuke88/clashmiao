import 'dart:async';

/// 最小的异步互斥锁：把传入的动作按调用顺序串成一条 Future 链，一次只跑一个。
///
/// 用途：订阅存储的「读 → 算 → 写」必须整体串行，否则两个并发写者会各自拿着
/// 旧快照互相覆盖。这里不引入第三方依赖，行为刻意保持最小：
/// - 严格 FIFO；
/// - 动作抛错只让它自己的 Future 失败，不会卡死后面的排队者；
/// - **不可重入**：动作内部再对同一把锁调用 [synchronized] 会死锁，
///   所以锁内的计算一律是同步的纯计算，不允许嵌套。
class AsyncLock {
  Future<void> _tail = Future<void>.value();

  /// 排队执行 [action]，返回它的结果。
  Future<T> synchronized<T>(FutureOr<T> Function() action) {
    final completer = Completer<T>();
    final previous = _tail;
    // 尾巴永远不会以错误结束，下一个排队者因此总能被唤醒。
    _tail = completer.future.then<void>((_) {}, onError: (_) {});
    unawaited(
      previous.then((_) async {
        try {
          completer.complete(await action());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      }),
    );
    return completer.future;
  }
}
