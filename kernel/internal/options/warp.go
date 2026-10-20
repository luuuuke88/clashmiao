package options

// Warp 对应 `warp` / `warp2`。
type Warp struct {
	Enable          bool   `json:"enable"`
	Mode            string `json:"mode"`
	WireguardConfig string `json:"wireguard-config"`
	LicenseKey      string `json:"license-key"`
	AccountID       string `json:"account-id"`
	AccessToken     string `json:"access-token"`
	CleanIP         string `json:"clean-ip"`
	CleanPort       int    `json:"clean-port"`
	Noise           string `json:"noise"`
	NoiseSize       string `json:"noise-size"`
	NoiseDelay      string `json:"noise-delay"`
	NoiseMode       string `json:"noise-mode"`
}

const (
	WarpProxyOverWarp = "proxy_over_warp"
	WarpWarpOverProxy = "warp_over_proxy"
)
