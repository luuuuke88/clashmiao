package engine

import (
	"github.com/sagernet/sing-box/experimental/libbox"
)

// LocalDNS 由宿主实现：本地 DNS 走系统解析器。
type LocalDNS interface {
	Raw() bool
	Exchange(call *DNSCall, message []byte) error
	Lookup(call *DNSCall, network, domain string) error
}

// Func 是一次性回调（与 libbox.Func 同形）。
type Func interface {
	Invoke() error
}

// DNSCall 是一次 DNS 请求的结果通道，对应 libbox.ExchangeContext。
type DNSCall struct {
	ctx *libbox.ExchangeContext
}

func (c *DNSCall) OnCancel(callback Func)   { c.ctx.OnCancel(callback) }
func (c *DNSCall) Success(result string)    { c.ctx.Success(result) }
func (c *DNSCall) RawSuccess(result []byte) { c.ctx.RawSuccess(result) }
func (c *DNSCall) ErrorCode(code int32)     { c.ctx.ErrorCode(code) }
func (c *DNSCall) ErrnoCode(code int32)     { c.ctx.ErrnoCode(code) }

type localDNSAdapter struct{ host LocalDNS }

var _ libbox.LocalDNSTransport = (*localDNSAdapter)(nil)

func (a *localDNSAdapter) Raw() bool { return a.host.Raw() }

func (a *localDNSAdapter) Lookup(ctx *libbox.ExchangeContext, network string, domain string) error {
	return a.host.Lookup(&DNSCall{ctx: ctx}, network, domain)
}

func (a *localDNSAdapter) Exchange(ctx *libbox.ExchangeContext, message []byte) error {
	return a.host.Exchange(&DNSCall{ctx: ctx}, message)
}
