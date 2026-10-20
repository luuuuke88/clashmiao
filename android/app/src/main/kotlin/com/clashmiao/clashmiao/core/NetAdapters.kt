package com.clashmiao.clashmiao.core

import android.net.IpPrefix
import android.os.Build
import androidx.annotation.RequiresApi
import java.net.InetAddress

/** CIDR 文本（`172.19.0.1/28`、`fd00::1/126`）拆成地址与前缀长度。不合法抛 [IllegalArgumentException]。 */
data class Cidr(val address: String, val prefix: Int) {
    override fun toString() = "$address/$prefix"

    companion object {
        fun parse(text: String): Cidr {
            val i = text.lastIndexOf('/')
            require(i > 0 && i < text.length - 1) { "not a CIDR: $text" }
            val prefix = text.substring(i + 1).toIntOrNull()
                ?: throw IllegalArgumentException("bad prefix length in $text")
            val address = text.substring(0, i)
            val max = if (address.contains(':')) 128 else 32
            require(prefix in 0..max) { "prefix length out of range in $text" }
            return Cidr(address, prefix)
        }
    }
}

/** [Cidr] → Android `IpPrefix`，Tiramisu+ VpnService.Builder.addRoute / excludeRoute 需要它。 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
fun Cidr.asAndroidPrefix(): IpPrefix = IpPrefix(InetAddress.getByName(address), prefix)
