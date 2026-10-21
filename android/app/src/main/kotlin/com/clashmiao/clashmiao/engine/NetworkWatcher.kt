package com.clashmiao.clashmiao.engine

import android.annotation.TargetApi
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.clashmiao.clashmiao.Application
import com.clashmiao.libcore.core.InterfaceListener
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.ObsoleteCoroutinesApi
import kotlinx.coroutines.channels.actor
import kotlinx.coroutines.runBlocking
import java.net.NetworkInterface
import java.net.UnknownHostException

/**
 * 进程内全局的"当前默认网络"哨兵 —— 也就是流量真正出去用的那张 wifi / 蜂窝。
 *
 * 这层做两件事，合并了原本散在两个对象里的职责：
 *   1. **订阅活动**：[start] / [stop]，按 caller-key 去重。多 caller 同时订阅
 *      只在 ConnectivityManager 注册一次 callback，最后一个 caller 走时再 unregister。
 *   2. **通知内核**：[attachInterfaceListener] 让内核在默认网络变了的时候
 *      重新挑出口（VPN 模式下 sing-box 自己要追踪 underlying network）。
 *
 * `register()` 选用哪个 ConnectivityManager API 完全看 API level —— Android 在
 * 23 / 24 / 26 / 28 / 31 上接 default-network 的方式都不一样，这里把那段挑路逻辑
 * 集中在一个 `when`。
 */
@OptIn(DelicateCoroutinesApi::class, ObsoleteCoroutinesApi::class)
object NetworkWatcher {

    private const val TAG = "engine/NetworkWatcher"

    // === actor 消息 ========================================================
    // 所有状态变更走 actor 顺序处理，避免多线程并发踩到 listeners map。

    private sealed interface Op {
        data class Subscribe(val key: Any, val cb: (Network?) -> Unit) : Op
        data class Unsubscribe(val key: Any) : Op
        data class Resolved(val n: Network) : Op
        class Forget(val out: CompletableDeferred<Network>) : Op
        data class Refreshed(val n: Network) : Op
        data class Lost(val n: Network) : Op
        class FetchCurrent(val out: CompletableDeferred<Network>) : Op
    }

    private val actor = GlobalScope.actor<Op>(Dispatchers.Unconfined) {
        val subs = HashMap<Any, (Network?) -> Unit>()
        var current: Network? = null
        val waiters = ArrayList<CompletableDeferred<Network>>()

        for (op in channel) when (op) {
            is Op.Subscribe -> {
                if (subs.isEmpty()) register()
                subs[op.key] = op.cb
                current?.let(op.cb)
            }
            is Op.Unsubscribe -> {
                val had = subs.remove(op.key) != null
                if (had && subs.isEmpty()) {
                    current = null
                    unregister()
                }
            }
            is Op.Resolved -> {
                current = op.n
                waiters.forEach { it.complete(op.n) }
                waiters.clear()
                subs.values.forEach { it(op.n) }
                // 网络切换后是否重载由协调器决定：它按句柄去重、吸收初始事件并去抖。
                KernelCoordinator.instance.onNetworkResolved(op.n.networkHandle)
            }
            is Op.Refreshed -> if (current == op.n) subs.values.forEach { it(op.n) }
            is Op.Lost -> if (current == op.n) {
                current = null
                subs.values.forEach { it(null) }
            }
            is Op.FetchCurrent -> {
                val c = current
                if (c != null) op.out.complete(c) else waiters += op.out
            }
            // 等待方被取消了：登记不能留下（否则一直没有网络事件时，取消过的等待会越积越多）。
            is Op.Forget -> waiters.remove(op.out)
        }
    }

    // === 内核的 interface listener ========================================

    private val listenerGate = InterfaceListenerGate<InterfaceListener>()

    /**
     * 让内核的 [InterfaceListener] 接到 default-interface 变化通知；传 null 即停止。
     *
     * 换监听 / 停止时按「代次 + 排空屏障」处理（见 [InterfaceListenerGate]）：返回之后旧监听不会再被调用，
     * 也没有仍在途的旧回调，所以新一轮启动不会与旧回调交错；回调期间**不持锁**（内核在回调里可能回头调平台接口）。
     */
    fun attachInterfaceListener(listener: InterfaceListener?) {
        listenerGate.attach(listener)
        if (listener != null) emitInterfaceUpdate(currentNetwork)
    }

