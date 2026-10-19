// 连接生命周期的内核端口协议：Dart 发送带序号的「期望请求」，内核（Android
// 原生协调器，或其它平台的 Dart 模拟层）回报带版本的「权威快照」。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §2、§10；本文件只有协议与模型，不含任何平台实现。

/// 内核运行状态。与 [BoxStatus] 不同：这是快照的一个字段，不是独立真值。
enum KernelStatus {
  stopped,
  starting,
  started,
  stopping;

  /// 容错解析（大小写不敏感）；未知值返回 null，由调用方决定丢弃整条快照。
  static KernelStatus? tryParse(Object? raw) {
    if (raw is! String) return null;
    final v = raw.toLowerCase();
    for (final s in KernelStatus.values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

/// 协调器当前追求的目标。
enum Desired {
  on,
  off;

  static Desired? tryParse(Object? raw) {
    if (raw is! String) return null;
    final v = raw.toLowerCase();
    for (final d in Desired.values) {
      if (d.name == v) return d;
    }
    return null;
  }
}

/// 谁设定了当前 desired（`notification` = 通知栏停止按钮）。
enum DesiredSource {
  app,
  tile,
  shortcut,
  boot,
  notification,
  system;

  /// 来源只用于副作用判定，不认识的来源按 [system]（最保守：不触觉、不评分）。
  static DesiredSource parse(Object? raw) {
    if (raw is String) {
      final v = raw.toLowerCase();
      for (final s in DesiredSource.values) {
        if (s.name == v) return s;
      }
    }
    return DesiredSource.system;
  }
}

/// 请求原因（原生用于日志与来源判定，不改变语义）。
enum RequestReason { userConnect, userDisconnect, applyConfig, retry }

/// 请求被拒绝的原因（回执中的 `reason`）。
enum RequestRejection {
  /// seq ≤ appliedSeq：已有同序号或更新的请求被处理过。状态未改变。
  stale,

  /// 请求携带的纪元与协调器当前纪元不符。状态未改变；调用方应重新同步。
  wrongEpoch;

  static RequestRejection? tryParse(Object? raw) {
    if (raw is! String) return null;
    for (final r in RequestRejection.values) {
      if (r.name == raw) return r;
    }
    return null;
  }
}

/// 失败码（线上是 [name] 字符串）。未知字符串解析为 [unknown]，原文保留在
/// [KernelFailure.message] 之外不再携带——新增码时三端同步加枚举值。
enum KernelFailureCode {
  /// 协调器内 30 s 启动超时（Android 含 VPN 授权等待）。
  startTimeout,

  /// VPN 授权被拒绝/未授予。
  permissionDenied,

  /// 配置缺失/为空。
  emptyConfiguration,

  /// 创建内核服务实例失败。
  createService,

  /// 启动内核服务失败（含重载失败）。
  startService,

  /// 启动内核命令服务失败。
  startCommandServer,

  /// 单个阻塞调用超过 20 s 仍未返回；状态保持 stopping（如实）。
  kernelUnresponsive,

  /// 内核意外退出。
  kernelExited,

  /// 核心库不可用（桌面 libcore 加载失败的桩实现）。仅 `EmulatedKernelPort`
  /// 产生；原生协调器不会发。
  coreUnavailable,

  /// 不认识的失败码，或平台层错误（message 携带原始错误码与文本）。
  unknown;

  static KernelFailureCode parse(Object? raw) {
    if (raw is String) {
      for (final c in KernelFailureCode.values) {
        if (c.name == raw) return c;
      }
    }
    return KernelFailureCode.unknown;
  }
}

/// 协调器把 desired 置 off 时附带的失败。Dart 永远不自己判定失败。
class KernelFailure {
  const KernelFailure({
    required this.code,
    required this.message,
    required this.attempt,
    this.seq,
  });

  final KernelFailureCode code;
  final String message;

  /// 失败发生时的 attempt。
  final int attempt;

  /// 触发该失败的请求序号；与 Dart 请求无关（内核意外退出等）时为 null。
  final int? seq;

  /// 解析失败返回 null（调用方丢弃该 failure 字段，不丢整条快照）。
  static KernelFailure? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    final attempt = raw['attempt'];
    if (code is! String || attempt is! num) return null;
    final seq = raw['seq'];
    return KernelFailure(
      code: KernelFailureCode.parse(code),
      message: raw['message'] is String ? raw['message'] as String : '',
      attempt: attempt.toInt(),
      seq: seq is num ? seq.toInt() : null,
    );
  }

  Map<String, Object?> toJson() => {
    'code': code.name,
    'message': message,
    'attempt': attempt,
    'seq': seq,
  };

  @override
  bool operator ==(Object other) =>
      other is KernelFailure &&
      other.code == code &&
      other.message == message &&
      other.attempt == attempt &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(code, message, attempt, seq);

  @override
  String toString() =>
      'KernelFailure(${code.name}, attempt=$attempt, seq=$seq)';
}

/// 内核权威快照。
///
/// JSON 载荷（事件通道 `com.clashmiao.app/kernel.snapshot`，`JSONMethodCodec`）：
/// ```
/// {"epoch":"<uuid>","version":12,"status":"started","attempt":3,
///  "desired":"on","source":"app","appliedSeq":7,
///  "activeConfigRevision":5 | null,
///  "selectionsReplayNeeded":false,
///  "lastFailure":{"code":"startTimeout","message":"","attempt":2,"seq":6|null} | null}
/// ```
class KernelSnapshot {
  const KernelSnapshot({
    required this.epoch,
    required this.version,
    required this.status,
    required this.attempt,
    required this.desired,
    required this.source,
    required this.appliedSeq,
    required this.selectionsReplayNeeded,
    this.activeConfigRevision,
    this.lastFailure,
  });

  /// 进程纪元：原生进程（或模拟端口实例）启动时生成的随机 id。变化 = 重启，
  /// Dart 重置所有基线。
  final String epoch;

  /// 纪元内单调递增，任何字段变化 +1。Dart 据此丢弃乱序/重复快照。
  final int version;

  final KernelStatus status;

  /// 纪元内单调递增；每次真正开始一次启动或重载时 +1。
  final int attempt;

  final Desired desired;
  final DesiredSource source;

  /// 协调器已处理到的最后一个 Dart 请求序号（同一纪元内）。
  final int appliedSeq;

  /// 当前运行实例使用的 [LaunchSpec.configRevision]。
  final int? activeConfigRevision;

  /// 协调器在把 desired 置 off 时附带；可跨 attempt 保留，调用方按
  /// `attempt`/`seq` 判断它是否属于自己关心的请求。
  final KernelFailure? lastFailure;

  /// 当前 attempt 是全新内核实例，尚未被 Dart 确认重放手选。
  final bool selectionsReplayNeeded;

  /// 解析事件通道载荷。结构非法（缺字段、未知 status/desired）抛
  /// [FormatException]；调用方应丢弃该条并记日志，不得合成默认值。
  factory KernelSnapshot.fromJson(Map<Object?, Object?> json) {
    final epoch = json['epoch'];
    final version = json['version'];
    final attempt = json['attempt'];
    final appliedSeq = json['appliedSeq'];
    final status = KernelStatus.tryParse(json['status']);
    final desired = Desired.tryParse(json['desired']);
    if (epoch is! String ||
        epoch.isEmpty ||
        version is! num ||
        attempt is! num ||
        appliedSeq is! num ||
        status == null ||
        desired == null) {
      throw FormatException('非法的内核快照载荷: $json');
    }
    final rev = json['activeConfigRevision'];
    return KernelSnapshot(
      epoch: epoch,
      version: version.toInt(),
      status: status,
      attempt: attempt.toInt(),
      desired: desired,
      source: DesiredSource.parse(json['source']),
      appliedSeq: appliedSeq.toInt(),
      activeConfigRevision: rev is num ? rev.toInt() : null,
      lastFailure: KernelFailure.tryFromJson(json['lastFailure']),
      selectionsReplayNeeded: json['selectionsReplayNeeded'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'version': version,
    'status': status.name,
    'attempt': attempt,
    'desired': desired.name,
    'source': source.name,
    'appliedSeq': appliedSeq,
    'activeConfigRevision': activeConfigRevision,
    'selectionsReplayNeeded': selectionsReplayNeeded,
    'lastFailure': lastFailure?.toJson(),
  };

  /// 复制并覆盖字段。`clearFailure` 用于把 lastFailure 置空（与「不传」区分）。
  KernelSnapshot copyWith({
    int? version,
    KernelStatus? status,
    int? attempt,
    Desired? desired,
    DesiredSource? source,
    int? appliedSeq,
    int? activeConfigRevision,
    bool clearActiveConfigRevision = false,
    KernelFailure? lastFailure,
    bool clearFailure = false,
    bool? selectionsReplayNeeded,
  }) {
    return KernelSnapshot(
      epoch: epoch,
      version: version ?? this.version,
      status: status ?? this.status,
      attempt: attempt ?? this.attempt,
      desired: desired ?? this.desired,
      source: source ?? this.source,
      appliedSeq: appliedSeq ?? this.appliedSeq,
      activeConfigRevision: clearActiveConfigRevision
          ? null
          : (activeConfigRevision ?? this.activeConfigRevision),
      lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      selectionsReplayNeeded:
          selectionsReplayNeeded ?? this.selectionsReplayNeeded,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KernelSnapshot &&
      other.epoch == epoch &&
      other.version == version &&
      other.status == status &&
      other.attempt == attempt &&
      other.desired == desired &&
      other.source == source &&
      other.appliedSeq == appliedSeq &&
      other.activeConfigRevision == activeConfigRevision &&
      other.lastFailure == lastFailure &&
      other.selectionsReplayNeeded == selectionsReplayNeeded;

  @override
  int get hashCode => Object.hash(
    epoch,
    version,
    status,
    attempt,
    desired,
    source,
    appliedSeq,
    activeConfigRevision,
    lastFailure,
    selectionsReplayNeeded,
  );

  @override
  String toString() =>
      'KernelSnapshot($epoch v$version ${status.name} attempt=$attempt '
      'desired=${desired.name}/${source.name} appliedSeq=$appliedSeq '
      'rev=$activeConfigRevision replay=$selectionsReplayNeeded '
      'failure=$lastFailure)';
}

/// 启动/重载所需的不可变产物，每个请求独立。
class LaunchSpec {
  const LaunchSpec({
    required this.runtimeConfigPath,
    required this.optionsJson,
    required this.profileName,
    required this.configRevision,
  });

  /// 每请求独立的运行时配置文件（`runtime-config-<seq>.json`）。
  final String runtimeConfigPath;

  /// 内联、不可变的内核选项 JSON。
  final String optionsJson;
  final String profileName;

  /// 设置/模式/订阅的组合版本号；与 [KernelSnapshot.activeConfigRevision]
  /// 不同即触发重载。
  final int configRevision;

  @override
  bool operator ==(Object other) =>
      other is LaunchSpec &&
      other.runtimeConfigPath == runtimeConfigPath &&
      other.optionsJson == optionsJson &&
      other.profileName == profileName &&
      other.configRevision == configRevision;

  @override
  int get hashCode =>
      Object.hash(runtimeConfigPath, optionsJson, profileName, configRevision);
}

/// Dart → 内核的带序号期望请求。
class DesiredRequest {
  DesiredRequest({
    required this.epoch,
    required this.seq,
    required this.desired,
    required this.reason,
    this.launch,
  }) : assert(
         desired == Desired.off || launch != null,
         'desired=on 的请求必须带 LaunchSpec',
       );

  /// 据以分配 [seq] 基线的纪元（来自最近一次被接受的快照）。
  final String epoch;

  /// 在「准备完成、即将调用 request()」时才分配；基线为首个快照的
  /// `appliedSeq + 1`。
  final int seq;
  final Desired desired;
  final RequestReason reason;

  /// `desired == on` 时必填。
  final LaunchSpec? launch;
}

/// 请求回执：只表示「已入队」或「被拒绝」，完成与否看快照。
class RequestReceipt {
  const RequestReceipt({
    required this.accepted,
    required this.epoch,
    required this.appliedSeq,
    this.reason,
  });

  final bool accepted;

  /// 被拒绝时的原因；受理时为 null。
  final RequestRejection? reason;

  /// 内核当前纪元。
  final String epoch;

  /// 处理本请求之后的 appliedSeq（拒绝时即现值，供调用方重设基线）。
  final int appliedSeq;

  @override
  bool operator ==(Object other) =>
      other is RequestReceipt &&
      other.accepted == accepted &&
      other.reason == reason &&
      other.epoch == epoch &&
      other.appliedSeq == appliedSeq;

  @override
  int get hashCode => Object.hash(accepted, reason, epoch, appliedSeq);

  @override
  String toString() =>
      'RequestReceipt(accepted=$accepted, reason=$reason, epoch=$epoch, '
      'appliedSeq=$appliedSeq)';
}

/// 与内核之间的通道健康度，供状态机判断「失联」（spec §10.8）。
enum KernelLink {
  /// 最近一次订阅/查询成功，快照可信。
  connected,

  /// 订阅断开或查询失败，正在退避重试；快照是最后已知值。
  lost,
}

/// 端口自身的失败（桥接不可达、超时、原生拒绝）。不是内核的启动失败——
/// 那类失败只会出现在 [KernelSnapshot.lastFailure]。
class KernelPortException implements Exception {
  const KernelPortException(this.code, [this.message = '']);

  /// `timeout`、`unavailable`，或原生 `FlutterError` 的 code
  /// （如 `unimplemented`、`unsupported`）。
  final String code;
  final String message;

  @override
  String toString() =>
      'KernelPortException($code${message.isEmpty ? '' : ': $message'})';
}

/// [KernelPort.selectOutbound] 的结果。
sealed class SelectOutcome {
  const SelectOutcome();
}

/// 已写入。
class SelectOk extends SelectOutcome {
  const SelectOk();
}

/// `expectedAttempt` 与内核当前 attempt 不符：**未写入**（旧重放应放弃）。
class SelectStale extends SelectOutcome {
  const SelectStale();
}

/// 写入失败（桥接不可达、内核拒绝等）。[code] 是原生错误码或
/// `timeout`/`unavailable`，[message] 为文本。
class SelectFailed extends SelectOutcome {
  const SelectFailed(this.code, [this.message = '']);
  final String code;
  final String message;

  @override
  String toString() => 'SelectFailed($code, $message)';
}

/// 内核端口。Android 由 `PlatformKernelPort`（Pigeon + 事件通道）实现，其它平台
/// 由 `EmulatedKernelPort`（包装 `BoxService`）实现。
///
/// 所有实现必须满足 spec §2 的语义：请求按 seq 顺序处理、后到覆盖先到；
/// 启动失败/超时/意外退出由内核侧把 desired 置 off 并写 `lastFailure`。
abstract interface class KernelPort {
  /// 权威快照。必须在 2 s 内返回，否则抛 [KernelPortException]。
  ///
  /// 每次调用带一个内部查询 token；过期 token（有更新的查询或更新的流快照
  /// 已被接受）的结果被丢弃，此时返回已接受的较新快照。
  Future<KernelSnapshot> current();

  /// 快照流。订阅时先推当前已知值（若已有），之后每次被接受的变化推一次。
  /// 只推通过版本过滤的快照（§10.5）。流本身不报错——失联体现在 [watchLink]。
  Stream<KernelSnapshot> watch();

  /// 通道健康度。订阅时先推当前值。
  Stream<KernelLink> watchLink();

  /// 提交期望请求。回执只表示「已入队/被拒绝」。必须在 2 s 内返回，否则抛
  /// [KernelPortException]。
  Future<RequestReceipt> request(DesiredRequest request);

  /// 确认 [attempt] 的手选重放已完成。幂等：attempt 不是当前值时被忽略。
  Future<void> acknowledgeReplay(int attempt);

  /// 切换出站选择。[expectedAttempt] 非空且与内核当前 attempt 不一致时**不写入**
  /// 并返回 [SelectStale]。不抛异常：失败一律是 [SelectFailed]。
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  });
}
