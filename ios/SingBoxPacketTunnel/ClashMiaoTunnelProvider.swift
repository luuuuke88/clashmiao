//
//  ClashMiaoTunnelProvider.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Concrete NEPacketTunnelProvider that ships in the
//  `SingBoxPacketTunnel` Extension target. The Info.plist points
//  iOS at this class through NSExtensionPrincipalClass.
//
//  Subclass responsibilities are intentionally thin:
//    1. own the traffic-stats counters (the base class owns the kernel),
//    2. answer "stats" app-messages so Runner can poll byte totals.
//

import Foundation
import NetworkExtension

final class ClashMiaoTunnelProvider: KernelProviderProxy {

    // Cumulative byte counters. Updated from the TrafficStatsReader
    // callback; read from `handleAppMessage`. Protected by an NSLock
    // because the two callers run on unrelated queues.
    private let counterLock = NSLock()
    private var uploadedBytes: Int64 = 0
    private var downloadedBytes: Int64 = 0

    /// Holds the polling reader. Optional because we only enable it
    /// once the tunnel is actually up; clearing it stops the loop.
    private var trafficReader: TrafficStatsReader?

    override func startTunnel(options: [String: NSObject]?) async throws {
        try await super.startTunnel(options: options)

        // Kick off the kernel-side traffic poll. Counters accumulate
        // independently from Runner so reconnects don't reset the UI's
        // session total.
        trafficReader = TrafficStatsReader { [weak self] delta in
            guard let self else { return }
            self.counterLock.lock()
            self.uploadedBytes += delta.up
            self.downloadedBytes += delta.down
            self.counterLock.unlock()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        trafficReader = nil
        await super.stopTunnel(with: reason)
    }

    /// Runner asks for `"stats"` once per second through
    /// `sendProviderMessage`. We answer with a tiny CSV payload to
    /// avoid the overhead of JSON encoding/decoding on the hot path.
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        let raw = String(data: messageData, encoding: .utf8)
        switch raw {
        case "stats":
            counterLock.lock()
            let payload = "\(uploadedBytes),\(downloadedBytes)"
            counterLock.unlock()
            return payload.data(using: .utf8)
        default:
            return nil
        }
    }
}
