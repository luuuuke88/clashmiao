package com.clashmiao.clashmiao.engine

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * 最终运行配置里的 tun inbound 只能有一个。
 *
 * tun 只该由启动参数 `enable-tun` 交给内核配置构建器创建（它把自己的 tun inbound
 * append 在订阅 inbounds 之后）。旧版本 app 写出、被原生持久化下来的运行配置里还
 * 留着订阅自带的 tun inbound——磁贴冷启动直接复用它，不经过 Dart 重新拼配置，最终
 * 配置就有两个 tun inbound：每次启动 `VpnService.Builder.establish()` 两次（tun0 被
 * tun1 替换），两套 tun 协议栈抢同一个地址，偶发 tun 转发监听缺失、经 tun 的 TCP
 * 全被拒，界面却显示已连接（真机验收 BUG-B）。
 *
 * 这里在交给内核之前收口：多于一个时只留最后一个（内核按当前网络设置 append 的
 * 那个），其余删掉。解析不了的文本原样返回，让内核自己报配置错误。
 */
internal object TunInbounds {
    data class Result(val content: String, val removed: Int)

    fun keepLast(content: String): Result {
        val root = try {
            JSONObject(content)
        } catch (_: JSONException) {
            return Result(content, 0)
        }
        val inbounds = root.optJSONArray("inbounds") ?: return Result(content, 0)
        val tunIndexes = (0 until inbounds.length()).filter {
            inbounds.optJSONObject(it)?.optString("type") == "tun"
        }
        if (tunIndexes.size <= 1) return Result(content, 0)
        val drop = tunIndexes.dropLast(1).toSet()
        val kept = JSONArray()
        for (i in 0 until inbounds.length()) {
            if (i !in drop) kept.put(inbounds.get(i))
        }
        root.put("inbounds", kept)
        return Result(root.toString(), drop.size)
    }
}
