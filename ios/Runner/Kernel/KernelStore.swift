//
//  KernelStore.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  协调器的持久化：`intent.json` 的唯一写者（iOS 设计 §3）。
//  最近一次被受理的 LaunchSpec 与 desired，加上「扩展下次启动该读哪份最终配置」。
//  所有写入走同一把锁、写整份内存内容，因此后一次写入必然包含前一次。
//

import Foundation

final class KernelStore {
    private let intentURL: URL
    private let stateURL: URL
    private let lock = NSLock()
    private var intent: KernelIntent

    /// `known == false` 表示文件存在但读不出来（损坏 / 版本不认识）：不知道里面引用了什么，
    /// 快照的 `retainedConfigPaths` 因此报「未知」。
    let loadedSpec: LaunchSpec?
    let loadedKnown: Bool

    init(intentURL: URL, stateURL: URL) {
        self.intentURL = intentURL
        self.stateURL = stateURL
        let exists = FileManager.default.fileExists(atPath: intentURL.path)
        if let existing = KernelFile.read(KernelIntent.self, from: intentURL),
           existing.version == KernelIntent.currentVersion {
            intent = existing
            loadedSpec = existing.spec
            loadedKnown = true
        } else {
            intent = KernelIntent(desired: .off, launchId: "", spec: nil, finalConfigPath: nil)
            loadedSpec = nil
            loadedKnown = !exists
        }
    }

    /// 当前内存里的意图（测试与诊断用）。
    var current: KernelIntent {
        lock.lock(); defer { lock.unlock() }
        return intent
    }

    /// 协调器接受新意图时写：desired 与（若有）spec。返回是否确认落盘。
    func commitIntent(desired: Desired, spec: LaunchSpec?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        intent.desired = desired
        if let spec { intent.spec = spec }
        return KernelFile.write(intent, to: intentURL)
    }

    /// 启动 / 重载前写：新的 `launchId` 与已拼好的最终配置。扩展只看这些字段。
    /// 不碰 `desired`：它只由 `commitIntent` 按核心的受理顺序写。
    func commitLaunch(launchId: String, spec: LaunchSpec, built: BuiltConfig) -> Bool {
        lock.lock(); defer { lock.unlock() }
        intent.launchId = launchId
        intent.spec = spec
        intent.finalConfigPath = built.path
        intent.finalRevision = built.revision
        return KernelFile.write(intent, to: intentURL)
    }

    /// 扩展最近写下的事实；缺失 / 损坏返回 nil。
    func readExtensionState() -> ExtensionState? {
        KernelFile.read(ExtensionState.self, from: stateURL)
    }
}
