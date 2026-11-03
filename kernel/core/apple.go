//go:build !android

package core

import "github.com/luuuuke88/clashmiao/kernel/engine"

// 本文件只在非 Android 构建里出现：Android 的 gomobile 绑定看不到这些 API，
// Java 公共 API 快照（kernel/api/java-api.txt）与 aar 因此不变。

// Client 只连接命令服务器、不持有服务：iOS 的 Runner 进程用它订阅 Packet Tunnel 里的内核。
// 两个进程 Setup 同一个 BasePath 即可互通。订阅的线格式与 Engine 的同名方法一致。
type Client struct{ inner *engine.Client }

// NewClient 创建 Client；不发起连接，命令服务器不在时订阅返回错误。
func NewClient() *Client { return &Client{inner: engine.NewClient()} }

func (c *Client) SubscribeGroups(h GroupsHandler) (*Subscription, error) {
	return wrapSub(c.inner.SubscribeGroups(h))
}

func (c *Client) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) {
	return wrapSub(c.inner.SubscribeStats(h, intervalMillis))
}

func (c *Client) SubscribeLogs(h LogHandler) (*Subscription, error) {
	return wrapSub(c.inner.SubscribeLogs(h))
}

func (c *Client) SelectOutbound(group, tag string) error { return c.inner.SelectOutbound(group, tag) }
func (c *Client) URLTest(tag string) error               { return c.inner.URLTest(tag) }

// Close 关闭全部订阅，之后不能再订阅；重复调用返回 nil。
func (c *Client) Close() error { return c.inner.Close() }

// TunnelFileDescriptor 返回 Packet Tunnel 的 utun fd（扫描本进程的 socket）；非 Apple 平台或找不到时为 -1。
// NE 的 packetFlow 拿不到 fd 时的兜底。
func TunnelFileDescriptor() int32 { return engine.TunnelFileDescriptor() }

// WriteLog 把宿主自己的一行诊断写进内核日志流（订阅者都能看到）；命令服务器不在时丢弃。
func (e *Engine) WriteLog(line string) { e.inner.WriteLog(line) }
