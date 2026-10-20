package warp

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/crypto/curve25519"
)

// Cloudflare 的设备注册接口（官方客户端使用的公开 HTTP API）。
const (
	apiBase       = "https://api.cloudflareclient.com/v0a2158"
	clientVersion = "a-6.3-1922"
	userAgent     = "okhttp/3.12.1"
	maxBody       = 1 << 20
)

// 错误前缀（Kotlin / Dart 当字符串处理，界面只显示通用失败文案，前缀便于日志与测试区分原因）。
const (
	PrefixNetwork  = "warp-network:"
	PrefixLicense  = "warp-license-invalid:"
	PrefixRegister = "warp-register-failed:"
)

// 错误类别，errors.Is 可识别；消息都以对应前缀开头。
var (
	ErrNetwork  = errors.New("warp network error")
	ErrLicense  = errors.New("warp license rejected")
	ErrRegister = errors.New("warp registration failed")
)

// Account 是一次注册（或续用）的结果。
type Account struct {
	ID      string // 设备 id（旧契约里的 account-id）
	Token   string // 访问令牌（access-token）
	License string
	Config  WireguardConfig
}

type apiResponse struct {
	ID      string `json:"id"`
	Token   string `json:"token"`
	Account struct {
		ID      string `json:"id"`
		License string `json:"license"`
	} `json:"account"`
	Config struct {
		ClientID string `json:"client_id"`
		Peers    []struct {
			PublicKey string `json:"public_key"`
		} `json:"peers"`
		Interface struct {
			Addresses struct {
				V4 string `json:"v4"`
				V6 string `json:"v6"`
			} `json:"addresses"`
		} `json:"interface"`
	} `json:"config"`
}

// Register 注册一台新设备；licenseKey 非空时再绑定 license（PUT）。
// client 可注入（测试用 httptest）；ctx 控制整个流程的取消 / 超时。
// 绑定 license 失败时会尽力删除刚注册的设备，不留孤儿账号。
func Register(ctx context.Context, client *http.Client, licenseKey string) (Account, error) {
	priv, pub, err := newKeyPair()
	if err != nil {
		return Account{}, fmt.Errorf("%s generate key: %v: %w", PrefixRegister, err, ErrRegister)
	}
	var resp apiResponse
	err = call(ctx, client, http.MethodPost, "/reg", "", map[string]any{
		"key":        pub,
		"install_id": "",
		"fcm_token":  "",
		"tos":        time.Now().UTC().Format("2006-01-02T15:04:05.000Z"),
		"type":       "Android",
		"model":      "PC",
		"locale":     "en_US",
	}, &resp)
	if err != nil {
		return Account{}, err
	}
	if resp.ID == "" || resp.Token == "" {
		return Account{}, fmt.Errorf("%s response has no id / token: %w", PrefixRegister, ErrRegister)
	}
	if licenseKey != "" {
		err = call(ctx, client, http.MethodPut, "/reg/"+url.PathEscape(resp.ID)+"/account", resp.Token, map[string]any{"license": licenseKey}, nil)
		if err != nil {
			// 刚建的设备没用了：清掉。失败也无妨（不覆盖原错误）。
			_ = Delete(ctx, client, resp.ID, resp.Token)
			var he *httpError
			if errors.As(err, &he) && he.status >= 400 && he.status < 500 {
				return Account{}, fmt.Errorf("%s license was not accepted: %v: %w", PrefixLicense, err, ErrLicense)
			}
			return Account{}, err
		}
		// license 绑定后账号类型会变，重新读一遍设备信息。
		var fresh apiResponse
		if err := call(ctx, client, http.MethodGet, "/reg/"+url.PathEscape(resp.ID), resp.Token, nil, &fresh); err == nil && fresh.ID != "" {
			resp.Config, resp.Account = fresh.Config, fresh.Account
		}
	}
	acc, err := accountFrom(resp, priv)
	if err != nil {
		return Account{}, err
	}
	acc.License = licenseKey
	if acc.License == "" {
		acc.License = resp.Account.License
	}
	return acc, nil
}

// Delete 删除一台设备（DELETE）。设备已经不存在（404）按成功处理。
func Delete(ctx context.Context, client *http.Client, accountID, token string) error {
	if accountID == "" || token == "" {
		return fmt.Errorf("%s delete needs account id and token: %w", PrefixRegister, ErrRegister)
	}
	err := call(ctx, client, http.MethodDelete, "/reg/"+url.PathEscape(accountID), token, nil, nil)
	var he *httpError
	if errors.As(err, &he) && he.status == http.StatusNotFound {
		return nil
	}
	return err
}

