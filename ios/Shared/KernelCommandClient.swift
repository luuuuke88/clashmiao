//
//  KernelCommandClient.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Thin wrapper around libcore's `LibboxCommandClient`. The kernel runs
//  inside the network extension, which opens a unix-domain command
//  socket. Both the extension itself and the main app process talk to
//  that socket through this client; subscribers are notified via
//  `@Published` properties so SwiftUI / Combine pipelines stay tidy.
//

import Foundation
import Libcore

/// Live connection to the running kernel's command socket.
///
/// Each instance handles a *single* topic. Spin up multiple clients if
/// you need both logs and status; they share the underlying socket via
/// libcore but logically present independent streams.
public class KernelCommandClient: ObservableObject {

    /// What kind of data this client is interested in.
    public enum Topic {
        case runtimeStatus       // uplink/downlink/connection counters
        case proxyGroups         // outbound groups + their currently selected node
        case proxyGroupsLite     // groups without per-item delays (cheaper)
        case kernelLog           // streaming text log
    }

    // MARK: - Tunables

    private let topic: Topic
    private let maxBufferedLogLines: Int

    // MARK: - libcore handles

    private var nativeClient: LibboxCommandClient?
    private var connectionTask: Task<Void, Error>?

    // MARK: - Published state (consumed by Combine sinks in handlers)

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var latestStatus: LibboxStatusMessage?
    @Published public private(set) var outboundGroups: [OutboundGroupSnapshot]?
    @Published public private(set) var bufferedLogs: [String] = []

    // MARK: - Lifecycle

    public init(_ topic: Topic, maxBufferedLogLines: Int = 300) {
        self.topic = topic
        self.maxBufferedLogLines = maxBufferedLogLines
    }

    /// Begin connecting. Safe to call multiple times – additional calls
    /// while already connected are no-ops; pending attempts are cancelled
    /// and restarted to avoid leaking tasks.
    public func connect() {
        if isConnected { return }
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            await self?.runConnectLoop()
        }
    }

    /// Tear down the socket. Idempotent.
    public func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        if let nativeClient {
            try? nativeClient.disconnect()
            self.nativeClient = nil
        }
    }

    // MARK: - Internal connect loop

    /// libcore's command server can take a moment to come up after the
    /// tunnel starts. We retry with progressive back-off so we don't
    /// race against the extension boot sequence.
    private nonisolated func runConnectLoop() async {
        let options = LibboxCommandClientOptions()
        switch topic {
        case .runtimeStatus:
            options.command = LibboxCommandStatus
        case .proxyGroups:
            options.command = LibboxCommandGroup
        case .proxyGroupsLite:
            options.command = LibboxCommandGroupInfoOnly
        case .kernelLog:
            options.command = LibboxCommandLog
        }
        options.statusInterval = Int64(2 * NSEC_PER_SEC)

        let handler = NativeHandler(owner: self)
        guard let client = LibboxNewCommandClient(handler, options) else {
            return
        }

        // Up to ~3.5s of staggered retries.
        for attempt in 0..<10 {
            let backoffMs = 100 + (attempt * 50)
            try? await Task.sleep(nanoseconds: UInt64(backoffMs) * NSEC_PER_MSEC)
            if Task.isCancelled { break }
            do {
                try client.connect()
                await MainActor.run { [weak self] in
                    self?.nativeClient = client
                }
                return
            } catch {
                // try again
            }
            if Task.isCancelled { break }
        }
        try? client.disconnect()
    }

    // MARK: - libcore callback adapter

    /// Bridges libcore's Objective-C-style protocol back into Swift.
    /// Kept private so callers can't accidentally drive this directly.
    private final class NativeHandler: NSObject, LibboxCommandClientHandlerProtocol {

        private weak var owner: KernelCommandClient?

        init(owner: KernelCommandClient) {
            self.owner = owner
        }

        func connected() {
            DispatchQueue.main.async { [weak self] in
                guard let owner = self?.owner else { return }
                if owner.topic == .kernelLog {
                    owner.bufferedLogs = []
                }
                owner.isConnected = true
            }
        }

        func disconnected(_: String?) {
            DispatchQueue.main.async { [weak self] in
                self?.owner?.isConnected = false
            }
        }

        func clearLog() {
            DispatchQueue.main.async { [weak self] in
                self?.owner?.bufferedLogs.removeAll()
            }
        }

        func writeLog(_ message: String?) {
            guard let message else { return }
            DispatchQueue.main.async { [weak self] in
                guard let owner = self?.owner else { return }
                if owner.bufferedLogs.count > owner.maxBufferedLogLines {
                    owner.bufferedLogs.removeFirst()
                }
                owner.bufferedLogs.append(message)
            }
        }

        func writeStatus(_ message: LibboxStatusMessage?) {
            DispatchQueue.main.async { [weak self] in
                self?.owner?.latestStatus = message
            }
        }

        func writeGroups(_ groupIter: LibboxOutboundGroupIteratorProtocol?) {
            guard let groupIter else { return }
            var collected: [OutboundGroupSnapshot] = []
            while groupIter.hasNext() {
                guard let group = groupIter.next() else { continue }
                var items: [OutboundItemSnapshot] = []
                let itemsIter = group.getItems()
                while itemsIter?.hasNext() ?? false {
                    if let item = itemsIter?.next() {
                        items.append(OutboundItemSnapshot(
                            tag: item.tag,
                            type: item.type,
                            urlTestDelay: Int(item.urlTestDelay)
                        ))
                    }
                }
                collected.append(OutboundGroupSnapshot(
                    tag: group.tag,
                    type: group.type,
                    selected: group.selected,
                    items: items
                ))
            }
            DispatchQueue.main.async { [weak self] in
                self?.owner?.outboundGroups = collected
            }
        }

        // Clash-mode hooks are unused by ClashMiao for now. Kept as
        // explicit no-ops so libcore doesn't complain about an
        // incomplete protocol implementation.
        func initializeClashMode(_: LibboxStringIteratorProtocol?, currentMode _: String?) {}
        func updateClashMode(_: String?) {}
    }
}

// MARK: - Snapshot DTOs

/// JSON-encodable description of a single outbound option inside a group.
/// Field names mirror what the Dart `OutboundItem` model expects.
public struct OutboundItemSnapshot: Codable {
    public let tag: String
    public let type: String
    public let urlTestDelay: Int

    enum CodingKeys: String, CodingKey {
        case tag
        case type
        case urlTestDelay = "url-test-delay"
    }
}

/// JSON-encodable description of an outbound group.
public struct OutboundGroupSnapshot: Codable {
    public let tag: String
    public let type: String
    public let selected: String
    public let items: [OutboundItemSnapshot]
}
