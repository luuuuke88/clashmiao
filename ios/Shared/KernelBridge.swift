//
//  KernelBridge.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Tiny convenience layer above libcore's free C functions. We want a
//  single, well-named place that everything else (handlers, the VPN
//  manager, tests) can route through – it gives us a chokepoint for
//  logging, error wrapping and future swapping of the underlying core.
//

import Foundation
import Libcore

/// Errors surfaced from libcore in a Swift-native form.
///
/// libcore raises `NSError`s with opaque domains; we wrap them so
/// callers can pattern-match without sprinkling `as NSError` everywhere.
public enum KernelBridgeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case kernelFailed(code: Int, message: String)

    public var description: String {
        switch self {
        case .invalidArguments(let detail):
            return "[ClashMiao] invalid arguments: \(detail)"
        case .kernelFailed(let code, let message):
            return "[ClashMiao] kernel error (\(code)): \(message)"
        }
    }
}

/// Static facade around the global libcore entry points. Stateless –
/// instances would be misleading because libcore itself holds the state.
public enum KernelBridge {

    // MARK: - Lifecycle

    /// Run libcore's one-time process setup. Idempotent in practice.
    public static func bootOnce() {
        var error: NSError?
        MobileSetup(&error)
    }

    // MARK: - Configuration helpers

    /// Validate a sing-box profile file. Returns nil on success, the
    /// human-readable error string otherwise. We never throw here –
    /// validation is a UI-driven operation and callers expect a
    /// message they can show inline.
    public static func parseProfile(at path: String,
                                    tempPath: String,
                                    debug: Bool) -> String? {
        var error: NSError?
        MobileParse(path, tempPath, debug, &error)
        return error?.localizedDescription
    }

    /// Build the final sing-box config given the user profile path and
    /// the JSON options blob. Throws on failure so the caller can map
    /// onto a Flutter error response.
    public static func buildFullConfig(profilePath: String,
                                       options: String) throws -> String {
        var error: NSError?
        let config = MobileBuildConfig(profilePath, options, &error)
        if let error {
            throw KernelBridgeError.kernelFailed(
                code: error.code,
                message: error.localizedDescription
            )
        }
        return config
    }

    /// Generate a fresh WARP credential. Used by the Cloudflare-WARP
    /// onboarding flow.
    public static func generateWarpCredential(licenseKey: String,
                                              previousAccountId: String,
                                              previousAccessToken: String) -> String {
        return MobileGenerateWarpConfig(
            licenseKey,
            previousAccountId,
            previousAccessToken,
            nil
        )
    }

    // MARK: - Runtime control

    /// Convenience for issuing a one-off command against the running
    /// kernel without holding a long-lived client. Used by the
    /// outbound-selection and url-test methods.
    public static func withStandaloneClient<T>(
        _ body: (LibboxCommandClient) throws -> T
    ) throws -> T {
        // libcore reads cwd-relative paths internally – align it with
        // the shared container first so the standalone client can find
        // the command socket.
        FileManager.default.changeCurrentDirectoryPath(
            ProfilePathResolver.sharedContainer.path
        )
        guard let client = LibboxNewStandaloneCommandClient() else {
            throw KernelBridgeError.kernelFailed(
                code: -1,
                message: "failed to create standalone command client"
            )
        }
        return try body(client)
    }
}
