package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus

/**
 * 让一条流命令订阅（分组 / 统计）跟随**当前**内核实例。纯 Kotlin，JVM 可测。
 *
 * libbox 的 command client 连上的是某一个内核实例的 command server；实例停止后它只收到
 * `disconnected`，不会自己连到下一个实例。以前完全靠 Dart 侧取消再监听（EventChannel 的
 * onCancel / onListen）来重连——Dart 侧什么时候重建订阅取决于界面有没有帧、有几个监听者，
 * 原生不能把「连到新实例」押在这上面。
 *
 * 用法：订阅开始时 [attach]（传当时的快照，可能为 null）并立即连接一次；之后每份快照交给
 * [onSnapshot]，它在出现一个**新的已启动实例**（epoch 或 attempt 不同）时返回 true，调用方据此
 * 重连。同一实例的后续快照（版本号变化、重放确认等）不会触发重连。
 */
class InstanceFollower {
    private var current: Pair<String, Long>? = null

    /** 订阅开始：记下此刻已在运行的实例（没有就是 null，之后第一个启动的实例会触发重连）。 */
    fun attach(snapshot: KernelSnapshot?) {
        current = snapshot?.takeIf { it.status == KernelStatus.Started }?.let { it.epoch to it.attempt }
    }

    /** 返回 true = 出现了新的已启动实例，调用方应重新连接 command client。 */
    fun onSnapshot(snapshot: KernelSnapshot): Boolean {
        if (snapshot.status != KernelStatus.Started) return false
        val key = snapshot.epoch to snapshot.attempt
        if (key == current) return false
        current = key
        return true
    }
}
