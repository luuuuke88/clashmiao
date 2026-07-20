package com.clashmiao.clashmiao.engine

import android.os.RemoteCallbackList
import androidx.lifecycle.MutableLiveData
import com.clashmiao.clashmiao.IService
import com.clashmiao.clashmiao.IServiceCallback
import com.clashmiao.clashmiao.core.KernelStatus
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * AIDL [IService] 的 Service-side 实现 —— Activity 通过 bindService 拿到这个
 * binder 后注册 callback，状态 / alert / log 通过 [fanOut] 广播给所有 callback。
 *
 * 维持外部状态的 LiveData 由 [KernelHost] 持有；这里只做 IPC fan-out。
 * 重命名背景：原本叫 ServiceBinder，跟 Android Service.onBind 返回的 IBinder
 * 概念太接近，叫 KernelBinder 表意更明确 —— "把内核状态绑给所有订阅者"。
 */
@OptIn(DelicateCoroutinesApi::class)
class KernelBinder(status: MutableLiveData<KernelStatus>) : IService.Stub() {

    private val callbacks = RemoteCallbackList<IServiceCallback>()
    private val fanOutLock = Mutex()

    init {
        // 把 LiveData 的状态变化镜像到所有 IPC callback +
        // cache 最近 ordinal 给同步 [getStatus] 用（避免读 LiveData.value 跨线程）。
        status.observeForever { snapshot ->
            currentStatusOrdinal = snapshot.ordinal
            fanOut { cb -> cb.onServiceStatusChanged(snapshot.ordinal) }
        }
    }

    /**
     * 把一段操作分发给所有 alive 的 [IServiceCallback]。失败的单个 callback
     * 不影响其他订阅者（用 try/catch 隔离）。
     */
    fun fanOut(action: (IServiceCallback) -> Unit) {
        GlobalScope.launch(Dispatchers.Main) {
            fanOutLock.withLock {
                val count = callbacks.beginBroadcast()
                try {
                    for (i in 0 until count) {
                        try {
                            action(callbacks.getBroadcastItem(i))
                        } catch (_: Exception) {
                            // 单个 callback 死了不影响其他
                        }
                    }
                } finally {
                    callbacks.finishBroadcast()
                }
            }
        }
    }

    // === AIDL surface =====================================================

    @Volatile
    private var currentStatusOrdinal: Int = KernelStatus.Stopped.ordinal

    override fun getStatus(): Int = currentStatusOrdinal

    override fun registerCallback(callback: IServiceCallback) {
        callbacks.register(callback)
        // 补发当前状态给这个刚注册的回调——不然它只能等下一次真实变化才知道
        // 现在是什么状态。真实会命中的场景：Activity/Flutter engine 重建
        // （例如冷启动、进程被系统回收后重新拉起）但 native TunnelService/
        // PlainService 组件本身没死（前台 service 独立于 Activity 生命周期
        // 存活），新绑定的客户端在这之前对"当前状态"一无所知，只能显示初始
        // 默认值直到内核状态碰巧再变一次——如果内核已经稳定在 Started/
        // Stopped，可能永远等不到下一次变化，UI 就卡在错误的初始猜测上。
        // `status.observeForever` 那份镜像只在 `init` 时挂一次、不会替后来
        // 才注册的每个新 callback 单独补发，所以这里要显式做一次。跟这个
        // 仓库其它地方（LiveData replay-on-observe、ValueStream/
        // BehaviorSubject replay-on-subscribe）统一遵守的"新订阅者立即拿到
        // 当前值"惯例保持一致。
        //
        // 走 Dispatchers.Main（不是在当前 binder 线程上同步调用）是为了跟
        // [fanOut] 的既有线程模型保持一致——所有 IPC callback 调用统一从
        // 同一个线程发出，不给客户端引入"这次是 binder 线程、之后都是主
        // 线程"的不一致假设。
        GlobalScope.launch(Dispatchers.Main) {
            try {
                callback.onServiceStatusChanged(currentStatusOrdinal)
            } catch (_: Exception) {
                // 回调本身可能已经死了（binder 另一端进程刚好在这个瞬间
                // 挂掉），不影响 register 本身成功，后续真实状态变化走
                // fanOut 的 try/catch 隔离，这里没必要重复处理。
            }
        }
    }

    override fun unregisterCallback(callback: IServiceCallback?) {
        callbacks.unregister(callback)
    }

    fun close() {
        callbacks.kill()
    }
}
