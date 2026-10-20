package com.clashmiao.clashmiao.engine

/**
 * 启动链上的每个原生步骤。生产实现在 [CoreKernelRuntime]（自有门面调用），JVM 单测用假实现。
 *
 * 资源归属约定与 [KernelRuntime] 相同：创建出来的东西一出现就记在 runtime 名下，
 * 无论启动以何种结果返回，随后的 teardown 都能完整回收。
 *
 * 与旧链路相比（旧：commandServer / newService / settle / startService / bindCommandServer 五段）：
 * 新内核的 Engine 把「建服务、启动、绑定命令服务器」收成一次阻塞的 [startEngine]，
 * 重载也不再等固定 1 s——直接再次启动，内核自己先关旧实例。
 */
internal interface KernelStartOps {
    fun bootstrap()

    /** 创建 Engine（含命令服务器）；已有则什么都不做（幂等）。失败抛异常。 */
    fun createEngine()

    /** 拼最终运行用 config；失败抛异常。 */
    fun buildConfig(spec: LaunchSpec): String

    /** 清日志、arm 默认网络监听。 */
    fun prepareRuntime()

    /** 阻塞的启动：建服务并启动；失败的消息以 `create-service:` / `start-service:` 开头。 */
    fun startEngine(content: String)
}

/** 把 [KernelStartOps.startEngine] 的失败消息映射成失败码：`create-service:` → CreateService，其余都按启动失败。 */
internal fun classifyStartFailure(message: String?): FailureCode =
    if (message != null && message.trimStart().startsWith("create-service:")) FailureCode.CreateService
    else FailureCode.StartService

/**
 * 「bootstrap → createEngine → 配置 → prepareRuntime → startEngine」整条启动链。
 *
 * 每个可能阻塞的原生步骤之前报告 [ExecContext.step]（20 s 看门狗按步骤计时）；
 * **每个阻塞调用一返回就检查取消**，被取消就不再进入下一个原生步骤，直接返回 [JobResult.Cancelled]
 * （资源仍在 runtime 名下，由协调器随后的回收收口）。不抛异常。
 *
 * 取消语义（不承诺协调器做不到的事）：协调器的 cancel 只置位，回收与启动在同一工作线程上串行，
 * 所以 [KernelStartOps.startEngine] 阻塞期间没有人会去停 Engine；它一返回，这里立刻发现已取消并交给回收。
 */
internal fun runStartSequence(
    ops: KernelStartOps,
    spec: LaunchSpec,
    @Suppress("UNUSED_PARAMETER") reload: Boolean,
    ctx: ExecContext,
): JobResult {
    try {
        ctx.step("bootstrap")
        ops.bootstrap()
        if (ctx.cancelled) return JobResult.Cancelled

        ctx.step("createEngine")
        try {
            ops.createEngine()
        } catch (e: Exception) {
            return JobResult.Failed(FailureCode.StartCommandServer, e.message.orEmpty())
        }
        if (ctx.cancelled) return JobResult.Cancelled

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

        ctx.step("startEngine")
        try {
            ops.startEngine(content)
        } catch (e: Exception) {
            return JobResult.Failed(classifyStartFailure(e.message), e.message.orEmpty())
        }
        // startEngine 返回后立即检查：off 在它阻塞期间到达时，直接交给回收。
        if (ctx.cancelled) return JobResult.Cancelled
        return JobResult.Started
    } catch (e: Exception) {
        return JobResult.Failed(FailureCode.StartService, e.message.orEmpty())
    }
}

/**
 * 回收内核运行时资源的每一步。生产实现在 [CoreKernelRuntime]，JVM 单测用假实现注入失败。
 * 全部步骤幂等：提前 abort 时没创建的资源都是 null-safe no-op。
 */
internal interface KernelTeardownOps {
    /** 停止服务（Engine.stop）；会打断仍在进行的启动。 */
    fun stopEngine()

    /** 关闭 Android 侧原始 tun fd（撤销系统路由表）。 */
    fun closeTunFd()

    /** 彻底关闭 Engine（命令服务器、订阅）。 */
    fun closeEngine()

    /** 断开默认网络监听。 */
    fun disarmNetworkWatcher()

    /** 释放 Go 引用（Seq.destroyRef）并清空对 Engine 的持有。 */
    fun releaseEngineRef()
}

/**
 * 回收：[soft]（重载用）只做 stop + 关 tun fd，保留 Engine 与网络监听；否则再 close / disarm / 释放引用。
 *
 * **每一步各自兜底**：任一步抛异常都记录并继续下一步，绝不让某一步的异常截断后面的回收
 * （历史上 abortWithAlert 先后漏过 tun fd / service、DNS 注销 / 网络监听 / 命令服务器，
 * 导致启动失败重试时泄漏原生资源）。返回按顺序记录下来的失败（步骤名 → 异常），空表示全部成功。
 */
internal fun runTeardown(
    ops: KernelTeardownOps,
    soft: Boolean,
    ctx: ExecContext,
    onError: (step: String, e: Throwable) -> Unit = { _, _ -> },
): List<Pair<String, Throwable>> {
    val failures = ArrayList<Pair<String, Throwable>>()
    fun step(name: String, block: () -> Unit) {
        ctx.step(name)
        try {
            block()
        } catch (e: Throwable) {
            failures += name to e
            onError(name, e)
        }
    }
    step("stopEngine", ops::stopEngine)
    step("closeTun", ops::closeTunFd)
    if (soft) return failures
    step("closeEngine", ops::closeEngine)
    step("disarmNetworkWatcher", ops::disarmNetworkWatcher)
    step("releaseEngineRef", ops::releaseEngineRef)
    return failures
}
