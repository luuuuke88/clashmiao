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

    /// Root bundle id used to derive the App Group identifier and the
    /// network extension's provider bundle.
    var clashMiaoBundleRoot: String {
        guard let value = infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String else {
            fatalError("[ClashMiao] BASE_BUNDLE_IDENTIFIER missing from Info.plist")
        }
        return value
    }
}