    private val watcherKey = Any()
    @Volatile private var currentNetwork: Network? = null

    /** 给 sing-box 模块（KernelHost）调，启用监听。 */
    suspend fun arm() {
        actor.send(Op.Subscribe(watcherKey) { net ->
            currentNetwork = net
            emitInterfaceUpdate(net)
        })
        currentNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Application.connectivity.activeNetwork
        } else {
            blockingFetchCurrent()
        }
    }

    suspend fun disarm() {
        actor.send(Op.Unsubscribe(watcherKey))
    }

    /** Blocking get current network；只供 LocalResolver 在 raw exchange 里同步用。 */
    suspend fun requireCurrent(): Network {
        currentNetwork?.let { return it }
        return blockingFetchCurrent()
    }

    private suspend fun blockingFetchCurrent(): Network = if (fallbackMode) {
        @TargetApi(23)
        Application.connectivity.activeNetwork ?: throw UnknownHostException()
    } else {
        val pending = CompletableDeferred<Network>()
        try {
            actor.send(Op.FetchCurrent(pending))
            pending.await()
        } finally {
            // 被取消（内核放弃这次 DNS 调用）：撤销登记；已经完成的不用管。
            if (!pending.isCompleted) {
                pending.cancel()
                actor.trySend(Op.Forget(pending))
            }
        }
    }

    /** 把 default network 翻译成 (interface-name, index, expensive, constrained) 推给内核。 */
    private fun emitInterfaceUpdate(network: Network?) {
        // 这一轮准备工作（含最多约 1 s 的重试）属于取这一刻的代次：中途换了监听就丢弃，不把旧网络状态喂给新一轮。
        if (!listenerGate.hasListener()) return
        val gen = listenerGate.generation()
        if (network == null) {
            notifyListener(gen, "", -1, expensive = false, constrained = false)
            return
        }
        val name = Application.connectivity.getLinkProperties(network)?.interfaceName ?: return
        val expensive = Application.connectivity.getNetworkCapabilities(network)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
        // 偶尔 NetworkInterface.getByName 比 LinkProperties 慢一拍，最多 ~1s 重试。
        repeat(10) {
            val ifc = runCatching { NetworkInterface.getByName(name) }.getOrNull()
            if (ifc != null) {
                notifyListener(gen, ifc.name, ifc.index, expensive, constrained = false)
                return
            }
            Thread.sleep(100)
        }
    }

    private fun notifyListener(gen: Long, name: String, index: Int, expensive: Boolean, constrained: Boolean) {
        listenerGate.dispatch(gen) { it.update(name, index, expensive, constrained) }
    }

    // === Android ConnectivityManager 注册路径（按 API level 分叉） ============

    private var fallbackMode = false

    private val request: NetworkRequest by lazy {
        NetworkRequest.Builder().apply {
            addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            if (Build.VERSION.SDK_INT == 23) {
                // OEM bug workaround on API 23
                removeCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                removeCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
            }
        }.build()
    }
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private object SystemCallback : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            runBlocking { actor.send(Op.Resolved(network)) }
        }

        override fun onCapabilitiesChanged(network: Network, c: NetworkCapabilities) {
            runBlocking { actor.send(Op.Refreshed(network)) }
        }

        override fun onLost(network: Network) {
            runBlocking { actor.send(Op.Lost(network)) }
        }
    }

    private fun register() {
        val cm = Application.connectivity
        when {
            Build.VERSION.SDK_INT >= 31 -> {
                @TargetApi(31)
                cm.registerBestMatchingNetworkCallback(request, SystemCallback, mainHandler)
            }
            Build.VERSION.SDK_INT >= 28 -> {
                // requestNetwork 不是 listen — 强制选 default
                cm.requestNetwork(request, SystemCallback, mainHandler)
            }
            Build.VERSION.SDK_INT >= 26 -> {
                cm.registerDefaultNetworkCallback(SystemCallback, mainHandler)
            }
            Build.VERSION.SDK_INT >= 24 -> {
                cm.registerDefaultNetworkCallback(SystemCallback)
            }
            else -> try {
                fallbackMode = false
                cm.requestNetwork(request, SystemCallback)
            } catch (_: RuntimeException) {
                // API 23 OEM 上偶尔 throw，退化成 activeNetwork 直读
                fallbackMode = true
            }
        }
    }

    private fun unregister() {
        runCatching { Application.connectivity.unregisterNetworkCallback(SystemCallback) }
    }
}
