// 下面的 _Frames 要实现 Riverpod 内部的调度接口（Vsync），只能引内部库。
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod/src/internals.dart'
    show Task, Vsync, InternalProviderContainer;

import '../../_fakes/fake_kernel_port.dart';

/// 模拟平台分组流：同一条 broadcast 流（不回放），平台订阅在监听数 0 → 1 时
/// 建立；原生 command client 连上**当前**内核实例后只推一次当前分组（之后只在
/// 测速结果变化时才推）。
class _NativeLikeGroups extends StubBoxService {
  _NativeLikeGroups() {
    _controller = StreamController<List<OutboundGroup>>.broadcast(
      onListen: () {
        platformListens++;
        // 原生异步连上 command server 后推一次当前分组。
        scheduleMicrotask(() => _controller.add(current));
      },
      onCancel: () => platformCancels++,
    );
  }

  late final StreamController<List<OutboundGroup>> _controller;
  List<OutboundGroup> current = const [];
  int platformListens = 0;
  int platformCancels = 0;

  @override
  Stream<List<OutboundGroup>> watchGroups() => _controller.stream;
}

List<OutboundGroup> _groups(String selected) => [
  OutboundGroup(
    tag: 'select',
    type: 'selector',
    selected: selected,
    items: const [
      OutboundProxy(tag: 'hk', type: 'vless'),
      OutboundProxy(tag: 'sg', type: 'vless'),
    ],
  ),
];

String? _sel(List<OutboundGroup>? g) =>
    g == null || g.isEmpty ? null : g.first.selected;

KernelSnapshot _started(int attempt) => FakeKernelPort.snap(
  version: attempt * 10,
  status: KernelStatus.started,
  attempt: attempt,
  desired: Desired.on,
);

KernelSnapshot _stopped(int attempt) =>
    FakeKernelPort.snap(version: attempt * 10 + 5, attempt: attempt);

/// 模拟 Flutter 下 `ProviderScope`（Riverpod 3）的调度：provider 刷新排到下一帧
/// 执行；等不到帧时（App 在后台不出帧），scope 用两个零时长定时器兜底，照样
/// 执行——与 flutter_riverpod `_UncontrolledProviderScopeState.scheduleRefresh`
/// 一致。释放任务与真实 scope 一样走微任务。
class _Frames implements Vsync {
  _Frames(ProviderContainer container) {
    container.scheduler.flutterVsyncs.add(this);
  }

  Task? _pending;
  Timer? _fallback;

  @override
  void Function()? scheduleRefresh(Task task) {
    _pending = task;
    _fallback?.cancel();
    _fallback = Timer(Duration.zero, () {
      _fallback = Timer(Duration.zero, () {
        _fallback = null;
        _run();
      });
    });
    return () {
      _fallback?.cancel();
      _fallback = null;
      if (identical(_pending, task)) _pending = null;
    };
  }

  @override
  void Function()? scheduleDispose(Task task) {
    var canceled = false;
    scheduleMicrotask(() {
      if (!canceled) task.call();
    });
    return () => canceled = true;
  }

  void _run() {
    final task = _pending;
    _pending = null;
    task?.call();
  }

  /// 出一帧：执行排着的刷新。
  Future<void> frame() async {
    _fallback?.cancel();
    _fallback = null;
    _run();
    await pumpEventQueue();
  }
}

void main() {
  test('后台重启内核：被读到的订阅者先重新订阅、拿走一次性推送，界面那一侧晚到也能拿到新实例的分组（BUG-A）', () async {
    final service = _NativeLikeGroups()..current = _groups('hk');
    final port = FakeKernelPort(initial: _started(1));
    final container = ProviderContainer(
      overrides: [
        boxServiceProvider.overrideWithValue(service),
        kernelPortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    final frames = _Frames(container);

    // 前台：两边都在监听，拿到 attempt 1 的分组。
    container.listen(liveGroupsProvider, (_, _) {});
    container.listen(outboundGroupsProvider, (_, _) {});
    for (var i = 0; i < 3; i++) {
      await frames.frame();
    }
    expect(_sel(container.read(outboundGroupsProvider).value), 'hk');

    // 后台：内核停止 → 新实例启动，期间没有帧。
    port.push(_stopped(1));
    await pumpEventQueue();
    service.current = _groups('sg');
    port.push(_started(2));
    // 只放行微任务（快照送达、刷新排上），不让 scope 的兜底定时器跑：手选重放
    // 赶在界面一侧刷新之前读实时分组，这是两路订阅抢一次性推送的那个时间窗。
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }

    // 手选重放在后台读实时分组：它先重新订阅、拿走这次推送。
    container.read(liveGroupsProvider);
    await pumpEventQueue();
    final live = container.read(liveGroupsProvider).value;
    expect(live?.instance.attempt, 2);
    expect(_sel(live?.groups), 'sg');

    // 回到前台：下一帧里界面一侧才重建。
    for (var i = 0; i < 3; i++) {
      await frames.frame();
    }
    expect(
      _sel(container.read(outboundGroupsProvider).value),
      'sg',
      reason: '界面拿到的必须是新实例的分组，而不是一直等不到',
    );
  });

  test('平台分组流在 Dart 侧只有一个订阅者：每次换实例都取消并重新建立平台订阅', () async {
    final service = _NativeLikeGroups()..current = _groups('hk');
    final port = FakeKernelPort(initial: _started(1));
    final container = ProviderContainer(
      overrides: [
        boxServiceProvider.overrideWithValue(service),
        kernelPortProvider.overrideWithValue(port),
      ],
    );
    addTearDown(container.dispose);
    final frames = _Frames(container);
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await frames.frame();
      }
    }

    container.listen(liveGroupsProvider, (_, _) {});
    container.listen(outboundGroupsProvider, (_, _) {});
    await settle();
    expect(service.platformListens, 1);

    port.push(_stopped(1));
    await settle();
    port.push(_started(2));
    await settle();

    expect(service.platformCancels, 1, reason: '旧实例的平台订阅被取消');
    expect(service.platformListens, 2, reason: '新实例重新建立平台订阅');
  });
}
