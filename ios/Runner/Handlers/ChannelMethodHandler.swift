//
//  ChannelMethodHandler.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Implements the iOS side of the `com.clashmiao.app/method`
//  MethodChannel. Method names and argument shapes match the Android
//  MethodHandler.kt contract one-for-one so the Dart layer doesn't
//  need to branch on platform for anything beyond which channel
//  implementation it picks.
//

import Flutter
import Combine
import Libcore

/// FlutterPlugin that bridges Dart -> Swift method calls.
public final class ChannelMethodHandler: NSObject, FlutterPlugin {

    /// Channel name. Built from the SERVICE_IDENTIFIER xcconfig value so
    /// it stays in lock-step with `PlatformBoxService` in Dart.
    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/method"
    }

    /// Supported method names. Keep this enum in sync with
    /// android/.../MethodHandler.kt::Trigger – every value here must
    /// have a matching Kotlin entry.
    private enum Trigger: String {
        case setup = "setup"
        case parseConfig = "parse_config"
        case changeConfigOptions = "change_config_options"
        case generateConfig = "generate_config"
        case start = "start"
        case stop = "stop"
        case restart = "restart"
        case selectOutbound = "select_outbound"
        case urlTest = "url_test"
        case clearLogs = "clear_logs"
        case generateWarpConfig = "generate_warp_config"
    }

    private weak var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = ChannelMethodHandler()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Dispatch

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let trigger = Trigger(rawValue: call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }

        // Helper to bounce results back onto the main thread. Flutter
        // expects MethodChannel results on the platform thread.
        @Sendable func reply(_ value: Any?) async {
            await MainActor.run { result(value) }
        }

        switch trigger {
        case .setup:
            Task {
                KernelBridge.bootOnce()
                do {
                    try await TunnelManager.shared.ensureLoaded()
                } catch {
                    await reply(FlutterError(
                        code: "SETUP_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                await reply(true)
            }

        case .parseConfig:
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String,
                let tempPath = args["tempPath"] as? String,
                let debug = (args["debug"] as? NSNumber)?.boolValue
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            // Returning the error string (or empty on success) matches
            // the Android contract – Dart's `validateConfig` treats an
            // empty / nil string as success.
            if let problem = KernelBridge.parseProfile(at: path,
                                                      tempPath: tempPath,
                                                      debug: debug) {
                result(problem)
            } else {
                result("")
            }

        case .changeConfigOptions:
            guard let options = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            TunnelProfile.shared.configOptions = options
            result(true)

        case .generateConfig:
            guard
                let args = call.arguments as? [String: Any?],
                let path = args["path"] as? String,
                !path.isEmpty
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            do {
                let config = try KernelBridge.buildFullConfig(
                    profilePath: path,
                    options: TunnelProfile.shared.configOptions
                )
                result(config)
            } catch {
                result(FlutterError(
                    code: "BUILD_CONFIG",
                    message: error.localizedDescription,
                    details: nil
                ))
            }

        case .start:
            Task {
                guard
                    let args = call.arguments as? [String: Any?],
                    let path = args["path"] as? String
                else {
                    await reply(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                TunnelProfile.shared.activeConfigPath = path
                TunnelProfile.shared.activeProfileName = (args["name"] as? String) ?? ""

                let config: String
                do {
                    config = try KernelBridge.buildFullConfig(
                        profilePath: path,
                        options: TunnelProfile.shared.configOptions
                    )
                } catch {
                    await reply(FlutterError(
                        code: "BUILD_CONFIG",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                do {
                    try await TunnelManager.shared.ensureLoaded()
                    try await TunnelManager.shared.connect(
                        with: config,
                        disableMemoryLimit: TunnelProfile.shared.disableMemoryLimit
                    )
                } catch {
                    await reply(FlutterError(
                        code: "TUNNEL_START",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                await reply(true)
            }

        case .stop:
            TunnelManager.shared.disconnect()
            result(true)

        case .restart:
            Task {
                guard
                    let args = call.arguments as? [String: Any?],
                    let path = args["path"] as? String
                else {
                    await reply(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                TunnelProfile.shared.activeConfigPath = path
                TunnelProfile.shared.activeProfileName = (args["name"] as? String) ?? ""
                TunnelManager.shared.disconnect()
                await self.awaitDisconnected()

                let config: String
                do {
                    config = try KernelBridge.buildFullConfig(
                        profilePath: path,
                        options: TunnelProfile.shared.configOptions
                    )
                } catch {
                    await reply(FlutterError(
                        code: "BUILD_CONFIG",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                do {
                    try await TunnelManager.shared.ensureLoaded()
                    try await TunnelManager.shared.connect(
                        with: config,
                        disableMemoryLimit: TunnelProfile.shared.disableMemoryLimit
                    )
                } catch {
                    await reply(FlutterError(
                        code: "TUNNEL_RESTART",
                        message: error.localizedDescription,
                        details: nil
                    ))
                    return
                }
                await reply(true)
            }

        case .selectOutbound:
            guard
                let args = call.arguments as? [String: Any?],
                let group = args["groupTag"] as? String,
                let outbound = args["outboundTag"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            do {
                try KernelBridge.withStandaloneClient { client in
                    try client.selectOutbound(group, outboundTag: outbound)
                }
                result(true)
            } catch {
                result(FlutterError(
                    code: "SELECT_OUTBOUND",
                    message: error.localizedDescription,
                    details: nil
                ))
            }

        case .urlTest:
            guard
                let args = call.arguments as? [String: Any?],
                let group = args["groupTag"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            do {
                try KernelBridge.withStandaloneClient { client in
                    try client.urlTest(group)
                }
                result(true)
            } catch {
                result(FlutterError(
                    code: "URL_TEST",
                    message: error.localizedDescription,
                    details: nil
                ))
            }

        case .clearLogs:
            // Logs live entirely in the streaming pipeline today; we
            // ack the call so Dart's contract is satisfied. If/when we
            // add an on-disk log buffer this is where we truncate it.
            result(true)

        case .generateWarpConfig:
            guard
                let args = call.arguments as? [String: Any],
                let licenseKey = args["license-key"] as? String,
                let accountId = args["previous-account-id"] as? String,
                let accessToken = args["previous-access-token"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let warp = KernelBridge.generateWarpCredential(
                licenseKey: licenseKey,
                previousAccountId: accountId,
                previousAccessToken: accessToken
            )
            result(warp)
        }
    }

    // MARK: - Internal helpers

    /// Suspend until the OS reports the VPN as `.disconnected`. Used by
    /// the `restart` path so we don't race the bring-up against the
    /// in-flight tear-down. 500ms grace mirrors the kernel's own
    /// shutdown timing.
    private func awaitDisconnected() async {
        await withCheckedContinuation { continuation in
            var token: AnyCancellable?
            token = TunnelManager.shared.$state
                .filter { $0 == .disconnected || $0 == .invalid }
                .first()
                .delay(for: 0.5, scheduler: RunLoop.main)
                .sink { _ in
                    continuation.resume()
                    token?.cancel()
                }
        }
    }
}
