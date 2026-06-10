package com.clashmiao.clashmiao.engine

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import com.clashmiao.clashmiao.core.KernelStatus

@RequiresApi(Build.VERSION_CODES.N)
class QuickSettingsTileService : TileService(), KernelConnection.Sink {

    private val connection = KernelConnection(this, this)

    override fun onStatusChange(status: KernelStatus) {
        qsTile?.apply {
            state = when (status) {
                KernelStatus.Started -> Tile.STATE_ACTIVE
                KernelStatus.Stopped -> Tile.STATE_INACTIVE
                else -> Tile.STATE_UNAVAILABLE
            }
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        connection.connect()
    }

    override fun onStopListening() {
        connection.disconnect()
        super.onStopListening()
    }

    override fun onClick() {
        when (connection.lastKnownStatus) {
            KernelStatus.Stopped -> KernelHost.fireStart()
            KernelStatus.Started -> KernelHost.fireStop()
            else -> Unit
        }
    }
}
