//
//  PigeonBridge.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//

import Flutter
import Foundation

/// iOS implementation of the Pigeon-generated BoxHostApi protocol.
///
/// 连接生命周期（`getSnapshot` / `request` / `acknowledgeReplay` / `selectOutbound`）全部转给进程级
/// `KernelCoordinator`；其余是内核配置与工具类调用。所有回调都在主线程完成（Pigeon 的要求）。
final class PigeonBridge: BoxHostApi {

    private var coordinator: KernelCoordinator { KernelHost.shared.coordinator }
    private var controller: TunnelController { KernelHost.shared.controller }

    // MARK: - Lifecycle

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        prepare(completion)
    }

    /// `baseDir`/`workingDir`/`tempDir` 有意不消费：内核真正落盘的位置由 `ProfilePathResolver` 统一计算
    /// （`AppDelegate.seedSharedFilesystem()` 在进程启动时已经建好目录并 chdir 过），Runner 和 packet-tunnel
    /// extension 是两个独立沙盒进程，必须共享同一份原生侧算出来的 App Group 容器路径，不能各自按 Dart
    /// 传来的值再算一遍。Dart 侧真正需要 App Group 路径时走 `getAppGroupWorkingDirectory()`；
    /// 下面的 assert 只是 DEBUG 期回归哨兵。
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
        prepare(completion)
    }

    /// 内核一次性初始化；首次运行时尽早弹出系统「添加 VPN 配置」授权，避免它落在第一次连接的 30 s 里。
    /// 授权被拒不在这里报错：真正连接时会以 `permissionDenied` 如实失败。
    private func prepare(_ completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [controller, coordinator] in
            KernelBridge.bootOnce()
            if controller.currentStatus == .invalid {
                do {
                    try controller.ensureConfigured()
                } catch {
                    NSLog("[ClashMiao] initial VPN configuration not saved: %@", String(describing: error))
                }
            }
            coordinator.resync()
            DispatchQueue.main.async { completion(.success(())) }
        }
    }

    func getAppGroupWorkingDirectory(completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(ProfilePathResolver.runtimeWorkingDirectory.path))
    }

    // MARK: - Config

    func validateConfig(
        req: ValidateConfigRequest,
        completion: @escaping (Result<ValidateConfigResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let errorMessage = KernelBridge.parseProfile(at: req.path, tempPath: req.tempPath, debug: req.debug)
            DispatchQueue.main.async { completion(.success(ValidateConfigResult(error: errorMessage))) }
        }
    }

    func changeConfigOptions(options: ConfigOptions, completion: @escaping (Result<Void, Error>) -> Void) {
        TunnelProfile.shared.configOptions = options.jsonOptions
        completion(.success(()))
    }

    func generateFullConfig(path: String, completion: @escaping (Result<String?, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String?, Error>
            do {
                result = .success(try KernelBridge.buildFullConfig(profilePath: path, options: TunnelProfile.shared.configOptions))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - 连接生命周期（B spec §2 / §10）

    func getSnapshot(completion: @escaping (Result<KernelSnapshotMsg, Error>) -> Void) {
        // 绝不在管理器加载、事实读入之前发默认 stopped；超时让 Dart 的退避重试接管。
        coordinator.whenReady(timeout: 1.5) { [coordinator] ready in
            let result: Result<KernelSnapshotMsg, Error> = ready
                ? .success(coordinator.snapshot.toMsg())
                : .failure(PigeonError(code: "unavailable", message: "kernel coordinator is still starting", details: nil))
            DispatchQueue.main.async { completion(result) }
        }
    }

    func request(req: DesiredRequestMsg, completion: @escaping (Result<ReceiptMsg, Error>) -> Void) {
        func fail(_ code: String, _ message: String) {
            completion(.failure(PigeonError(code: code, message: message, details: nil)))
        }
        guard let desired = Desired(rawValue: req.desired) else {
            return fail("invalidRequest", "unknown desired '\(req.desired)'")
        }
        var launch: LaunchSpec?
        if let l = req.launch {
            launch = LaunchSpec(
                runtimeConfigPath: l.runtimeConfigPath, optionsJson: l.optionsJson,
                profileName: l.profileName, configRevision: l.configRevision
            )
        }
        if desired == .on, launch == nil {
            return fail("invalidRequest", "desired=on requires a launch spec")
        }
        coordinator.whenReady(timeout: 1.5) { [coordinator] ready in
            guard ready else {
                DispatchQueue.main.async { fail("unavailable", "kernel coordinator is still starting") }
                return
            }
            let r = coordinator.request(epoch: req.epoch, seq: req.seq, desired: desired, launch: launch, reason: req.reason)
            let msg = ReceiptMsg(accepted: r.accepted, reason: r.reason?.rawValue, epoch: r.epoch, appliedSeq: r.appliedSeq)
            DispatchQueue.main.async { completion(.success(msg)) }
        }
    }

    func acknowledgeReplay(attempt: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        coordinator.acknowledgeReplay(attempt)
        completion(.success(()))
    }

    /// 旧 start / stop / restart：Dart 已不调用。与其留一条绕过协调器的旁路，不如显式失败。
    func start(req: StartRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(PigeonError(code: "unsupported", message: "use request(): lifecycle is owned by the coordinator", details: nil)))
    }

    func stop(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(PigeonError(code: "unsupported", message: "use request(): lifecycle is owned by the coordinator", details: nil)))
    }

    func restart(req: StartRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(PigeonError(code: "unsupported", message: "use request(): lifecycle is owned by the coordinator", details: nil)))
    }

    /// 对同一配置强制重载一次（desired=on 且已就绪时才有意义，否则无操作）。
    func resetTunnel(completion: @escaping (Result<Void, Error>) -> Void) {
        coordinator.requestReload(.app)
        completion(.success(()))
    }

    // MARK: - Outbound control

    func selectOutbound(req: SelectOutboundRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !req.groupTag.trimmingCharacters(in: .whitespaces).isEmpty,
              !req.outboundTag.trimmingCharacters(in: .whitespaces).isEmpty else {
            completion(.failure(PigeonError(code: "selectOutbound", message: "selectOutbound requires non-blank groupTag and outboundTag", details: nil)))
            return
        }
        coordinator.selectOutbound(group: req.groupTag, outbound: req.outboundTag, expectedAttempt: req.expectedAttempt) { result in
            let mapped: Result<Void, Error>
            switch result {
            case .ok: mapped = .success(())
            case .stale(let m): mapped = .failure(PigeonError(code: "stale", message: m, details: nil))
            case .failed(let m): mapped = .failure(PigeonError(code: "selectOutbound", message: m, details: nil))
            }
            DispatchQueue.main.async { completion(mapped) }
        }
    }

    func urlTest(groupTag: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Void, Error>
            do {
                try KernelBridge.withStandaloneClient { try $0.urlTest(groupTag) }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
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

    func getAppIconBase64(packageName: String, completion: @escaping (Result<String?, Error>) -> Void) {
        completion(.success(nil))
    }
}

extension KernelSnapshot {
    /// 与 `toWireMap()` 同值：Pigeon 查询与事件通道必须来自同一状态源、同一份字段。
    func toMsg() -> KernelSnapshotMsg {
        KernelSnapshotMsg(
            epoch: epoch,
            version: version,
            status: status.rawValue,
            attempt: attempt,
            desired: desired.rawValue,
            source: source.rawValue,
            appliedSeq: appliedSeq,
            activeConfigRevision: activeConfigRevision,
            lastFailure: lastFailure.map {
                KernelFailureMsg(code: $0.code.rawValue, message: $0.message, attempt: $0.attempt, seq: $0.seq)
            },
            selectionsReplayNeeded: selectionsReplayNeeded,
            retainedConfigPaths: retainedConfigPaths
        )
    }
}
