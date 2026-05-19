//
//  PigeonBridge.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//

import Flutter
import Combine

/// iOS implementation of the Pigeon-generated BoxHostApi protocol.
///
/// Registered via BoxHostApiSetup.setUp in AppDelegate so Dart's
/// PlatformBoxService can call into the native tunnel layer with
/// full type-safety.
final class PigeonBridge: BoxHostApi {

    // MARK: - Lifecycle

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            KernelBridge.bootOnce()
            do {
                try await TunnelManager.shared.ensureLoaded()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func setup(
        baseDir: String,
        workingDir: String,
        tempDir: String,
        debug: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            KernelBridge.bootOnce()
            do {
                try await TunnelManager.shared.ensureLoaded()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Config

    func validateConfig(
        req: ValidateConfigRequest,
        completion: @escaping (Result<ValidateConfigResult, Error>) -> Void
    ) {
        let errorMessage = KernelBridge.parseProfile(
            at: req.path,
            tempPath: req.tempPath,
            debug: req.debug
        )
        completion(.success(ValidateConfigResult(error: errorMessage)))
    }

    func changeConfigOptions(
        options: ConfigOptions,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        TunnelProfile.shared.configOptions = options.jsonOptions
        completion(.success(()))
    }

    func generateFullConfig(
        path: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        do {
            let config = try KernelBridge.buildFullConfig(
                profilePath: path,
                options: TunnelProfile.shared.configOptions
            )
            completion(.success(config))
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Tunnel control

    func start(req: StartRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            TunnelProfile.shared.activeConfigPath = req.configPath
            TunnelProfile.shared.activeProfileName = req.profileName
            do {
                let config = try KernelBridge.buildFullConfig(
                    profilePath: req.configPath,
                    options: TunnelProfile.shared.configOptions
                )
                try await TunnelManager.shared.ensureLoaded()
                try await TunnelManager.shared.connect(
                    with: config,
                    disableMemoryLimit: TunnelProfile.shared.disableMemoryLimit
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        TunnelManager.shared.disconnect()
        completion(.success(()))
    }

    func restart(req: StartRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            TunnelProfile.shared.activeConfigPath = req.configPath
            TunnelProfile.shared.activeProfileName = req.profileName
            TunnelManager.shared.disconnect()
            await awaitDisconnected()
            do {
                let config = try KernelBridge.buildFullConfig(
                    profilePath: req.configPath,
                    options: TunnelProfile.shared.configOptions
                )
                try await TunnelManager.shared.ensureLoaded()
                try await TunnelManager.shared.connect(
                    with: config,
                    disableMemoryLimit: TunnelProfile.shared.disableMemoryLimit
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func resetTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            await TunnelManager.shared.resetTunnel()
            completion(.success(()))
        }
    }

    // MARK: - Outbound control

    func selectOutbound(
        req: SelectOutboundRequest,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            try KernelBridge.withStandaloneClient { client in
                try client.selectOutbound(req.groupTag, outboundTag: req.outboundTag)
            }
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    func urlTest(groupTag: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try KernelBridge.withStandaloneClient { client in
                try client.urlTest(groupTag)
            }
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Logs

    func clearLogs(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    // MARK: - App list (iOS stub)

    func getInstalledApps(completion: @escaping (Result<[InstalledApp], Error>) -> Void) {
        completion(.success([]))
    }

    func getAppIconBase64(
        packageName: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        completion(.success(nil))
    }

    // MARK: - Helpers

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
