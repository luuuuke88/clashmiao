//
//  KernelEngine.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Helpers that turn the raw config string Runner hands us into
//  something libcore is happy to consume. Today this is mostly a
//  passthrough validator – the bulk of the config is already built by
//  `KernelBridge.buildFullConfig` on the Runner side. Keep the file as
//  a single chokepoint in case we need to inject TUN parameters or
//  clash-api overrides later.
//

import Foundation

/// Static helpers; no instance state. Kept as an enum to prevent
/// accidental instantiation.
enum KernelEngine {

    /// Normalise / sanity-check the user-supplied config blob.
    ///
    /// Returns nil only if the string is not valid JSON; otherwise the
    /// (possibly re-serialised) JSON is returned verbatim. We avoid
    /// mutating the config on iOS – every required field is already
    /// injected on the Runner side so the extension only ever sees a
    /// finalised payload.
    ///
    /// `mtu` is currently unused but left in the signature so callers
    /// can forward NETunnelProviderProtocol options here without churn.
    static func normaliseConfig(_ raw: String, mtu: Int = 9000) -> String? {
        guard
            let data = raw.data(using: .utf8),
            (try? JSONSerialization.jsonObject(
                with: data,
                options: [.mutableLeaves, .mutableContainers]
            )) as? [String: Any] != nil
        else {
            return nil
        }
        // Pass through unmodified for now. Future hook point: inject
        // clash-api / tun / log overrides on the extension side.
        return raw
    }
}
