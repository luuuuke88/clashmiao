//
//  KernelProviderProxy.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Reusable NEPacketTunnelProvider subclass that owns the kernel
//  lifecycle (LibboxBoxService + LibboxCommandServer). The concrete
//  `ClashMiaoTunnelProvider` extends this and adds traffic-stats
//  bookkeeping; the heavy lifting lives here so it stays test-friendly.
//

import Foundation
import Libcore
import NetworkExtension

/// Base class. `open` so the concrete provider can override
/// startTunnel/stopTunnel and add per-product behaviour.
open class KernelProviderProxy: NEPacketTunnelProvider {

    // MARK: - libcore handles

    private var commandServer: LibboxCommandServer?
    private var boxService: LibboxBoxService?
    private var platformBridge: KernelPlatformBridge?
    private var activeConfig: String?

    // MARK: - Error reporting

    /// Path the extension uses to persist its last fatal error so
    /// Runner can read it after relaunch.
    public static let lastErrorMarker = ProfilePathResolver.extensionErrorMarker

    // MARK: - Lifecycle entry points

    override open func startTunnel(options: [String: NSObject]?) async throws {
        // Reset stale error markers from previous runs.
        try? FileManager.default.removeItem(at: Self.lastErrorMarker)

        let disableMemoryLimit = (options?["DisableMemoryLimit"] as? NSString as? String ?? "NO") == "YES"

        guard let rawConfig = options?["Config"] as? NSString as? String else {
            recordFatal("[Tunnel] no config supplied; aborting startup")
            return
        }
        guard let normalised = KernelEngine.normaliseConfig(rawConfig) else {
            recordFatal("[Tunnel] config rejected as invalid JSON")
            return
        }
        activeConfig = normalised

        // Make sure the App Group working dir exists. libcore mmaps a
        // few files in here so creation must precede LibboxSetup.
        do {
            try FileManager.default.createDirectory(
                at: ProfilePathResolver.runtimeWorkingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            recordFatal("[Tunnel] cannot create working dir: \(error.localizedDescription)")
            return
        }

        LibboxSetup(
            ProfilePathResolver.sharedContainer.relativePath,
            ProfilePathResolver.runtimeWorkingDirectory.relativePath,
            ProfilePathResolver.cacheDirectory.relativePath,
            false
        )

        var redirectError: NSError?
        LibboxRedirectStderr(
            ProfilePathResolver.cacheDirectory.appendingPathComponent("stderr.log").relativePath,
            &redirectError
        )
        if let redirectError {
            recordNonFatal("[Tunnel] stderr redirect failed: \(redirectError.localizedDescription)")
        }

        LibboxSetMemoryLimit(!disableMemoryLimit)

        // Spin up the command server before the kernel itself so log
        // lines emitted during start can flow back to Runner.
        let bridge = platformBridge ?? KernelPlatformBridge(self)
        platformBridge = bridge

        let server = LibboxNewCommandServer(bridge, Int32(30))
        do {
            try server?.start()
        } catch {
            recordFatal("[Tunnel] command server failed to start: \(error.localizedDescription)")
            return
        }
        commandServer = server
        forwardKernelLine("[Tunnel] command server ready")

        await launchKernel()
    }

    override open func stopTunnel(with reason: NEProviderStopReason) async {
        forwardKernelLine("[Tunnel] shutting down, reason=\(reason)")
        teardownKernel()
        if let server = commandServer {
            // Allow in-flight log writes to flush before we close.
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            try? server.close()
            commandServer = nil
        }
    }

    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        // Concrete subclass handles real messages; pass-through default
        // so unknown messages get echoed (useful for debugging).
        messageData
    }

    override open func sleep() async {
        boxService?.pause()
    }

    override open func wake() {
        boxService?.wake()
    }

    // MARK: - Kernel control

    /// Asynchronous kernel start. Splits out from `startTunnel` so the
    /// reload path can reuse it.
    private func launchKernel() async {
        guard let activeConfig else { return }
        var error: NSError?
        let service = LibboxNewService(activeConfig, platformBridge, &error)
        if let error {
            recordNonFatal("[Tunnel] LibboxNewService failed: \(error.localizedDescription)")
            return
        }
        guard let service else { return }
        do {
            try service.start()
        } catch {
            recordNonFatal("[Tunnel] kernel start failed: \(error.localizedDescription)")
            return
        }
        boxService = service
        commandServer?.setService(service)
    }

    private func teardownKernel() {
        if let service = boxService {
            do {
                try service.close()
            } catch {
                recordNonFatal("[Tunnel] kernel close failed: \(error.localizedDescription)")
            }
            boxService = nil
            commandServer?.setService(nil)
        }
        platformBridge?.discardCachedSettings()
    }

    /// Triggered by libcore (`serviceReload()`). Bounces the kernel
    /// while keeping the OS tunnel session alive.
    func reloadKernelService() async {
        forwardKernelLine("[Tunnel] reloading kernel service")
        reasserting = true
        defer { reasserting = false }
        teardownKernel()
        await launchKernel()
    }

    // MARK: - Logging helpers

    /// Write a line that should appear in both the command server's
    /// log stream (consumed by Runner) and, if possible, NSLog.
    func forwardKernelLine(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(message)
        } else {
            NSLog("%@", message)
        }
    }

    /// Soft error: log it and persist to the marker file so Runner can
    /// pick it up on next launch.
    private func recordNonFatal(_ message: String) {
        forwardKernelLine(message)
        try? message.write(to: Self.lastErrorMarker, atomically: true, encoding: .utf8)
    }

    /// Hard error: same as non-fatal but additionally tears the tunnel
    /// down so the OS marks the session as failed.
    private func recordFatal(_ message: String) {
        #if DEBUG
        NSLog("%@", message)
        #endif
        recordNonFatal(message)
        cancelTunnelWithError(NSError(domain: message, code: 0))
    }
}
