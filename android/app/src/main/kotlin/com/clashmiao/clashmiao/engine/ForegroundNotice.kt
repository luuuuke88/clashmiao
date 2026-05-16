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
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.StatusMessage
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.withContext

/**
 * 前台 service 的通知 + 实时上行 / 下行更新。
 *
 * 行为概要：
 *   - [show] 上 foreground notification（包含 "stop" action）；Android 14+ 必须
 *     带 [ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE] 并与 manifest 对齐
 *   - [start] 在用户开了 dynamic notification 时连一条 libbox CommandClient
 *     拉取 status 流，按 ~1s tick 刷新通知内容（上行 / 下行 byte 数）
 *   - screen on/off 广播控制连通：屏幕关时断开 CommandClient 省电
 *   - [close] 停 foreground + 卸 receiver + 断 CommandClient
 *
 * 这层是 [KernelHost] 内部组件，外面拿不到引用。
 */
@OptIn(DelicateCoroutinesApi::class)
class ForegroundNotice(private val service: Service) :
    BroadcastReceiver(),
    LibboxCommandStream.Subscriber {

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

    private val statsStream = LibboxCommandStream(
        GlobalScope,
        LibboxCommandStream.StreamKind.STATS,
        this,
    )

    @Volatile private var screenReceiverArmed = false

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

    /** 用户开了 dynamic-notification 才订阅 stats 流；同时 wire 屏幕开关广播。 */
    suspend fun start() {
        if (!Prefs.Notice.dynamic) return
        statsStream.connect()
        withContext(Dispatchers.Main) {
            if (!screenReceiverArmed) {
                service.registerReceiver(
                    this@ForegroundNotice,
                    IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON)
                        addAction(Intent.ACTION_SCREEN_OFF)
                    },
                )
                screenReceiverArmed = true
            }
        }
    }

    // 参数名跟 Subscriber.onStats(message: StatusMessage) 对齐，方便 named-arg 调用。
    override fun onStats(message: StatusMessage) {
        val upText = Libbox.formatBytes(message.uplink) + "/s ↑"
        val downText = Libbox.formatBytes(message.downlink) + "/s ↓"
        Application.notificationManager.notify(
            NOTIFY_ID,
            noticeTemplate.setContentText("$upText\t$downText").build(),
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> statsStream.connect()
            Intent.ACTION_SCREEN_OFF -> statsStream.disconnect()
        }
    }

    fun close() {
        statsStream.disconnect()
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (screenReceiverArmed) {
            runCatching { service.unregisterReceiver(this) }
            screenReceiverArmed = false
        }
    }
}
