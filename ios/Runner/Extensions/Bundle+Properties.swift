//
//  Bundle+Properties.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Looks up the build-time identifiers we injected via Base.xcconfig.
//  Force-unwrapping is intentional: if these keys are missing the app
//  is misconfigured and we want to learn about it on first launch
//  rather than days later when something else fails mysteriously.
//

import Foundation

extension Bundle {

    /// Method/Event channel namespace. Matches the Dart-side prefix in
    /// `PlatformBoxService._channelPrefix`.
    var channelNamespace: String {
        guard let value = infoDictionary?["SERVICE_IDENTIFIER"] as? String else {
            fatalError("[ClashMiao] SERVICE_IDENTIFIER missing from Info.plist")
        }
        return value
    }

    /// Bundle id of the embedded packet tunnel extension. Xcode requires an
    /// embedded extension's id to be prefixed by the host app's id, so it
    /// is derived from `bundleIdentifier` — not from BASE_BUNDLE_IDENTIFIER,
    /// which is only the App Group root and does not share that prefix.
    var tunnelProviderBundleIdentifier: String {
        guard let value = bundleIdentifier else {
            fatalError("[ClashMiao] CFBundleIdentifier missing from Info.plist")
        }
        return value + ".SingBoxPacketTunnel"
    }
}
