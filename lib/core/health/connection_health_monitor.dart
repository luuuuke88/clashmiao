import 'dart:async';

import 'package:clashmiao/core/egress_ip/egress_ip_service.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 这条连接实际能不能出网。
///
/// 跟 [BoxStatus] 是两件不同的事：[BoxStatus] 说的是"内核起没起来、隧道建没
/// 建成"，这里说的是"建成的这条隧道，数据包真的送得出去吗"。两者会不一致，
/// 而且不一致的那个组合（已连接 + 出不去）正是最坑用户的情形。
enum ConnectionHealth {
  /// 未连接，或刚连上、还没有任何一次探测结果。
  unknown,

  /// 探测通过：隧道真的能出网。
  healthy,

  /// 连续多次探测失败：结构性连上但真实 egress 不通。
  ///
  /// 这就是"黑洞"——tun 已经 UP 并接管了全设备流量，但流量送不出去，
  /// 表现是整机断网，而 App 界面显示"已连接"。真机上确定性复现过。
  degraded,
}

/// 连接健康探测器。
///
/// ## 为什么需要它
///
/// 这个 App 此前完全没有"连上了但不通"的检测能力：内核报告 `BoxStarted`
/// 之后，UI 就一直显示"已连接"，哪怕真实 egress 早已不通、整机流量被黑洞。
/// 用户看到的是"VPN 连着呢"，实际上什么都打不开。
///
/// ## 探测手段：复用已有的 [EgressIpService]，不新造轮子
///
/// [EgressIpService] 本来就是**走隧道**（`preferTunnel: true`，经本地 mixed
/// 代理端口发出）去查出口 IP 的。它其实已经是一个现成的、语义正确的
/// "隧道通不通"探针，只是原来放错了位置、也没有把失败当回事：
///
/// - 挂在 `HomePage` widget 的生命周期里 → 用户不在首页 / App 在后台时不探测
/// - 只在刚进入 `BoxStarted` 时打一次 → 没有周期性复查，连上之后节点挂掉
///   永远发现不了
/// - 失败被当成"锦上添花没查到"，返回 `EgressIpResult.unknown` 静默吞掉 →
///   从不升级成"这条连接实际不通"
///
/// 这个类把探测能力提到 App 生命周期级，并且给失败一个出口。
///
/// ## 明确不做：不自动拆隧道
///
/// 探测失败只**报告**，绝不自动 stop。这是有意的产品决策，理由是误杀风险：
/// 探测端点被墙、临时抖动、对端限流，都会让一条健康连接被误判。把一条好好
/// 的连接自动断掉，比让用户自己看到提示后决定要糟糕得多。用户拿到明确提示
/// （"已连接，但无法访问网络"）之后，断开还是换节点由他决定。
///
/// ## 不受"自动检查 IP"开关影响
///
/// [EgressIpService.autoCheckEnabled] 是首页那个 IP 展示的用户偏好。健康探测
/// 是安全兜底、不是展示功能，所以这里直接调 [EgressIpService.fetch]（该方法
/// 本身不检查开关，是否调用由调用方决定），不读那个偏好。
/// ## 为什么探测要靠 [start] 显式激活，而不是构造即开跑
///
/// 这个 provider 会被首页的告警条 `ref.watch`，也就是说**渲染一次首页就会
/// 构造一个 monitor**。如果构造函数里就挂上周期定时器，等于"渲染了一个
/// widget 就启动了一个后台任务"——生命周期归属错了：探测该活多久取决于
/// App，不取决于某个页面在不在。实测的直接后果是所有渲染首页的 widget
/// 测试都会因为残留定时器报错。
///
/// 所以：构造函数只保留状态，周期探测由 `main.dart` 的启动流程调 [start]
/// 显式激活。这也跟这个仓库既有的做法一致——`ProfileUpdateScheduler` 的
/// `Timer.periodic` 同样挂在启动流程里，不挂在被 widget watch 的 provider 上。
class ConnectionHealthMonitor extends StateNotifier<ConnectionHealth> {
  ConnectionHealthMonitor(this._ref) : super(ConnectionHealth.unknown);

