package com.clashmiao.clashmiao.core

import android.net.IpPrefix
import android.os.Build
import androidx.annotation.RequiresApi
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.StringIterator
import java.net.InetAddress

/**
 * 把 libbox 暴露的 Go iterator / native type 桥到 Kotlin 标准容器或 Android framework
 * 对应物的本地小适配器。每个函数都是单一职责，写在这里而不是分散到散文件里
 * 主要是为了减少 import 噪声。
 */

/** libbox `RoutePrefix` → Android `IpPrefix`，Tiramisu+ VpnService.Builder.addRoute 需要它。 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
fun RoutePrefix.asAndroidPrefix(): IpPrefix {
    val host = InetAddress.getByName(address())
    return IpPrefix(host, prefix())
}

/** 把 Go 风格的 StringIterator 一次性 drain 成普通 List<String>。 */
fun StringIterator.drain(): List<String> {
    val out = ArrayList<String>()
    while (hasNext()) out.add(next())
    return out
}
