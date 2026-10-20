# env.sh — 内核模块 kernel/ 的共享构建参数，全仓唯一来源。
#
# 被 source，不直接执行：
#   - tools/kernel/gotest.sh（go vet / go test）
#   - tools/kernel/build-android.sh（gomobile bind）
#   - .github/workflows/ci.yml 的 kernel job（经由上面两个脚本）
# 新构建链路里任何地方都不允许再写第二份下面这两个值的字面量，
# 由 tools/kernel/check-tags-single-source.sh 拦截。
#
# KERNEL_TAGS：
#   不含 with_clash_api（App 从不使用 Clash API，也不编进去）与 with_grpc（官方默认走精简实现）。
#   缺这组 tags 时 QUIC / WireGuard / gVisor 是桩实现，CheckConfig 会失败，
#   所以裸 `go test ./...` 不是合法的验证命令。
# KERNEL_LDFLAGS_LINK：
#   上游 libbox 自己用 go:linkname 访问 Go 运行时内部符号（官方构建同样要带这个链接参数）。
#   实测（macOS arm64 主机，Go 1.26.3，带上面这组 tags）：不带它，测试二进制链接失败，
#   报 `invalid reference to runtime.fwdSig`；Android 目标则是 `invalid reference to os.checkPidfdOnce`。
#   所以主机测试也必须带，与发布构建保持一致。
#   发布构建另在其后追加 -X 版本覆盖与 -s -w -buildid=（见 build-android.sh）。
KERNEL_TAGS="with_gvisor,with_quic,with_wireguard,with_utls,badlinkname,tfogo_checklinkname0"
KERNEL_LDFLAGS_LINK="-checklinkname=0"
export KERNEL_TAGS KERNEL_LDFLAGS_LINK
