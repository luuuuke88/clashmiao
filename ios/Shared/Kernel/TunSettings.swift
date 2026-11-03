//
//  TunSettings.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  TUN 规格（内核拍平后的 JSON，字段见 kernel/engine/tunspec.go）→ `NEPacketTunnelNetworkSettings`。
//  映射表见 docs/superpowers/specs/2026-11-03-apple-desktop-kernel-design.md §4.3。
//  纯函数：扩展在 openTun 里用，Runner 只为了让单测能 `@testable import` 才编进来。
//

import Foundation
import NetworkExtension

/// 内核拍平后的 TUN 规格。所有数组都非 nil（内核保证），这里仍按缺省兜底。
struct TunSpec: Decodable {
    struct HTTPProxy: Decodable {
        var enabled = false
        var server = ""
        var port: Int32 = 0
        var bypass: [String] = []
        var match: [String] = []
    }

    var mtu: Int32 = 0
    var autoRoute = false
    var strictRoute = false
    var dnsMode = ""
    var dnsServers: [String] = []
    var inet4Address: [String] = []
    var inet6Address: [String] = []
    var inet4Route: [String] = []
    var inet6Route: [String] = []
    var inet4RouteExclude: [String] = []
    var inet6RouteExclude: [String] = []
    var inet4RouteRange: [String] = []
    var inet6RouteRange: [String] = []
    var includePackage: [String] = []
    var excludePackage: [String] = []
    var httpProxy = HTTPProxy()

    enum CodingKeys: String, CodingKey {
        case mtu
        case autoRoute = "auto_route"
        case strictRoute = "strict_route"
        case dnsMode = "dns_mode"
        case dnsServers = "dns_servers"
        case inet4Address = "inet4_address"
        case inet6Address = "inet6_address"
        case inet4Route = "inet4_route"
        case inet6Route = "inet6_route"
        case inet4RouteExclude = "inet4_route_exclude"
        case inet6RouteExclude = "inet6_route_exclude"
        case inet4RouteRange = "inet4_route_range"
        case inet6RouteRange = "inet6_route_range"
        case includePackage = "include_package"
        case excludePackage = "exclude_package"
        case httpProxy = "http_proxy"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mtu = try c.decodeIfPresent(Int32.self, forKey: .mtu) ?? 0
        autoRoute = try c.decodeIfPresent(Bool.self, forKey: .autoRoute) ?? false
        strictRoute = try c.decodeIfPresent(Bool.self, forKey: .strictRoute) ?? false
        dnsMode = try c.decodeIfPresent(String.self, forKey: .dnsMode) ?? ""
        dnsServers = try c.decodeIfPresent([String].self, forKey: .dnsServers) ?? []
        inet4Address = try c.decodeIfPresent([String].self, forKey: .inet4Address) ?? []
        inet6Address = try c.decodeIfPresent([String].self, forKey: .inet6Address) ?? []
        inet4Route = try c.decodeIfPresent([String].self, forKey: .inet4Route) ?? []
        inet6Route = try c.decodeIfPresent([String].self, forKey: .inet6Route) ?? []
        inet4RouteExclude = try c.decodeIfPresent([String].self, forKey: .inet4RouteExclude) ?? []
        inet6RouteExclude = try c.decodeIfPresent([String].self, forKey: .inet6RouteExclude) ?? []
        inet4RouteRange = try c.decodeIfPresent([String].self, forKey: .inet4RouteRange) ?? []
        inet6RouteRange = try c.decodeIfPresent([String].self, forKey: .inet6RouteRange) ?? []
        includePackage = try c.decodeIfPresent([String].self, forKey: .includePackage) ?? []
        excludePackage = try c.decodeIfPresent([String].self, forKey: .excludePackage) ?? []
        if let p = try c.decodeIfPresent(HTTPProxyRaw.self, forKey: .httpProxy) {
            httpProxy = HTTPProxy(enabled: p.enabled ?? false, server: p.server ?? "", port: p.port ?? 0,
                                  bypass: p.bypass ?? [], match: p.match ?? [])
        }
    }

    private struct HTTPProxyRaw: Decodable {
        var enabled: Bool?
        var server: String?
        var port: Int32?
        var bypass: [String]?
        var match: [String]?
    }
}

enum TunSpecError: Error, CustomStringConvertible {
    case malformed(String)
    case noDNSServer
    case badPrefix(String)

    var description: String {
        switch self {
        case .malformed(let m): return "tun spec is not valid JSON: \(m)"
        case .noDNSServer: return "tun spec has no DNS server; refusing to leave DNS outside the tunnel"
        case .badPrefix(let p): return "tun spec has an invalid prefix: \(p)"
        }
    }
}

/// TunSpec → NE 设置（纯函数，便于单测）。
enum TunSettingsBuilder {

