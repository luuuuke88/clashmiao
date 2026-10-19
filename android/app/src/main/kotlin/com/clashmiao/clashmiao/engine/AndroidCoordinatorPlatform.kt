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
import com.clashmiao.clashmiao.core.Prefs
import io.nekohasekai.libbox.Libbox
import java.util.UUID

/** 能弹出 VPN 授权对话框的界面（MainActivity）。 */
interface ActivityHost {
    /** 以 [requestCode] 弹出授权对话框；结果须以同一 requestCode 交回 [KernelCoordinator.onVpnConsentResult]。 */
    fun launchVpnConsent(intent: Intent, requestCode: Int)
}

/**
 * [CoordinatorPlatform] 的 Android 实现：主线程 Handler 做定时器、`VpnService.prepare` 做授权、
 * `startForegroundService` 拉起 Service。
 *
 * VPN 授权对话框全局只会有一个，归属规则见 [VpnConsentBroker]：结果只报告给弹出它的 token，
 * 对话框开着时到达的新请求在它关闭后各自重新检查授权。
 */
class AndroidCoordinatorPlatform(private val app: Context) : CoordinatorPlatform {

    private val main = Handler(Looper.getMainLooper())
    private val timers = HashMap<Any, Runnable>()

    /** 由 [KernelCoordinator] 装配后设置：把授权结果交回协调器。 */
    var authSink: (token: Long, granted: Boolean, message: String) -> Unit = { _, _, _ -> }

    private val consent = VpnConsentBroker<Intent, ActivityHost>(
        prepare = { VpnService.prepare(app) },
        launch = { host, intent, requestCode -> host.launchVpnConsent(intent, requestCode) },
        sink = { token, granted, message -> authSink(token, granted, message) },
    )

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

    override fun requestVpnAuth(token: Long) = consent.request(token)

    override fun cancelVpnAuth(token: Long) = consent.cancel(token)

    /** 授权对话框的结果（Activity.onActivityResult）；false = 不是授权对话框的 requestCode。 */
    fun onConsentResult(requestCode: Int, granted: Boolean): Boolean = consent.onResult(requestCode, granted)

    fun attachActivity(host: ActivityHost) = consent.attach(host)

    fun detachActivity(host: ActivityHost) = consent.detach(host)

    override fun startService(type: ServiceType) {
        val cls = when (type) {
            ServiceType.Vpn -> TunnelService::class.java
            ServiceType.Proxy -> PlainService::class.java
        }
        ContextCompat.startForegroundService(app, Intent(app, cls))
    }

    override fun serviceTypeOf(spec: LaunchSpec): ServiceType = spec.serviceType()

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
            selector = OutboundSelector { group, outbound ->
                Libbox.newStandaloneCommandClient().selectOutbound(group, outbound)
            },
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

    /** `commit()` 的返回值才是可验证的落盘结果（`apply()` 失败不可见）。 */
    override fun commit(values: Map<String, String>): Boolean {
        val editor = sp.edit()
        values.forEach { (k, v) -> editor.putString(k, v) }
        return editor.commit()
    }
}
