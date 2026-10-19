package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus

/*
 * 进程级协调器的数据模型（连接生命周期 spec §2、§10）。
 *
 * 纯 Kotlin，不依赖任何 Android 类，[CoordinatorCore] 的 JVM 单测直接使用。
 * 所有 [wire] 字符串与 Dart 侧 `KernelSnapshot.fromJson`（lib/core/box_service/kernel_port.dart）
 * 逐字一致，改动前先看那边。
 */

/** 承载内核的 Service 形态：VPN（TunnelService）或纯代理（PlainService）。 */
enum class ServiceType { Vpn, Proxy }

/** 协调器当前追求的目标。 */
enum class Desired(val wire: String) {
    On("on"),
    Off("off"),
}

/** 谁设定了当前 desired。 */
enum class Source(val wire: String) {
    App("app"),
    Tile("tile"),
    Shortcut("shortcut"),
    Boot("boot"),
    Notification("notification"),
    System("system"),
}

/** 失败码。线上值见 Dart `KernelFailureCode`；原生不发 coreUnavailable。 */
enum class FailureCode(val wire: String) {
    StartTimeout("startTimeout"),
    PermissionDenied("permissionDenied"),
    EmptyConfiguration("emptyConfiguration"),
    CreateService("createService"),
    StartService("startService"),
    StartCommandServer("startCommandServer"),
    KernelUnresponsive("kernelUnresponsive"),
    KernelExited("kernelExited"),
    Unknown("unknown"),
}

/** 启动/重载所需的不可变产物（每请求独立）。 */
data class LaunchSpec(
    val runtimeConfigPath: String,
    val optionsJson: String,
    val profileName: String,
    val configRevision: Long,
)

data class KernelFailure(
    val code: FailureCode,
    val message: String,
    val attempt: Long,
    /** 触发该失败的 Dart 请求序号；与 Dart 请求无关的失败为空。 */
    val seq: Long?,
)

/** 请求被拒绝的原因（线上值与 Dart `RequestRejection` 一致）。 */
enum class RejectReason(val wire: String) {
    Stale("stale"),
    WrongEpoch("wrongEpoch"),
}

data class Receipt(
    val accepted: Boolean,
    val reason: RejectReason?,
    val epoch: String,
    val appliedSeq: Long,
)

/** 权威快照。字段含义见 spec §2；[version] 在纪元内单调，任何字段变化 +1（§10.5）。 */
data class KernelSnapshot(
    val epoch: String,
    val version: Long,
    val status: KernelStatus,
    val attempt: Long,
    val desired: Desired,
    val source: Source,
    val appliedSeq: Long,
    val activeConfigRevision: Long?,
    val lastFailure: KernelFailure?,
    val selectionsReplayNeeded: Boolean,
    /**
     * 原生之后**可能还会读取**的运行时配置文件路径（去重、排序）：当前意图的 spec、
     * 持久化的 spec（磁贴 / 快捷方式 / 开机等外部入口在冷进程里用它）、运行中内核的
     * spec、在途启动任务的 spec。每份快照都带（含 stopped 与 attach 后的首份）。
     * 为空 = 无法确定（例如读取持久化失败）：Dart 必须一个都不删。
     */
    val retainedConfigPaths: List<String>?,
) {
    /** 事件通道 `com.clashmiao.app/kernel.snapshot` 的 JSON map 载荷（计划 P1①）。 */
    fun toWireMap(): Map<String, Any?> = mapOf(
        "epoch" to epoch,
        "version" to version,
        "status" to status.name.lowercase(),
        "attempt" to attempt,
        "desired" to desired.wire,
        "source" to source.wire,
        "appliedSeq" to appliedSeq,
        "activeConfigRevision" to activeConfigRevision,
        "selectionsReplayNeeded" to selectionsReplayNeeded,
        "retainedConfigPaths" to retainedConfigPaths,
        "lastFailure" to lastFailure?.let {
            mapOf(
                "code" to it.code.wire,
                "message" to it.message,
                "attempt" to it.attempt,
                "seq" to it.seq,
            )
        },
    )

    /** 日志用的单行摘要：smoke 时据此核对 epoch/attempt/desired/source/version 序列。 */
    fun logLine(): String =
        "epoch=${epoch.take(8)} version=$version status=${status.name.lowercase()} " +
            "attempt=$attempt desired=${desired.wire} source=${source.wire} " +
            "appliedSeq=$appliedSeq rev=$activeConfigRevision replay=$selectionsReplayNeeded " +
            "retained=${retainedConfigPaths?.map { it.substringAfterLast('/') } ?: "unknown"}" +
            (lastFailure?.let { " failure=${it.code.wire}(attempt=${it.attempt},seq=${it.seq})" } ?: "")
}
