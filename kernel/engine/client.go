package engine

import (
	"os"
	"sync"
)

// Client 只连接命令服务器、不持有服务：给「内核跑在另一个进程里」的宿主用
// （iOS 的 Runner 订阅 Packet Tunnel 里的内核）。命令服务器的位置由 Setup 的 BasePath 决定，
// 两个进程 Setup 同一个 BasePath 即可。
//
// 订阅语义、线格式与 Engine 的同名方法完全一致；断线只上抛（DisconnectListener），重连由宿主决定。
type Client struct {
	mu     sync.Mutex
	subs   map[*Subscription]struct{}
	closed bool
	// 测试注入点，语义同 Engine.hooks 里的同名字段。
	beforeConnect func(*Subscription)
	connect       func(*Subscription) error
}

// NewClient 创建 Client。不发起连接：每条订阅各自连接，命令服务器不在时订阅返回错误。
func NewClient() *Client {
	return &Client{subs: map[*Subscription]struct{}{}}
}

func (c *Client) register(s *Subscription) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return os.ErrClosed
	}
	c.subs[s] = struct{}{}
	return nil
}

func (c *Client) removeSub(s *Subscription) {
	c.mu.Lock()
	delete(c.subs, s)
	c.mu.Unlock()
}

func (c *Client) connectHooks() (func(*Subscription), func(*Subscription) error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.beforeConnect, c.connect
}

func (c *Client) SubscribeGroups(h GroupsHandler) (*Subscription, error) {
	return subscribeGroups(c, h)
}

func (c *Client) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) {
	return subscribeStats(c, h, intervalMillis)
}

func (c *Client) SubscribeLogs(h LogHandler) (*Subscription, error) { return subscribeLogs(c, h) }

func (c *Client) SelectOutbound(group, tag string) error { return selectOutbound(group, tag) }

func (c *Client) URLTest(tag string) error { return urlTest(tag) }

// Close 关闭全部订阅（等它们的流退出），之后不能再订阅。重复调用返回 nil。
func (c *Client) Close() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	subs := make([]*Subscription, 0, len(c.subs))
	for s := range c.subs {
		subs = append(subs, s)
	}
	c.mu.Unlock()
	return closeAll(subs)
}
