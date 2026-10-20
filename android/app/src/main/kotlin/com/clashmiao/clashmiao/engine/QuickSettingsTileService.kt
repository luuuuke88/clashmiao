package com.clashmiao.clashmiao.engine

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import androidx.lifecycle.Observer
import com.clashmiao.clashmiao.core.KernelStatus

/**
 * 快速设置磁贴：观察进程级协调器的快照，点击提交 source=tile 的外部请求。
 * 不再绑定 Service；App 没打开（无 Activity）时也能启动与停止——启动用持久化的最近 LaunchSpec。
 */
@RequiresApi(Build.VERSION_CODES.N)
class QuickSettingsTileService : TileService() {

    private val observer = Observer<KernelSnapshot> { render(it) }

    override fun onStartListening() {
        super.onStartListening()
        KernelCoordinator.snapshotLive.removeObserver(observer)
        KernelCoordinator.snapshotLive.observeForever(observer)
    }

    override fun onStopListening() {
        KernelCoordinator.snapshotLive.removeObserver(observer)
        super.onStopListening()
    }

    override fun onClick() {
        KernelCoordinator.instance.toggleExternal(Source.Tile)
    }

    private fun render(snapshot: KernelSnapshot) {
        qsTile?.apply {
            // desired=on 的整个过渡期都保持可点（点击 = 停止，任何阶段都会被执行）。
            state = when {
                snapshot.desired == Desired.On -> Tile.STATE_ACTIVE
                snapshot.status == KernelStatus.Stopped -> Tile.STATE_INACTIVE
                else -> Tile.STATE_UNAVAILABLE
            }
            updateTile()
        }
    }
}
