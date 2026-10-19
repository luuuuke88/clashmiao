package com.clashmiao.clashmiao.engine

/**
 * 执行层调用的内核运行时（spec §3「执行层通过接口 KernelRuntime 注入」）。
 *
 * 所有方法只会在 [KernelExecutor] 的唯一后台线程上被调用，且同一时刻至多一个在执行；
 * 方法内部可以阻塞（libbox 调用不可中断）。命令层（主线程）永远不会直接调用它们。
 *
 * 资源归属约定：[start] 创建的任何东西（包括尚未交付的局部实例）一出现就记在 runtime 自己名下，
 * 所以无论 [start] 以成功、取消还是失败返回，协调器随后发出的 [teardown] 都能完整回收，
 * 不存在「局部实例没人管」的窗口。
 */
interface KernelRuntime {

    /**
     * 完成「bootstrap → command server → 配置 → 创建服务 → start」整条启动链。
     *
     * 每个阻塞步骤之前调用 [ExecContext.step] 报告进度（用于 20 s 失联看门狗），
     * 并在步骤之间检查 [ExecContext.cancelled]：为 true 时不再继续后续步骤，返回 [JobResult.Cancelled]。
     * 不得抛异常；失败以 [JobResult.Failed] 返回。
     *
     * @param reload 本次启动紧随一次重载回收（沿用旧实现里重载时等待旧资源释放的 1 s）。
     */
    fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult

    /**
     * 回收内核资源。幂等；每一步各自兜底，任何一步失败都不得中断后续步骤。
     *
     * @param soft true = 重载用：只回收 tun / libbox service，保留 command server
     *   （与旧 serviceReload 一致，已连接的统计/分组流不断）；false = 完整回收。
     */
    fun teardown(soft: Boolean, ctx: ExecContext)
}

/** 执行层交给 runtime 的上下文。 */
interface ExecContext {
    /** 协调器要求放弃本次执行（可能在任意线程被置位，读取是 volatile 的）。 */
    val cancelled: Boolean

    /** 即将进入一个可能长时间阻塞的步骤。 */
    fun step(name: String)
}

/** 一次执行层任务的结果（投递回命令层的事件载荷）。 */
sealed interface JobResult {
    /** 启动成功，内核已就绪。 */
    data object Started : JobResult

    /** 启动途中被 [ExecContext.cancelled] 打断；资源仍在 runtime 名下，等待回收。 */
    data object Cancelled : JobResult

    /** 启动失败；资源仍在 runtime 名下，等待回收。 */
    data class Failed(val code: FailureCode, val message: String) : JobResult

    /** 回收完成。 */
    data object TornDown : JobResult
}
