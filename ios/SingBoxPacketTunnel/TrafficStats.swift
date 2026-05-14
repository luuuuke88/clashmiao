//
//  TrafficStats.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Reads cumulative traffic counters from the running kernel and hands
//  them to the extension to surface back to Runner. We poll the
//  Clash-compatible /traffic WebSocket exposed by libcore; the
//  extension owns this object's lifetime and tears it down on stop.
//

import Foundation

/// One traffic delta emitted by the kernel. Units are bytes.
struct TrafficDelta: Codable {
    let up: Int64
    let down: Int64
}

/// Polls the kernel's local HTTP/WS endpoint for traffic deltas.
///
/// Notes on the implementation:
/// - We can't connect immediately on init: the kernel's HTTP server
///   takes a moment to come up after `LibboxBoxService.start()`. We
///   probe with a short delay then poll until 200.
/// - Once the WebSocket is open, the handler is recursive: each
///   incoming frame triggers another `receive` call.
final class TrafficStatsReader {

    /// Where libcore exposes its clash-compat external controller.
    /// Keep aligned with the value injected into the sing-box config
    /// by `KernelEngine.normaliseConfig`.
    private static let controllerEndpoint = "127.0.0.1:10864"

    private var webSocketTask: URLSessionWebSocketTask?
    private let onDelta: (TrafficDelta) -> Void

    init(onDelta: @escaping (TrafficDelta) -> Void) {
        self.onDelta = onDelta
        Task(priority: .background) { [weak self] in
            await self?.boot()
        }
    }

    deinit {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    /// Wait for the kernel HTTP endpoint to start serving, then open
    /// the WebSocket. We deliberately don't surface failures – this is
    /// a best-effort telemetry stream.
    private func boot() async {
        // Give the kernel a head start before we start hammering it.
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        guard let probeURL = URL(string: "http://\(Self.controllerEndpoint)") else {
            return
        }

        while !Task.isCancelled {
            do {
                let (_, response) = try await URLSession.shared.data(from: probeURL)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (200..<300).contains(status) { break }
            } catch {
                // not up yet – retry
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        guard let wsURL = URL(string: "ws://\(Self.controllerEndpoint)/traffic") else {
            return
        }
        let task = URLSession.shared.webSocketTask(with: wsURL)
        webSocketTask = task
        pump()
        task.resume()
    }

    /// Recursive read loop. We don't reschedule on `.failure` to avoid
    /// busy-spinning when the kernel goes away.
    private func pump() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                return
            case .success(let frame):
                if case .string(let text) = frame,
                   let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(TrafficDelta.self, from: data) {
                    self.onDelta(decoded)
                }
                self.pump()
            }
        }
    }
}
