package com.clashmiao.clashmiao.engine

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.annotation.StringRes
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.MainActivity
import com.clashmiao.clashmiao.R
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.core.BroadcastIntents
import org.json.JSONException
import org.json.JSONObject
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope

/**
 * 前台 service 的通知 + 实时上行 / 下行更新。
 *
 * 行为概要：
 *   - [show] 上 foreground notification（包含 "stop" action）；Android 14+ 必须
 *     带 [ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE] 并与 manifest 对齐
 *   - [startUpdates] 在用户开了 dynamic notification 时订阅内核的统计流
 *     拉取 status 流，按 ~1s tick 刷新通知内容（上行 / 下行 byte 数）；按 [beginUpdates]
 *     的代际归属，[stopUpdates] / [close] 之后迟到的启动任务不会留下资源
 *   - screen on/off 广播控制连通：屏幕关时断开统计流省电
 *   - [close] 停 foreground + 卸 receiver + 断统计流
 *
 * 这层是 [KernelHost] 内部组件，外面拿不到引用。
 */
@OptIn(DelicateCoroutinesApi::class)
class ForegroundNotice(private val service: Service) :
    BroadcastReceiver(),
    CoreStream.Subscriber {

    companion object {
        private const val NOTIFY_ID = 1
        private const val NOTIFY_CHANNEL = "service"
        private val pendingFlags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        /** Android 13+ runtime POST_NOTIFICATIONS permission gate。 */
        fun canPostNotifications(): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                Application.notification.areNotificationsEnabled()
    }

    private val statsStream = CoreStream(
        GlobalScope,
        CoreStream.StreamKind.STATS,
        this,
    )

    private val noticeTemplate: NotificationCompat.Builder by lazy {
        NotificationCompat.Builder(service, NOTIFY_CHANNEL)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSmallIcon(R.drawable.ic_stat_logo)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(launchActivityPendingIntent())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .also { it.addAction(stopAction()) }
    }

    private fun launchActivityPendingIntent(): PendingIntent = PendingIntent.getActivity(
        service,
        0,
        Intent(service, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
        pendingFlags,
    )

    private fun stopAction(): NotificationCompat.Action = NotificationCompat.Action.Builder(
        0,
        service.getText(R.string.stop),
        PendingIntent.getBroadcast(
            service,
            0,
            Intent(BroadcastIntents.SHUTDOWN).setPackage(service.packageName),
            pendingFlags,
        ),
    ).build()

    fun show(profileName: String, @StringRes statusTextId: Int) {
        ensureNotificationChannel()
        val displayTitle = profileName.ifBlank { "ClashMiao" }
        val notification = noticeTemplate
            .setContentTitle(displayTitle)
            .setContentText(service.getString(statusTextId))
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.startForeground(
                NOTIFY_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            service.startForeground(NOTIFY_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        Application.notification.createNotificationChannel(
            NotificationChannel(
                NOTIFY_CHANNEL,
                "clashmiao service",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    /** 统计流与屏幕广播按代际归属：停止 / 销毁之后迟到的启动任务不会再连接或注册。 */
    private val updates = NoticeUpdates(object : NoticeUpdates.Ops {
        override fun dynamicEnabled(): Boolean = Prefs.Notice.dynamic
        override fun connectStats() = statsStream.connect()
        override fun disconnectStats() = statsStream.disconnect()
        override fun registerScreen() {
            service.registerReceiver(
                this@ForegroundNotice,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_ON)
                    addAction(Intent.ACTION_SCREEN_OFF)
                },
            )
        }

        override fun unregisterScreen() {
            service.unregisterReceiver(this@ForegroundNotice)
        }
    })

    /** 开启新一代动态更新（主线程）；返回值交给后台的 [startUpdates]。 */
    fun beginUpdates(): Long = updates.begin()

    /** 后台执行：用户开了 dynamic-notification 且本代仍有效时，订阅 stats 流并 wire 屏幕开关广播。 */
    fun startUpdates(generation: Long) = updates.runStart(generation)

    override fun onStats(json: String) {
        val (up, down) = try {
            JSONObject(json).let { it.getLong("uplink") to it.getLong("downlink") }
        } catch (_: JSONException) {
            return // 畸形帧：丢弃，等下一帧
        }
        val upText = formatBytes(up) + "/s ↑"
        val downText = formatBytes(down) + "/s ↓"
        Application.notificationManager.notify(
            NOTIFY_ID,
            noticeTemplate.setContentText("$upText\t$downText").build(),
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> updates.onScreen(true)
            Intent.ACTION_SCREEN_OFF -> updates.onScreen(false)
        }
    }

    /**
     * 停止动态更新（断开统计流、注销屏幕广播），**保留**前台通知。
     * 重载 / 内核回收期间用：Android 12+ 后台不允许重新 startForeground，
     * 所以回收期间绝不能把 Service 降级成非前台。
     */
    fun stopUpdates() = updates.stop()

    /** 彻底关闭：停止更新并撤掉前台通知（Service 退休 / 销毁时）。 */
    fun close() {
        stopUpdates()
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }
}
