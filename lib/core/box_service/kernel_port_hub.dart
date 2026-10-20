import 'dart:async';

/// [KernelPort] 两个实现共用的「最新值 + 多订阅者」小工具。
///
/// - 每次 [stream] 调用返回一条独立的单订阅流；订阅时先推 [latest]（若有），
///   之后每次 [add] 推一次。
/// - 第一个订阅者出现时回调 [onFirstListener]，最后一个离开时回调
///   [onNoListeners]——PlatformKernelPort 用它按需开关原生订阅。
///
/// 值类型 `T` 不限；快照与链路状态各用一个实例。
class KernelPortHub<T> {
  KernelPortHub({this.onFirstListener, this.onNoListeners});

  final void Function()? onFirstListener;
  final void Function()? onNoListeners;

  final Set<StreamController<T>> _controllers = {};
  T? _latest;
  bool _hasLatest = false;

  /// 最近一次 [add] 的值；无则 null。
  T? get latest => _hasLatest ? _latest : null;

  bool get hasListeners => _controllers.isNotEmpty;

  Stream<T> stream() {
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        final first = _controllers.isEmpty;
        _controllers.add(controller);
        if (_hasLatest) controller.add(_latest as T);
        if (first) onFirstListener?.call();
      },
      onCancel: () {
        _controllers.remove(controller);
        if (_controllers.isEmpty) onNoListeners?.call();
      },
    );
    return controller.stream;
  }

  void add(T value) {
    _latest = value;
    _hasLatest = true;
    for (final c in _controllers.toList()) {
      c.add(value);
    }
  }

  /// 清空最新值（订阅整体断开后，旧值不再可信，不应回放给下一批订阅者）。
  void clearLatest() {
    _latest = null;
    _hasLatest = false;
  }

  /// 关闭所有订阅流。
  Future<void> close() async {
    final all = _controllers.toList();
    _controllers.clear();
    for (final c in all) {
      await c.close();
    }
  }
}
