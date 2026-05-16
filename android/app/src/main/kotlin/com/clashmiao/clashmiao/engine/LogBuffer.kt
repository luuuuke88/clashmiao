package com.clashmiao.clashmiao.engine

import java.util.LinkedList

/**
 * 内核日志的进程内环形缓冲 —— 容量到上限就丢最旧的，按行存。
 *
 * 老代码里 [com.clashmiao.clashmiao.MainActivity] 把 `LinkedList<String>` + 一个
 * `((Boolean) -> Unit)?` callback 直接当 public field 暴露，多线程写没保护。
 * 这里收口成一个类：写 / 订阅 / drain 都内部锁，外部只能通过方法触达。
 *
 * @param capacity 最多保留多少行，0 = 无限（不要这么用）
 */
class LogBuffer(private val capacity: Int = 300) {

    private val lines = LinkedList<String>()
    private val lock = Any()

    /**
     * 订阅者：每次新日志写入或 reset 时调一次。
     * Boolean 参数：true = 整段被 reset（清空 + 灌新 batch），false = 单行 append。
     */
    @Volatile
    var subscriber: ((Boolean) -> Unit)? = null

    /** 当前缓冲快照（线程安全 copy）。 */
    fun snapshot(): MutableList<String> = synchronized(lock) { LinkedList(lines) }

    /** 追加一行；超过 [capacity] 自动丢最旧。 */
    fun append(line: String) {
        synchronized(lock) {
            if (lines.size >= capacity) lines.removeFirst()
            lines.addLast(line)
        }
        // 先把 var 读到本地再调用 —— 避免 subscriber 被并发置 null 走到 NPE 上去。
        subscriber?.let { it(false) }
    }

    /** 整段替换（service restart / clear logs 时用）。 */
    fun reset(batch: Collection<String>) {
        synchronized(lock) {
            lines.clear()
            lines.addAll(batch)
        }
        subscriber?.let { it(true) }
    }

    /** 清空缓冲。 */
    fun clear() = reset(emptyList())
}