func accountFrom(r apiResponse, priv string) (Account, error) {
	if len(r.Config.Peers) == 0 || r.Config.Peers[0].PublicKey == "" {
		return Account{}, fmt.Errorf("%s response has no peer public key: %w", PrefixRegister, ErrRegister)
	}
	c := WireguardConfig{
		PrivateKey:       priv,
		LocalAddressIPv4: r.Config.Interface.Addresses.V4,
		LocalAddressIPv6: r.Config.Interface.Addresses.V6,
		PeerPublicKey:    r.Config.Peers[0].PublicKey,
		ClientID:         r.Config.ClientID,
	}
	raw, _ := json.Marshal(c)
	if _, err := ParseConfig(string(raw)); err != nil {
		return Account{}, fmt.Errorf("%s response is not usable: %v: %w", PrefixRegister, err, ErrRegister)
	}
	return Account{ID: r.ID, Token: r.Token, License: r.Account.License, Config: c}, nil
}

// GenerateResult 是 GenerateWarpConfig 返回的 JSON：键名与旧 Dart 解析兼容。
type GenerateResult struct {
	AccountID   string          `json:"account-id"`
	AccessToken string          `json:"access-token"`
	Log         string          `json:"log"`
	Config      WireguardConfig `json:"config"`
}

// Generate 注册新设备并（有 oldID / oldToken 时）删除旧设备，返回旧契约的 JSON。
// 先注册、成功之后才删旧设备：注册失败时旧账号原样保留，不会让用户落到「旧的没了、新的没来」。
func Generate(ctx context.Context, client *http.Client, licenseKey, oldID, oldToken string) (string, error) {
	var log strings.Builder
	acc, err := Register(ctx, client, licenseKey)
	if err != nil {
		return "", err
	}
	log.WriteString("registered device " + acc.ID + "\n")
	if oldID != "" && oldToken != "" && oldID != acc.ID {
		if err := Delete(ctx, client, oldID, oldToken); err != nil {
			log.WriteString("old device " + oldID + " was not deleted: " + err.Error() + "\n")
		} else {
			log.WriteString("deleted old device " + oldID + "\n")
		}
	}
	out, err := json.Marshal(GenerateResult{AccountID: acc.ID, AccessToken: acc.Token, Log: log.String(), Config: acc.Config})
	if err != nil {
		return "", fmt.Errorf("%s marshal: %v: %w", PrefixRegister, err, ErrRegister)
	}
	return string(out), nil
}

type httpError struct {
	status int
	body   string
}

func (e *httpError) Error() string { return fmt.Sprintf("HTTP %d: %s", e.status, e.body) }

// call 发一次请求。传输层错误 → ErrNetwork；非 2xx → ErrRegister（带状态码）。
func call(ctx context.Context, client *http.Client, method, path, token string, body any, out any) error {
	var rd io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("%s marshal request: %v: %w", PrefixRegister, err, ErrRegister)
		}
		rd = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, apiBase+path, rd)
	if err != nil {
		return fmt.Errorf("%s build request: %v: %w", PrefixRegister, err, ErrRegister)
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("CF-Client-Version", clientVersion)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s %s: %v: %w", PrefixNetwork, method, path, err, ErrNetwork)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return fmt.Errorf("%s read response: %v: %w", PrefixNetwork, err, ErrNetwork)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		he := &httpError{status: resp.StatusCode, body: truncate(string(data), 200)}
		return fmt.Errorf("%s %s %s: %w: %w", PrefixRegister, method, path, he, ErrRegister)
	}
	if out != nil {
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("%s response is not JSON: %v: %w", PrefixRegister, err, ErrRegister)
		}
	}
	return nil
}

func truncate(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		return s[:n] + "..."
	}
	return s
}

// newKeyPair 生成 WireGuard 的 x25519 密钥对（base64）。
func newKeyPair() (priv, pub string, err error) {
	var k [32]byte
	if _, err = rand.Read(k[:]); err != nil {
		return "", "", err
	}
	// 按 RFC 7748 钳位（curve25519.X25519 内部也会做，这里让私钥本身就是规范形式，与官方客户端一致）
	k[0] &= 248
	k[31] &= 127
	k[31] |= 64
	p, err := curve25519.X25519(k[:], curve25519.Basepoint)
	if err != nil {
		return "", "", err
	}
	return base64.StdEncoding.EncodeToString(k[:]), base64.StdEncoding.EncodeToString(p), nil
}
