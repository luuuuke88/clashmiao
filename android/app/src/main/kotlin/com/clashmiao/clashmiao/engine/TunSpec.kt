package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.Cidr
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Go 一侧把 libbox 的 TUN 选项拍平成的 JSON（spec §4.3 的 `TunSpec`），宿主据此建 VPN 接口。
 *
 * 所有数组 Go 都保证非 null；这里仍然对缺字段宽容（缺省为空 / false / 0），
 * 因为宿主只按「有没有元素」判断，不该因为将来 Go 侧多一个或少一个键就起不来。
 */
data class TunSpec(
    val mtu: Int,
    val autoRoute: Boolean,
    val strictRoute: Boolean,
    val dnsMode: DnsMode,
    val dnsServers: List<String>,
    val inet4Address: List<Cidr>,
    val inet6Address: List<Cidr>,
    val inet4Route: List<Cidr>,
    val inet6Route: List<Cidr>,
    val inet4RouteExclude: List<Cidr>,
    val inet6RouteExclude: List<Cidr>,
    val inet4RouteRange: List<Cidr>,
    val inet6RouteRange: List<Cidr>,
    val includePackage: List<String>,
    val excludePackage: List<String>,
    val httpProxy: HttpProxy,
) {
    /** `dns_mode`：disabled 不向系统加 DNS 服务器；native / hijack 都要加（内核自己接管 DNS 查询）。 */
    enum class DnsMode {
        Disabled, Native, Hijack;

        companion object {
            fun parse(value: String): DnsMode = when (value) {
                "disabled" -> Disabled
                "native" -> Native
                // 空串 / hijack / 未知值：内核默认行为是 hijack
                else -> Hijack
            }
        }
    }

    data class HttpProxy(
        val enabled: Boolean,
        val server: String,
        val port: Int,
        val bypass: List<String>,
        val match: List<String>,
    ) {
        companion object {
            val Disabled = HttpProxy(false, "", 0, emptyList(), emptyList())
        }
    }

    companion object {
        /** 解析 JSON；不是合法 JSON 对象时抛 [IllegalArgumentException]（由调用方变成 openTun 失败）。 */
        fun parse(json: String): TunSpec {
            val o = try {
                JSONObject(json)
            } catch (e: JSONException) {
                throw IllegalArgumentException("TunSpec is not a JSON object: ${e.message}", e)
            }
            val proxy = o.optJSONObject("http_proxy")?.let {
                HttpProxy(
                    enabled = it.optBoolean("enabled", false),
                    server = it.optString("server", ""),
                    port = it.optInt("port", 0),
                    bypass = it.optJSONArray("bypass").strings(),
                    match = it.optJSONArray("match").strings(),
                )
            } ?: HttpProxy.Disabled
            return TunSpec(
                mtu = o.optInt("mtu", 0),
                autoRoute = o.optBoolean("auto_route", false),
                strictRoute = o.optBoolean("strict_route", false),
                dnsMode = DnsMode.parse(o.optString("dns_mode", "")),
                dnsServers = o.optJSONArray("dns_servers").strings(),
                inet4Address = o.optJSONArray("inet4_address").cidrs(),
                inet6Address = o.optJSONArray("inet6_address").cidrs(),
                inet4Route = o.optJSONArray("inet4_route").cidrs(),
                inet6Route = o.optJSONArray("inet6_route").cidrs(),
                inet4RouteExclude = o.optJSONArray("inet4_route_exclude").cidrs(),
                inet6RouteExclude = o.optJSONArray("inet6_route_exclude").cidrs(),
                inet4RouteRange = o.optJSONArray("inet4_route_range").cidrs(),
                inet6RouteRange = o.optJSONArray("inet6_route_range").cidrs(),
                includePackage = o.optJSONArray("include_package").strings(),
                excludePackage = o.optJSONArray("exclude_package").strings(),
                httpProxy = proxy,
            )
        }

        private fun JSONArray?.strings(): List<String> {
            if (this == null) return emptyList()
            return (0 until length()).map { getString(it) }
        }

        private fun JSONArray?.cidrs(): List<Cidr> = strings().map(Cidr::parse)
    }
}
