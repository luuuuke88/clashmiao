// Package kernel 是 ClashMiao 自有的内核模块根包，本身不含代码。
//
// 分层见 docs/ARCHITECTURE.md 的「内核模块 kernel/」一节：
//
//	core/      gomobile 门面（Android；iOS 之后复用）
//	engine/    唯一直接依赖 libbox 的包
//	internal/  配置选项、运行配置构建、订阅解析、URI 转换、旧 schema 清洗、WARP
package kernel
