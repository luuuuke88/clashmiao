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

    /// `baseDir`/`workingDir`/`tempDir` 有意不消费：sing-box 内核真正落盘的
    /// 位置由 `ProfilePathResolver` 统一计算（`AppDelegate.seedSharedFilesystem()`
    /// 在进程启动时已经建好目录并 chdir 过），Runner 和 packet-tunnel extension
    /// 是两个独立沙盒进程，必须共享同一份原生侧算出来的 App Group 容器路径，
    /// 不能各自按 Dart 传来的值再算一遍——那样两边可能算出不一致的目录。
    /// Android 侧 `PigeonBridge.kt.setup()` 同理忽略这三个参数（`Libbox.setup`
    /// 走自己的 baseDir/getExternalFilesDir/cacheDir）。
    ///
    /// Dart 侧真正需要 App Group 路径时（`RuleSetProvisioner` 写 .srs、
    /// `RuntimeConfigBuilder` 往 runtime-config.json 里嵌 rule_set 绝对路径），
    /// 走 `getAppGroupWorkingDirectory()`，不依赖这里传入的值——下面的
    /// assert 只是一道 DEBUG 期回归哨兵：如果 Dart 侧目录解析逻辑退化回
    /// `path_provider` 的私有沙盒路径，这里能第一时间炸出来，而不是等到
    /// "智能模式在 iOS 上读不到规则文件" 这种难排查的现象。
    func setup(
        baseDir: String,
        workingDir: String,
        tempDir: String,
        debug: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if DEBUG
        assert(
            workingDir.hasPrefix(ProfilePathResolver.sharedContainer.path),
            "[ClashMiao] setup() 收到的 workingDir 不在 App Group 容器内: " +
            "\(workingDir) —— iOS 目录解析是不是退回 path_provider 私有沙盒了？"
        )
        #endif
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

    /// 见 pigeons/box_api.dart 里的方法文档：Dart 侧 iOS 分支用这个查询
    /// App Group 共享容器内 sing-box 运行时文件应该落地的目录。
    /// `runtimeWorkingDirectory` 而不是 `sharedContainer` 根目录——跟
    /// `AppDelegate.seedSharedFilesystem()` / `KernelProviderProxy` 用的是
    /// 同一个目录常量，这里不需要额外 mkdir（进程启动时已经建好）。
    func getAppGroupWorkingDirectory(
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        completion(.success(ProfilePathResolver.runtimeWorkingDirectory.path))
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