  final Ref _ref;
  ProviderSubscription<AsyncValue<BoxStatus>>? _sub;
  Timer? _timer;

  /// 开始跟随连接状态做周期探测。由 App 启动流程调用一次，见类文档。
  ///
  /// 重复调用无副作用（幂等）。
  void start() {
    if (_sub != null) return;
    _sub = _ref.listen<AsyncValue<BoxStatus>>(connectionControllerProvider, (
      previous,
      next,
    ) {
      _onStatus(next.valueOrNull);
    }, fireImmediately: true);
  }

  /// 一次探测还在飞的时候不再发起第二次——周期定时器和"刚连上"的首次探测
  /// 可能撞在一起，重复请求既浪费也会让失败计数翻倍。
  bool _probing = false;

  int _consecutiveFailures = 0;

  /// 刚进入已连接状态后，等多久做第一次探测。
  ///
  /// 不能是 0：隧道刚建好那一瞬间路由表/DNS 还在收敛，立刻探大概率假失败。
  static const firstProbeDelay = Duration(seconds: 5);

  /// 之后的探测间隔。
  static const probeInterval = Duration(seconds: 60);

  /// 连续失败多少次才判定 [ConnectionHealth.degraded]。
  ///
  /// 取 3 而不是 1：单次失败太容易是网络抖动/对端限流，误报会让这个提示变成
  /// 狼来了，用户很快就会无视它——那这个功能就白做了。
  static const failureThreshold = 3;

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.close();
    super.dispose();
  }

  void _onStatus(BoxStatus? status) {
    if (status is BoxStarted) {
      if (_timer != null) return; // 已经在监控了，重复的 BoxStarted 不重启周期
      _consecutiveFailures = 0;
      state = ConnectionHealth.unknown;
      _timer = Timer(firstProbeDelay, () {
        unawaited(_probe());
        _timer = Timer.periodic(probeInterval, (_) => unawaited(_probe()));
      });
    } else {
      // 断开 / 正在切换：停止探测并复位。不保留上一次的 degraded——那是上一条
      // 连接的结论，套到下一条连接上就是误报。
      _timer?.cancel();
      _timer = null;
      _consecutiveFailures = 0;
      if (state != ConnectionHealth.unknown) {
        state = ConnectionHealth.unknown;
      }
    }
  }

  /// 立即探测一次（供 UI 上的"重试"入口调用）。
  Future<void> probeNow() => _probe();

  Future<void> _probe() async {
    if (_probing) return;
    _probing = true;
    try {
      final result = await _ref.read(egressIpServiceProvider).fetch();
      if (!mounted) return;
      if (result.isUnknown) {
        _consecutiveFailures++;
        debugPrint(
          '[ConnectionHealth] 探测失败 '
          '$_consecutiveFailures/$failureThreshold',
        );
        if (_consecutiveFailures >= failureThreshold) {
          state = ConnectionHealth.degraded;
        }
      } else {
        _consecutiveFailures = 0;
        state = ConnectionHealth.healthy;
      }
    } finally {
      _probing = false;
    }
  }
}

/// 当前连接的健康度。
///
/// 周期探测**不会**因为有人 watch 这个 provider 就自动开始，必须由 App 启动
/// 流程调一次 [ConnectionHealthMonitor.start]（见 `main.dart`），理由见
/// [ConnectionHealthMonitor] 类文档。这样安排也保证了探测不依赖首页在不在：
/// 用户可能在别的页面、或者 App 在后台的时候连接就变成黑洞了。
final connectionHealthProvider =
    StateNotifierProvider<ConnectionHealthMonitor, ConnectionHealth>((ref) {
      return ConnectionHealthMonitor(ref);
    });