    static func settings(from spec: TunSpec) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if spec.autoRoute {
            settings.mtu = NSNumber(value: spec.mtu)
            guard !spec.dnsServers.isEmpty else { throw TunSpecError.noDNSServer }
            let dns = NEDNSSettings(servers: spec.dnsServers)
            dns.matchDomains = [""] // 全部查询走隧道里的 DNS
            settings.dnsSettings = dns
            settings.ipv4Settings = try ipv4(spec)
            settings.ipv6Settings = try ipv6(spec)
        }
        if spec.httpProxy.enabled {
            let proxy = NEProxySettings()
            let endpoint = NEProxyServer(address: spec.httpProxy.server, port: Int(spec.httpProxy.port))
            proxy.httpServer = endpoint
            proxy.httpsServer = endpoint
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
            if !spec.httpProxy.bypass.isEmpty { proxy.exceptionList = spec.httpProxy.bypass }
            if !spec.httpProxy.match.isEmpty { proxy.matchDomains = spec.httpProxy.match }
            settings.proxySettings = proxy
        }
        return settings
    }

    /// Android 专用字段在 iOS 上没有对应物：非空时返回提示，由调用方写诊断日志。
    static func ignoredFields(_ spec: TunSpec) -> [String] {
        var out: [String] = []
        if !spec.inet4RouteRange.isEmpty || !spec.inet6RouteRange.isEmpty { out.append("route_range") }
        if !spec.includePackage.isEmpty { out.append("include_package") }
        if !spec.excludePackage.isEmpty { out.append("exclude_package") }
        if spec.strictRoute { out.append("strict_route") }
        return out
    }

    static func ipv4(_ spec: TunSpec) throws -> NEIPv4Settings? {
        if spec.inet4Address.isEmpty { return nil }
        var addrs: [String] = []
        var masks: [String] = []
        for p in spec.inet4Address {
            let (a, len) = try split(p)
            addrs.append(a)
            masks.append(mask4(len))
        }
        let v4 = NEIPv4Settings(addresses: addrs, subnetMasks: masks)
        var routes: [NEIPv4Route] = []
        if spec.inet4Route.isEmpty {
            routes.append(NEIPv4Route.default())
        } else {
            for p in spec.inet4Route {
                let (a, len) = try split(p)
                routes.append(NEIPv4Route(destinationAddress: a, subnetMask: mask4(len)))
            }
        }
        for (i, a) in addrs.enumerated() {
            routes.append(NEIPv4Route(destinationAddress: a, subnetMask: masks[i]))
        }
        v4.includedRoutes = routes
        if !spec.inet4RouteExclude.isEmpty {
            v4.excludedRoutes = try spec.inet4RouteExclude.map {
                let (a, len) = try split($0)
                return NEIPv4Route(destinationAddress: a, subnetMask: mask4(len))
            }
        }
        return v4
    }

    static func ipv6(_ spec: TunSpec) throws -> NEIPv6Settings? {
        if spec.inet6Address.isEmpty { return nil }
        var addrs: [String] = []
        var prefixes: [NSNumber] = []
        for p in spec.inet6Address {
            let (a, len) = try split(p)
            addrs.append(a)
            prefixes.append(NSNumber(value: len))
        }
        let v6 = NEIPv6Settings(addresses: addrs, networkPrefixLengths: prefixes)
        var routes: [NEIPv6Route] = []
        if spec.inet6Route.isEmpty {
            routes.append(NEIPv6Route.default())
        } else {
            for p in spec.inet6Route {
                let (a, len) = try split(p)
                routes.append(NEIPv6Route(destinationAddress: a, networkPrefixLength: NSNumber(value: len)))
            }
        }
        for (i, a) in addrs.enumerated() {
            routes.append(NEIPv6Route(destinationAddress: a, networkPrefixLength: prefixes[i]))
        }
        v6.includedRoutes = routes
        if !spec.inet6RouteExclude.isEmpty {
            v6.excludedRoutes = try spec.inet6RouteExclude.map {
                let (a, len) = try split($0)
                return NEIPv6Route(destinationAddress: a, networkPrefixLength: NSNumber(value: len))
            }
        }
        return v6
    }

    /// "a.b.c.d/n" 或 "x::y/n" → (地址, 前缀长度)
    static func split(_ prefix: String) throws -> (String, Int) {
        let parts = prefix.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let len = Int(parts[1]), len >= 0, len <= 128 else {
            throw TunSpecError.badPrefix(prefix)
        }
        return (String(parts[0]), len)
    }

    static func mask4(_ len: Int) -> String {
        let l = max(0, min(32, len))
        let m: UInt32 = l == 0 ? 0 : UInt32.max << UInt32(32 - l)
        return "\(m >> 24 & 0xff).\(m >> 16 & 0xff).\(m >> 8 & 0xff).\(m & 0xff)"
    }
}
