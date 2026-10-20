import 'dart:async';

import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

/// 这条连接实际能不能出网。
///
/// 跟连接阶段（[ConnectionPhase]）是两件不同的事：阶段说的是"内核起没起来、
/// 隧道建没建成"，这里说的是"建成的这条隧道，数据包真的送得出去吗"。两者会不一致，
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
/// 这个 App 此前完全没有"连上了但不通"的检测能力：内核报告已连接
/// 之后，UI 就一直显示"已连接"，哪怕真实 egress 早已不通、整机流量被黑洞。
/// 用户看到的是"VPN 连着呢"，实际上什么都打不开。
///
/// ## 探测手段：按连接形态选通路（见 [connectionHealthProbeProvider]）
///
/// VPN 形态从本进程直连探测，流量由系统路由进 tun、经内核 tun 协议栈转发——
/// 其他应用走的就是这条路；没有 tun 的形态经本地 mixed 代理端口
/// （[EgressIpService]）。早先一律经代理端口探测，它绕过 tun：tun 转发全部被拒
/// 时（真机验收 BUG-B）照样成功，「已连接」一直显示正常。
///
/// 此前更早的问题（已修）：探测挂在 `HomePage` 生命周期里、只在刚连上时打
/// 一次、失败被静默吞掉，从不升级成「这条连接实际不通」。
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
  ProviderSubscription<ConnectionSnapshot>? _sub;
  Timer? _timer;

  /// 开始跟随连接状态做周期探测。由 App 启动流程调用一次，见类文档。
  ///
  /// 重复调用无副作用（幂等）。
  void start() {
    if (_sub != null) return;
    _sub = _ref.listen<ConnectionSnapshot>(connectionControllerProvider, (
      previous,
      next,
    ) {
      _onSnapshot(next);
    }, fireImmediately: true);
  }

  /// 调度代次：每次进入已连接、离开已连接、或已连接时换了内核实例都 +1。
  ///
  /// 探测请求、定时器、结果与续排都绑在发起时的代次上：代次一变，在途请求被
  /// 取消，晚到的结果与它要安排的下一次探测一律丢弃——上一条连接的探测不能
  /// 改写这一条的健康度，也不能顶掉这一条的首次探测定时器。
  int _generation = 0;

  /// 当前监控的连接实例 (epoch, attempt)；未在监控时为 null。
  (String?, int?)? _instance;

  /// 本代次在途的探测（同一代次内不并发：周期定时器和「重新检测」可能撞在
  /// 一起，重复请求会让失败计数翻倍）。换代时取消并清空，不挡下一代。
  CancelToken? _inFlight;

  int _consecutiveFailures = 0;

  /// 刚进入已连接状态后，等多久做第一次探测。
  ///
  /// 不能是 0：隧道刚建好那一瞬间路由表/DNS 还在收敛，立刻探大概率假失败。
  static const firstProbeDelay = Duration(seconds: 5);

  /// 之后的探测间隔。
  static const probeInterval = Duration(seconds: 60);

  /// 探测失败、还没到阈值时，下一次探测的间隔：尽快确认是不是真的不通，不让
  /// 「已连接」在一条黑洞连接上挂好几分钟。
  static const retryInterval = Duration(seconds: 10);

  /// 单次探测的整体时限：与连接 / 接收超时无关，到点即取消请求、按失败计。
  /// 对端在接收超时之内一点点地吐数据，或请求压根不返回，都不能让监控停摆。
  static const probeDeadline = Duration(seconds: 8);

  /// 连续失败多少次才判定 [ConnectionHealth.degraded]。
  ///
  /// 取 3 而不是 1：单次失败太容易是网络抖动/对端限流，误报会让这个提示变成
  /// 狼来了，用户很快就会无视它——那这个功能就白做了。
  static const failureThreshold = 3;

  @override
  void dispose() {
    _stop();
    _sub?.close();
    super.dispose();
  }

  void _onSnapshot(ConnectionSnapshot snap) {
    if (snap.phase == ConnectionPhase.connected) {
      final instance = (snap.epoch, snap.attempt);
      // 已经在监控同一个实例：重复的 connected 不重启周期。
      if (_instance == instance) return;
      _stop();
      _instance = instance;
      _schedule(firstProbeDelay, _generation);
    } else if (_instance != null) {
      // 断开 / 正在切换：停止探测并复位。不保留上一次的 degraded——那是上一条
      // 连接的结论，套到下一条连接上就是误报。
      _stop();
    }
  }

  /// 结束当前代次：取消定时器与在途请求，复位计数与健康度。
  void _stop() {
    _generation++;
    _instance = null;
    _timer?.cancel();
    _timer = null;
    _inFlight?.cancel('connection instance changed');
    _inFlight = null;
    _consecutiveFailures = 0;
    if (mounted && state != ConnectionHealth.unknown) {
      state = ConnectionHealth.unknown;
    }
  }

  /// 按 [delay] 安排代次 [gen] 的下一次探测；探测完成后按结果安排再下一次
  /// （失败未到阈值用 [retryInterval]，否则 [probeInterval]）。
  void _schedule(Duration delay, int gen) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      await _probe(gen);
      if (!mounted || gen != _generation) return; // 已换代：不再续排
      final failing =
          _consecutiveFailures > 0 && _consecutiveFailures < failureThreshold;
      _schedule(failing ? retryInterval : probeInterval, gen);
    });
  }

  /// 立即探测一次（供 UI 上的"重试"入口调用）。未在监控连接时什么也不做。
  Future<void> probeNow() async {
    if (_instance == null) return;
    await _probe(_generation);
  }

  Future<void> _probe(int gen) async {
    if (gen != _generation || _inFlight != null) return;
    final token = CancelToken();
    _inFlight = token;
    final ok = await _runWithDeadline(
      _ref.read(connectionHealthProbeProvider),
      token,
    );
    // 换代后晚到的结果：丢弃（在途请求已在换代时取消）。
    if (!mounted || gen != _generation) return;
    _inFlight = null;
    if (!ok) {
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
  }

  /// 跑一次探测，最多等 [probeDeadline]：到点取消 [token] 并按失败计，不管
  /// 探测实现自己会不会响应取消。探测抛出也按失败计。
  static Future<bool> _runWithDeadline(HealthProbe probe, CancelToken token) {
    final result = Completer<bool>();
    final deadline = Timer(probeDeadline, () {
      if (!token.isCancelled) token.cancel('health probe deadline');
      if (!result.isCompleted) result.complete(false);
    });
    Future<bool>.sync(() => probe(token)).then(
      (ok) {
        if (!result.isCompleted) result.complete(ok);
      },
      onError: (Object e, StackTrace _) {
        if (!result.isCompleted) result.complete(false);
      },
    );
    return result.future.whenComplete(deadline.cancel);
  }
}

