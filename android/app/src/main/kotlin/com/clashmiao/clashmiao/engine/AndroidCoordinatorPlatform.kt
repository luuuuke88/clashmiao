package com.clashmiao.clashmiao.engine

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.core.EngineMode
import com.clashmiao.clashmiao.core.Prefs
import java.util.UUID

/** 能弹出 VPN 授权对话框的界面（MainActivity）。 */
interface ActivityHost {
    fun launchVpnConsent(intent: Intent)
}

/**
 * [CoordinatorPlatform] 的 Android 实现：主线程 Handler 做定时器、`VpnService.prepare` 做授权、
 * `startForegroundService` 拉起 Service。
 *
 * VPN 授权对话框全局只会有一个：授权期间新的请求只更新「等待的 token」，不重复弹窗；
 * 对话框结果交给**当前**等待的 token，协调器核心再校验它是否仍属于最新意图（丢弃过期回调）。
 */
class AndroidCoordinatorPlatform(private val app: Context) : CoordinatorPlatform {

    private val main = Handler(Looper.getMainLooper())
    private val timers = HashMap<Any, Runnable>()

    /** 由 [KernelCoordinator] 装配后设置：把授权结果交回协调器。 */
    var authSink: (token: Long, granted: Boolean, message: String) -> Unit = { _, _, _ -> }

    private var activityHost: ActivityHost? = null
    private var dialogOutstanding = false
    private var waitingToken: Long? = null

    override fun isMainThread(): Boolean = Looper.myLooper() == Looper.getMainLooper()

    override fun post(r: Runnable) {
        main.post(r)
    }

    override fun schedule(slot: Any, delayMs: Long, r: Runnable) {
        timers.remove(slot)?.let(main::removeCallbacks)
        val wrapped = Runnable {
            timers.remove(slot)
            r.run()
        }
        timers[slot] = wrapped
        main.postDelayed(wrapped, delayMs)
    }

    override fun cancel(slot: Any) {
        timers.remove(slot)?.let(main::removeCallbacks)
    }

    override fun requestVpnAuth(token: Long) {
        val intent = try {
            VpnService.prepare(app)
        } catch (e: Exception) {
            authSink(token, false, e.message ?: "VpnService.prepare failed")
            return
        }
        if (intent == null) {
            authSink(token, true, "")
            return
        }
        val host = activityHost
        if (host == null) {
            // 没有界面（磁贴 / 开机）：无法弹授权窗口，如实失败。
            authSink(token, false, "vpn consent requires the app UI")
            return
        }
        waitingToken = token
        if (dialogOutstanding) return
        dialogOutstanding = true
        try {
            host.launchVpnConsent(intent)
        } catch (e: Exception) {
            dialogOutstanding = false
            waitingToken = null
            authSink(token, false, e.message ?: "cannot show vpn consent")
        }
    }

    override fun cancelVpnAuth(token: Long) {
        if (waitingToken == token) waitingToken = null
    }

    /** 授权对话框的结果（Activity.onActivityResult → PermissionGate）。 */
    fun onConsentResult(granted: Boolean) {
        dialogOutstanding = false
        val token = waitingToken ?: return
        waitingToken = null
        authSink(token, granted, if (granted) "" else "user denied vpn consent")
    }

    fun attachActivity(host: ActivityHost) {
        activityHost = host
    }

    fun detachActivity(host: ActivityHost) {
        if (activityHost === host) {
            activityHost = null
            dialogOutstanding = false
        }
    }

    override fun startService(type: ServiceType) {
        val cls = when (type) {
            ServiceType.Vpn -> TunnelService::class.java
            ServiceType.Proxy -> PlainService::class.java
        }
        ContextCompat.startForegroundService(app, Intent(app, cls))
    }

    override fun currentMode(): ServiceType =
        if (Prefs.Engine.mode == EngineMode.VPN) ServiceType.Vpn else ServiceType.Proxy

    override fun log(line: String) {
        Log.i(TAG, line)
    }

    companion object {
        const val TAG = "KernelCoordinator"
    }
}

/** 进程级单例装配：Application 之后第一次访问时创建。 */
internal class AndroidKernelWiring {
    val platform = AndroidCoordinatorPlatform(Application.application)
    val live = MutableLiveData<KernelSnapshot>()
    val coordinator: KernelCoordinator

    init {
        val executor = KernelExecutor(
            postToMain = { platform.post(it) },
            logger = { Log.w(AndroidCoordinatorPlatform.TAG, it) },
        )
        coordinator = KernelCoordinator(
            platform = platform,
            executor = executor,
            store = KernelStore(PrefsKeyValueStore()),
            logs = LogBuffer(capacity = 300),
            epoch = UUID.randomUUID().toString(),
        )
        platform.authSink = { token, granted, message -> coordinator.onAuthResult(token, granted, message) }
        coordinator.observeSnapshot { live.value = it }
    }
}

/** [KernelStore] 的 SharedPreferences 实现（与 [Prefs] 共用 FlutterSharedPreferences 文件）。 */
class PrefsKeyValueStore : KeyValueStore {
    private val sp by lazy {
        Application.application.applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
    }

    override fun getString(key: String): String? = sp.getString(key, null)
    override fun putString(key: String, value: String) {
        sp.edit().putString(key, value).apply()
    }

    override fun getBoolean(key: String, default: Boolean): Boolean = sp.getBoolean(key, default)
}
