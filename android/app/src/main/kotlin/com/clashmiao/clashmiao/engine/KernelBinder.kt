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
    }

    override fun unregisterCallback(callback: IServiceCallback?) {
        callbacks.unregister(callback)
    }

    fun close() {
        callbacks.kill()
    }
}
