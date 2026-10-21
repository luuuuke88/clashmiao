package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CompletableDeferred

/**
 * 「等默认网络」的登记表。登记与撤销都在锁里直接做，不经 actor 的消息队列：
 * actor 忙（或一直没有网络事件）时，被取消的等待也能立刻被摘掉，不会因为撤销消息投递失败而留在表里。
 *
 * 顺序保证：调用方先 `cancel()` 自己的 deferred、再 [forget]；[add] 在锁内看到已结束的 deferred 就不登记。
 * 所以不论「登记」还是「撤销」谁先到（登记的消息可能还排在 actor 队列里），取消过的等待都不会留下。
 */
internal class NetworkWaiters<N : Any> {
    private val lock = Any()
    private val waiters = ArrayList<CompletableDeferred<N>>()

    /** 登记一个等待；已经结束（完成或被取消）的不登记。 */
    fun add(waiter: CompletableDeferred<N>) {
        synchronized(lock) {
            if (!waiter.isCompleted) waiters += waiter
        }
    }

    /** 撤销登记（等待方被取消）。 */
    fun forget(waiter: CompletableDeferred<N>) {
        synchronized(lock) { waiters.remove(waiter) }
    }

    /** 用 [network] 叫醒全部等待并清空。 */
    fun completeAll(network: N) {
        val snapshot = synchronized(lock) { waiters.toList().also { waiters.clear() } }
        snapshot.forEach { it.complete(network) }
    }

    fun size(): Int = synchronized(lock) { waiters.size }
}
