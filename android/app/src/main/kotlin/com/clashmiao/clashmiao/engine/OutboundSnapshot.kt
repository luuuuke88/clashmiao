package com.clashmiao.clashmiao.engine

import com.google.gson.Gson
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupItem

/**
 * 把 libbox 推过来的 [OutboundGroup]（go-jni 类型）拍平成 plain Kotlin data class，
 * 再编码成 JSON 推给 Dart 端 EventChannel。
 *
 * **字段名必须显式写出，不能靠反射 + `@SerializedName`。** release 包经 R8 混淆：
 * 字段被改名成 `a/b/c/d`，而 Gson 2.10 没有自带 keep 规则，`@SerializedName` 注解随
 * 未被 keep 的字段一起被剥掉——Gson 于是按混淆后的字段名输出 `{"a":"select",...}`，
 * Dart 读 `tag/items` 全是空，代理页拿不到任何实时分组，只能回退到订阅配置里的分组
 * tag（运行时根本不存在），选择与测速全部 not found。所以这里先转成 Map 再编码：
 * Map / List / String / Int 走 Gson 内置适配器，与类的字段名无关。
 *
 * Dart 解析按 kebab-case 字段名（`url-test-delay` 是 sing-box 内部 wire format 的写法）。
 *
 * 拆两个类是为了：item 不持有对父 group iterator 的引用，序列化时不会被 jni
 * 引用计数拽住。
 */
data class OutboundSnapshot(
    val tag: String,
    val type: String,
    val selected: String,
    val items: List<OutboundItemSnapshot>,
) {
    /** 推给 Dart 的载荷（键名即契约）。 */
    fun toWire(): Map<String, Any> = linkedMapOf(
        "tag" to tag,
        "type" to type,
        "selected" to selected,
        "items" to items.map { it.toWire() },
    )

    companion object {
        private val gson = Gson()

        /** 分组流的 JSON 载荷：`[{tag, type, selected, items: [{tag, type, url-test-delay}]}]`。 */
        fun encode(groups: List<OutboundSnapshot>): String = gson.toJson(groups.map { it.toWire() })

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
    val tag: String,
    val type: String,
    val urlTestDelay: Int,
) {
    fun toWire(): Map<String, Any> = linkedMapOf(
        "tag" to tag,
        "type" to type,
        "url-test-delay" to urlTestDelay,
    )

    companion object {
        fun from(item: OutboundGroupItem): OutboundItemSnapshot = OutboundItemSnapshot(
            tag = item.tag,
            type = item.type,
            urlTestDelay = item.urlTestDelay,
        )
    }
}