/// 一次健康探测：这条连接此刻能不能出网。[cancel] 在换代（断开 / 换实例）或
/// 超出 [ConnectionHealthMonitor.probeDeadline] 时被取消，实现应尽快放弃请求。
typedef HealthProbe = Future<bool> Function(CancelToken cancel);

/// 隧道（tun）通路探测的目标：境外站点，智能分流下按规则走代理节点，与出口
/// 探测同一取向（不用 gstatic：它在国内直连名单里，直连在国内不通）。
const kTunnelProbeUrl = 'http://cp.cloudflare.com/generate_204';

/// 按连接形态选探测通路。
///
/// - VPN 形态（内核起 tun，[kernelEnableTun]）：从本进程**直连**（不设代理）
///   请求 [kTunnelProbeUrl]，流量由系统路由进 tun、经内核的 tun 协议栈转发——
///   验证的正是其他应用的流量走的那条路。本 App 始终走隧道：原生分应用规则里
///   白名单模式总会补上本 App、排除模式总会滤掉本 App（`TunnelService`）。
///   只经本地 mixed 代理端口的探测（[EgressIpService]）绕过了 tun：tun 转发
///   全部被拒（真机验收 BUG-B，TCP 约 2 ms 内 connection refused）时它照样
///   成功，「已连接」会一直显示正常。
/// - 仅线路 / 系统代理形态（没有 tun）：经本地代理端口（[EgressIpService]）。
final connectionHealthProbeProvider = Provider<HealthProbe>((ref) {
  return (cancel) async {
    final throughTunnel = kernelEnableTun(ref.read(networkSettingsProvider));
    if (throughTunnel) {
      return probeTunnel(ref.read(tunnelProbeHttpClientProvider)(), cancel);
    }
    final result = await ref.read(egressIpServiceProvider).fetch();
    return !result.isUnknown;
  };
});

/// 经 tun 探测用的 HTTP 客户端工厂：直连（不设代理）、不重试。测试替换适配器。
final tunnelProbeHttpClientProvider = Provider<Dio Function()>((ref) {
  return () => createAppHttpClient(
    preferTunnel: false,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    maxRetries: 0,
  );
});

/// 经 tun 的一次直连探测：只认 [kTunnelProbeUrl] 的 **204**。
///
/// - 不跟随重定向，3xx 一律不通过：门户 / 网关拦截常用 302 把请求带去登录页。
/// - 200 也不通过：返回 200 的登录页、拦截页不能证明目标网络可达。
/// - 不读响应体（流式响应、读完头就判定），慢吞吞吐数据的对端拖不住探测；
///   用完即关闭客户端，连同未读的响应一起释放。
@visibleForTesting
Future<bool> probeTunnel(
  Dio dio,
  CancelToken cancel, {
  String url = kTunnelProbeUrl,
}) async {
  try {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        followRedirects: false,
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode == 204;
  } catch (e) {
    debugPrint('[ConnectionHealth] 经 tun 探测失败: $e');
    return false;
  } finally {
    dio.close(force: true);
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
