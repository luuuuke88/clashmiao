package com.clashmiao.clashmiao.engine

import com.google.gson.annotations.SerializedName
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupItem

/**
 * 把 libbox 推过来的 [OutboundGroup]（go-jni 类型）拍平成 plain Kotlin data class，
 * 然后 Gson 序列化成 JSON 推给 Dart 端 EventChannel。
 *
 * Dart 解析按 kebab-case 字段名，所以 @SerializedName 改写了字段命名映射
 * （`url-test-delay` 是 libbox / sing-box 内部 wire format 也用的写法）。
 *
 * 拆两个类是为了：item 不持有对父 group iterator 的引用，序列化时不会被 jni
 * 引用计数拽住。
 */
data class OutboundSnapshot(
    @SerializedName("tag") val tag: String,
    @SerializedName("type") val type: String,
    @SerializedName("selected") val selected: String,
    @SerializedName("items") val items: List<OutboundItemSnapshot>,
) {
    companion object {
        fun from(group: OutboundGroup): OutboundSnapshot {
            val iter = group.items
            val snapshots = ArrayList<OutboundItemSnapshot>()
            while (iter.hasNext()) {
                snapshots.add(OutboundItemSnapshot.from(iter.next()))
            }
            return OutboundSnapshot(
                tag = group.tag,
                type = group.type,
                selected = group.selected,
                items = snapshots,
            )
        }
    }
}

data class OutboundItemSnapshot(
    @SerializedName("tag") val tag: String,
    @SerializedName("type") val type: String,
    @SerializedName("url-test-delay") val urlTestDelay: Int,
) {
    companion object {
        fun from(item: OutboundGroupItem): OutboundItemSnapshot = OutboundItemSnapshot(
            tag = item.tag,
            type = item.type,
            urlTestDelay = item.urlTestDelay,
        )
    }
}
