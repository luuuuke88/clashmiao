//
//  BlockingRunner.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  libcore's exported protocols require synchronous Objective-C
//  methods (they can't be `async`). The Swift code that backs those
//  methods, however, is naturally async. This file bridges the gap
//  with a semaphore-blocking trampoline.
//
//  NOTE: do not call these from the main thread or from any actor
//  that the awaited code might need to hop back to – it will
//  deadlock. They're intended for libcore callback contexts only.
//

import Foundation
import Libcore
import NetworkExtension

/// Run an async closure synchronously, returning its result.
/// Only safe to call from a background thread.
func awaitBlocking<T>(_ work: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let slot = ResultSlot<T>()
    Task.detached {
        slot.value = await work()
        semaphore.signal()
    }
    semaphore.wait()
    return slot.value!
}

/// Throwing variant of `awaitBlocking`. Errors propagate up to the
/// caller via the standard `throws` mechanism.
func awaitBlockingThrowing<T>(_ work: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let slot = ResultSlot<T>()
    Task.detached {
        do {
            slot.value = try await work()
        } catch {
            slot.error = error
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let error = slot.error {
        throw error
    }
    return slot.value!
}

/// Reference-type result holder so the detached task can mutate it
/// across the semaphore boundary without value-type copy semantics.
private final class ResultSlot<T> {
    var value: T?
    var error: Error?
}
