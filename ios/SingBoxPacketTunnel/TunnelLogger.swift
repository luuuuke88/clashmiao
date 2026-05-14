//
//  TunnelLogger.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Append-only log writer used from inside the network extension.
//  The extension process is short-lived and sandboxed, so we serialise
//  writes through a dedicated utility queue and keep an open file
//  handle to avoid re-opening on every line.
//

import Foundation

/// Tiny line-buffered file logger.
///
/// Designed for the extension side where `print` / `NSLog` either get
/// throttled by the system or end up in places Runner can't read. By
/// writing to a path inside the App Group container Runner can stream
/// it back to the Dart side via `LogLinesStream`.
final class TunnelLogger {

    /// Shared dispatch queue – all file I/O for tunnel logging happens
    /// here. `utility` QoS is appropriate: logging shouldn't fight the
    /// proxy/DNS hot path for CPU.
    private static let writeQueue = DispatchQueue(
        label: "\(ProfilePathResolver.bundleRoot).TunnelLogger",
        qos: .utility
    )

    private let destinationURL: URL
    private let fileManager = FileManager.default
    private var cachedHandle: FileHandle?
    private let lock = NSLock()

    init(path: URL) {
        self.destinationURL = path
    }

    /// Append a single line to the log. A trailing newline is added if
    /// the caller didn't include one. Errors are swallowed – the only
    /// reasonable failure mode here is "disk full" and we don't want
    /// the tunnel to crash on that.
    func append(_ message: String) {
        let payload = message.hasSuffix("\n") ? message : message + "\n"
        TunnelLogger.writeQueue.async { [weak self] in
            self?.appendOnQueue(payload)
        }
    }

    private func appendOnQueue(_ payload: String) {
        lock.lock()
        defer { lock.unlock() }
        do {
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try payload.write(to: destinationURL, atomically: true, encoding: .utf8)
                return
            }
            let handle = try resolveHandle()
            try handle.seekToEnd()
            if let data = payload.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Intentionally silent. See doc comment above.
        }
    }

    private func resolveHandle() throws -> FileHandle {
        if let cachedHandle { return cachedHandle }
        let handle = try FileHandle(forWritingTo: destinationURL)
        cachedHandle = handle
        return handle
    }
}
