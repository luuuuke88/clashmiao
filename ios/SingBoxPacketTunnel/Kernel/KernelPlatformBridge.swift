//
//  KernelPlatformBridge.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Implements libcore's platform interface: every native callback the
//  kernel needs (TUN setup, WiFi detection, log sink, DNS reload, ...)
//  routes through this object. The class also doubles as the command
//  server's handler so Runner-side `KernelCommandClient` instances
//  receive log / status / group updates.
//

import Foundation
import Libcore
import NetworkExtension

/// Lives for the duration of one tunnel session.
public final class KernelPlatformBridge: NSObject,
                                         LibboxPlatformInterfaceProtocol,
                                         LibboxCommandServerHandlerProtocol {

    /// Back-pointer to the provider so we can call NEPacketTunnelProvider
    /// APIs (setTunnelNetworkSettings, packetFlow.value(forKeyPath:), …).
    private let provider: KernelProviderProxy

    /// Last applied NE settings. Used to support `clearDNSCache` and the
    /// system-proxy toggle without re-deriving from scratch.
    private var lastAppliedSettings: NEPacketTunnelNetworkSettings?

    init(_ provider: KernelProviderProxy) {
        self.provider = provider
    }

    /// Allow `KernelProviderProxy` to reset cached state on tunnel stop.
    func discardCachedSettings() {
        lastAppliedSettings = nil
    }

    // MARK: - WiFi state

    public func readWIFIState() -> LibboxWIFIState? {
        // iOS does not expose SSID/BSSID to non-privileged extensions
        // without the location entitlement. Returning nil disables
        // rules that depend on WiFi identification.
        return nil
    }

    // MARK: - TUN handling

    public func openTun(_ options: LibboxTunOptionsProtocol?,
                        ret0_: UnsafeMutablePointer<Int32>?) throws {
        try awaitBlockingThrowing { [self] in
            try await openTunAsync(options, ret0_)
        }
    }

    /// Translates libcore's tun configuration request into NetworkExtension
    /// settings and applies them. The returned file descriptor (via
    /// `ret0_`) is what libcore will feed packets to/from.
    private func openTunAsync(_ options: LibboxTunOptionsProtocol?,
                              _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw NSError(domain: "[ClashMiao] nil tun options", code: 1)
        }
        guard let ret0_ else {
            throw NSError(domain: "[ClashMiao] nil return pointer", code: 2)
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            var dnsError: NSError?
            let dns = options.getDNSServerAddress(&dnsError)
            if let dnsError { throw dnsError }
            settings.dnsSettings = NEDNSSettings(servers: [dns])

            try Self.applyIPv4(settings: settings, options: options)
            try Self.applyIPv6(settings: settings, options: options)
        }

        if options.isHTTPProxyEnabled() {
            let proxy = NEProxySettings()
            let endpoint = NEProxyServer(
                address: options.getHTTPProxyServer(),
                port: Int(options.getHTTPProxyServerPort())
            )
            proxy.httpServer = endpoint
            proxy.httpsServer = endpoint
            settings.proxySettings = proxy
        }

        lastAppliedSettings = settings
        try await provider.setTunnelNetworkSettings(settings)

        // Prefer the raw fd off the packet flow's underlying socket –
        // this is the fastest path. Fall back to libcore's helper if
        // KVC is unavailable (some OS versions strip it).
        if let fd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = fd
            return
        }
        let fallback = LibboxGetTunnelFileDescriptor()
        guard fallback != -1 else {
            throw NSError(domain: "[ClashMiao] missing tun fd", code: 3)
        }
        ret0_.pointee = fallback
    }

    private static func applyIPv4(settings: NEPacketTunnelNetworkSettings,
                                  options: LibboxTunOptionsProtocol) throws {
        var addrs: [String] = []
        var masks: [String] = []
        if let iter = options.getInet4Address() {
            while iter.hasNext() {
                guard let prefix = iter.next() else { continue }
                addrs.append(prefix.address())
                masks.append(prefix.mask())
            }
        }
        let ipv4 = NEIPv4Settings(addresses: addrs, subnetMasks: masks)
        var routes: [NEIPv4Route] = []
        if let routeIter = options.getInet4RouteAddress(), routeIter.hasNext() {
            while routeIter.hasNext() {
                guard let r = routeIter.next() else { continue }
                routes.append(NEIPv4Route(destinationAddress: r.address(),
                                          subnetMask: r.mask()))
            }
        } else {
            routes.append(NEIPv4Route.default())
        }
        for (index, address) in addrs.enumerated() {
            routes.append(NEIPv4Route(destinationAddress: address,
                                      subnetMask: masks[index]))
        }
        ipv4.includedRoutes = routes
        settings.ipv4Settings = ipv4
    }

    private static func applyIPv6(settings: NEPacketTunnelNetworkSettings,
                                  options: LibboxTunOptionsProtocol) throws {
        var addrs: [String] = []
        var prefixes: [NSNumber] = []
        if let iter = options.getInet6Address() {
            while iter.hasNext() {
                guard let prefix = iter.next() else { continue }
                addrs.append(prefix.address())
                prefixes.append(NSNumber(value: prefix.prefix()))
            }
        }
        let ipv6 = NEIPv6Settings(addresses: addrs, networkPrefixLengths: prefixes)
        var routes: [NEIPv6Route] = []
        if let routeIter = options.getInet6RouteAddress(), routeIter.hasNext() {
            while routeIter.hasNext() {
                guard let r = routeIter.next() else { continue }
                routes.append(NEIPv6Route(destinationAddress: r.address(),
                                          networkPrefixLength: NSNumber(value: r.prefix())))
            }
        } else {
            routes.append(NEIPv6Route.default())
        }
        ipv6.includedRoutes = routes
        settings.ipv6Settings = ipv6
    }

    // MARK: - Interface monitoring (delegated to OS)

    public func usePlatformAutoDetectControl() -> Bool { true }
    public func autoDetectControl(_: Int32) throws {}
    public func usePlatformDefaultInterfaceMonitor() -> Bool { false }
    public func startDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}
    public func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {}
    public func useGetter() -> Bool { false }
    public func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "[ClashMiao] interface enumeration not supported", code: 4)
    }
    public func underNetworkExtension() -> Bool { true }
    public func includeAllNetworks() -> Bool { false }

    // MARK: - Process attribution (unused on iOS)

    public func findConnectionOwner(_: Int32,
                                    sourceAddress _: String?,
                                    sourcePort _: Int32,
                                    destinationAddress _: String?,
                                    destinationPort _: Int32,
                                    ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "[ClashMiao] findConnectionOwner unsupported", code: 5)
    }

    public func packageName(byUid _: Int32, error _: NSErrorPointer) -> String { "" }
    public func uid(byPackageName _: String?, ret0_ _: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "[ClashMiao] uid lookup unsupported", code: 6)
    }
    public func useProcFS() -> Bool { false }

    // MARK: - Logging

    public func writeLog(_ message: String?) {
        guard let message else { return }
        provider.forwardKernelLine(message)
    }

    // MARK: - DNS / proxy lifecycle

    public func clearDNSCache() {
        guard let lastAppliedSettings else { return }
        // Bounce the tunnel settings to force a DNS cache flush. We
        // assert reasserting around it so the OS doesn't try to drop
        // the tunnel while we're swapping settings.
        provider.reasserting = true
        provider.setTunnelNetworkSettings(nil) { _ in }
        provider.setTunnelNetworkSettings(lastAppliedSettings) { _ in }
        provider.reasserting = false
    }

    public func serviceReload() throws {
        awaitBlocking { [provider] in
            await provider.reloadKernelService()
        }
    }

    public func getSystemProxyStatus() -> LibboxSystemProxyStatus? {
        let status = LibboxSystemProxyStatus()
        guard let proxySettings = lastAppliedSettings?.proxySettings,
              proxySettings.httpServer != nil else {
            return status
        }
        status.available = true
        status.enabled = proxySettings.httpEnabled
        return status
    }

    public func setSystemProxyEnabled(_ isEnabled: Bool) throws {
        guard
            let settings = lastAppliedSettings,
            let proxySettings = settings.proxySettings,
            proxySettings.httpServer != nil,
            proxySettings.httpEnabled != isEnabled
        else { return }
        proxySettings.httpEnabled = isEnabled
        proxySettings.httpsEnabled = isEnabled
        settings.proxySettings = proxySettings
        try awaitBlockingThrowing { [provider] in
            try await provider.setTunnelNetworkSettings(settings)
        }
    }

    public func postServiceClose() {
        // Reserved for future cleanup hooks. Intentionally empty.
    }
}
