package com.clashmiao.clashmiao.engine

/**
 * 启动链上的每个原生步骤。生产实现在 [LibboxKernelRuntime]（libbox 调用），JVM 单测用假实现。
 *
 * 资源归属约定与 [KernelRuntime] 相同：创建出来的东西一出现就记在 runtime 名下，
 * 无论启动以何种结果返回，随后的 teardown 都能完整回收。
 */
internal interface KernelStartOps {
    fun bootstrap()
    fun hasCommandServer(): Boolean

    /** 创建并启动 command server；失败抛异常。 */
    fun spawnCommandServer()

    /** 拼最终运行用 config；失败抛异常。 */
    fun buildConfig(spec: LaunchSpec): String

    /** 清日志、arm 默认网络监听、注册本地 DNS、内存限制。 */
    fun prepareRuntime()

    /** 创建 libbox service（立刻归 runtime 所有）；失败抛异常。 */
    fun newService(content: String)

    /** 重载后等旧资源释放；被取消返回 false。 */
    fun settleAfterReload(ctx: ExecContext): Boolean

    /** 阻塞的 libbox start。 */
    fun startService()

    /** 把 command server 绑到新 service。 */
    fun bindCommandServer()
}

/**
 * 「bootstrap → command server → 配置 → 创建服务 → start → 绑定 command server」整条启动链。
 *
 * 每个可能阻塞的原生步骤之前报告 [ExecContext.step]（20 s 看门狗按步骤计时）；
 * **每个阻塞调用一返回就检查取消**，被取消就不再进入下一个原生步骤，直接返回 [JobResult.Cancelled]
 * （资源仍在 runtime 名下，由协调器随后的回收收口）。不抛异常。
 */
internal fun runStartSequence(
    ops: KernelStartOps,
    spec: LaunchSpec,
    reload: Boolean,
    ctx: ExecContext,
): JobResult {
    try {
        ctx.step("bootstrap")
        ops.bootstrap()
        if (ctx.cancelled) return JobResult.Cancelled

        if (!ops.hasCommandServer()) {
            ctx.step("commandServer")
            try {
                ops.spawnCommandServer()
            } catch (e: Exception) {
                return JobResult.Failed(FailureCode.StartCommandServer, e.message.orEmpty())
            }
            if (ctx.cancelled) return JobResult.Cancelled
        }

        if (spec.runtimeConfigPath.isBlank()) {
            return JobResult.Failed(FailureCode.EmptyConfiguration, "empty runtime config path")
        }
        if (spec.optionsJson.isBlank()) {
            return JobResult.Failed(FailureCode.EmptyConfiguration, "empty config options")
        }

        ctx.step("buildConfig")
        val content = try {
            ops.buildConfig(spec)
        } catch (e: Exception) {
            return JobResult.Failed(FailureCode.EmptyConfiguration, e.message.orEmpty())
        }
        if (ctx.cancelled) return JobResult.Cancelled

        ctx.step("networkWatcher")
        ops.prepareRuntime()
        if (ctx.cancelled) return JobResult.Cancelled

        ctx.step("newService")
        try {
            ops.newService(content)
        } catch (e: Exception) {
            return JobResult.Failed(FailureCode.CreateService, e.message.orEmpty())
        }
        if (ctx.cancelled) return JobResult.Cancelled

        if (reload && !ops.settleAfterReload(ctx)) return JobResult.Cancelled

        ctx.step("start")
        ops.startService()
        // start 返回后立即检查：off 在它阻塞期间到达时，不再绑定 command server，直接交给回收。
        if (ctx.cancelled) return JobResult.Cancelled

        ctx.step("bindCommandServer")
        ops.bindCommandServer()
        if (ctx.cancelled) return JobResult.Cancelled
        return JobResult.Started
    } catch (e: Exception) {
        return JobResult.Failed(FailureCode.StartService, e.message.orEmpty())
    }
}
