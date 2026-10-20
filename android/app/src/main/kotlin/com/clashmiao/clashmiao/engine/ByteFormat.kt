package com.clashmiao.clashmiao.engine

import java.util.Locale

/**
 * 通知栏里的字节数文案（`1.5 MB` / `12 kB` / `0 B`）：十进制单位，三位有效数字以内取一位小数。
 * 与官方内核的格式化函数（FormatKBytes）逐档一致——旧内核的 `Libbox.formatBytes` 同样如此，通知文案不变。
 * 负数当 0。
 */
internal fun formatBytes(bytes: Long): String {
    if (bytes <= 0) return "0 B"
    val units = listOf("kB", "MB", "GB", "TB", "PB", "EB")
    // 指数 e：bytes ≥ 1000^e 的最大 e（至少 1）；用整数比较，不依赖浮点对数在边界上的舍入。
    var e = 1
    var scale = 1000.0
    while (e < units.size && bytes.toDouble() >= scale * 1000.0) {
        scale *= 1000.0
        e++
    }
    val value = Math.floor(bytes / scale * 10 + 0.5) / 10
    val format = if (value < 10) "%.1f %s" else "%.0f %s"
    return String.format(Locale.ROOT, format, value, units[e - 1])
}
