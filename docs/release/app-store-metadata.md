# App Store Connect 元数据（iOS 首发，美国 / 香港）

状态：可直接粘贴的定稿草案（2026-10-22）。字数限制按 App Store Connect 当前规则：名称 / 副标题 30 字符，推广文本 170，关键词 100，描述 4000。
配套清单见 `app-store-checklist.md`；本文件只放要填进后台的文字。

## 通用

| 字段 | 值 |
|---|---|
| 名称（所有语言） | `ClashMiao` |
| 主分类 / 次分类 | Utilities / Productivity |
| 隐私政策 URL | `https://clashmiao.com/privacy`（页面带语言切换；新版隐私政策在官网仓库 `feat/website-overhaul` 分支，提审前必须部署上线） |
| 技术支持 URL | `https://clashmiao.com` |
| 营销 URL | `https://clashmiao.com` |
| 支持邮箱 | `support@clashmiao.com` |
| 版权 | `© 2026 <组织法定名称>`（账号持有人填） |
| 价格 | 免费 |
| 销售范围 | 只勾 United States、Hong Kong |
| 版本号 / Build | `0.3.0` / `1`（`flutter build ipa --build-name 0.3.0 --build-number 1`） |

## en-US

**副标题**（29）

```
Proxy client for your configs
```

**推广文本**

```
Bring your own subscription and connect in one tap. Smart routing, live latency for every line, and nothing about your traffic ever leaves your device.
```

**描述**

```
ClashMiao is a clean, fast network client for proxy configurations you already have — a subscription URL or a config file from your own provider.

ONE TAP TO CONNECT
Import a subscription by pasting a link or scanning a QR code, then tap the big button on Home. ClashMiao picks the fastest line automatically, or you can choose one yourself.

SMART OR GLOBAL
Smart routing sends local sites directly and everything else through your line. Switch to Global when you want all traffic to go through the proxy.

SEE EVERY LINE
Latency for every line at a glance, sorted from fastest to slowest. Unreachable lines are marked clearly, never shown as fast.

KNOW WHERE YOU ARE
The home screen shows your current egress IP and its country or region, so you can confirm the connection works.

WIDE PROTOCOL SUPPORT
Shadowsocks, VMess, VLESS, Trojan, Hysteria2, TUIC and more, powered by the open-source sing-box core.

YOUR DATA STAYS YOURS
• ClashMiao does not operate any servers and does not sell or bundle a VPN service.
• We do not collect, store or transmit your traffic, browsing history, DNS queries, subscription URLs or node configuration. Everything stays on your device.
• No account, no ads, no tracking.
• Crash reports are optional and off by default.
Privacy policy: https://clashmiao.com/privacy

ClashMiao uses Apple's Network Extension framework. iOS asks you to allow adding a VPN configuration the first time you connect.
```

**关键词**（95）

```
proxy,sing-box,shadowsocks,vmess,vless,trojan,hysteria,tuic,subscription,tunnel,network,latency
```

**本版本新功能**

```
First App Store release.
```

## zh-Hans（简体中文）

**副标题**

```
用你自己的订阅，一键连接
```

**推广文本**

```
导入你自己的订阅，一键连接。智能分流、每条线路实时延迟，你的流量信息从不离开设备。
```

**描述**

```
ClashMiao 是一款简洁、快速的网络代理客户端，用来连接你已经拥有的代理配置——来自你自己服务商的订阅地址或配置文件。

一键连接
粘贴链接或扫描二维码导入订阅，在主页点一下大按钮即可连接。ClashMiao 会自动选择最快的线路，你也可以自己挑选。

智能分流 / 全局代理
智能分流让本地网站直接连接，其余流量走你的线路；需要所有流量都走代理时，切到全局即可。

每条线路一目了然
所有线路的延迟一屏看完，从快到慢排序；连不上的线路明确标出，绝不显示成"很快"。

确认连接状态
主页显示当前出口 IP 及其所在国家 / 地区，连接是否生效一眼可知。

广泛的协议支持
支持 Shadowsocks、VMess、VLESS、Trojan、Hysteria2、TUIC 等协议，基于开源的 sing-box 核心。

你的数据只属于你
• ClashMiao 不运营任何服务器，不出售、不捆绑任何 VPN 服务。
• 我们不收集、不存储、不传输你的流量、浏览记录、DNS 查询、订阅地址或节点配置，所有内容只保存在你的设备上。
• 无需注册账号，没有广告，不做任何跟踪。
• 崩溃报告为可选功能，默认关闭。
隐私政策：https://clashmiao.com/privacy

ClashMiao 使用 Apple 的 Network Extension 框架。首次连接时，iOS 会请求你允许添加 VPN 配置。
```

**关键词**

```
代理,订阅,节点,线路,sing-box,shadowsocks,vmess,vless,trojan,hysteria,隧道,网络,延迟
```

**本版本新功能**

```
首次在 App Store 发布。
```

## zh-Hant（繁体中文，香港店面）

**副标题**

```
用你自己的訂閱，一鍵連線
```

**推广文本**

```
匯入你自己的訂閱，一鍵連線。智慧分流、每條線路即時延遲，你的流量資訊從不離開裝置。
```

**描述**

```
ClashMiao 是一款簡潔、快速的網路代理用戶端，用來連接你已經擁有的代理設定——來自你自己服務商的訂閱網址或設定檔。

一鍵連線
貼上連結或掃描 QR 碼匯入訂閱，在主頁點一下大按鈕即可連線。ClashMiao 會自動選擇最快的線路，你也可以自行挑選。

智慧分流 / 全域代理
智慧分流讓本地網站直接連線，其餘流量走你的線路；需要所有流量都走代理時，切換到全域即可。

每條線路一目了然
所有線路的延遲一頁看完，由快到慢排序；連不上的線路會明確標示，絕不顯示成「很快」。

確認連線狀態
主頁顯示目前的出口 IP 及其所在國家 / 地區，連線是否生效一眼可知。

廣泛的協定支援
支援 Shadowsocks、VMess、VLESS、Trojan、Hysteria2、TUIC 等協定，基於開源的 sing-box 核心。

你的資料只屬於你
• ClashMiao 不營運任何伺服器，不販售、不綑綁任何 VPN 服務。
• 我們不收集、不儲存、不傳輸你的流量、瀏覽紀錄、DNS 查詢、訂閱網址或節點設定，所有內容只保存在你的裝置上。
• 無需註冊帳號，沒有廣告，不做任何追蹤。
• 當機報告為選用功能，預設關閉。
隱私權政策：https://clashmiao.com/privacy

ClashMiao 使用 Apple 的 Network Extension 框架。首次連線時，iOS 會請求你允許新增 VPN 設定。
```

**关键词**

```
代理,訂閱,節點,線路,sing-box,shadowsocks,vmess,vless,trojan,hysteria,隧道,網路,延遲
```

**本版本新功能**

```
首次在 App Store 發佈。
```

## App 隐私（营养标签）问卷

与 `ios/Runner/PrivacyInfo.xcprivacy` 一致：

- 是否用于跟踪：**否**。
- 收集的数据：**Diagnostics → Crash Data、Performance Data**。
  - 用途：App Functionality、Analytics。
  - 是否关联身份：**否**。是否用于跟踪：**否**。
  - 说明：只在用户于设置中开启「启用分析」后才会发送。当前构建没有配置上报地址，设置里也没有这个开关，实际不发送任何数据；申报是按代码能力从严填写，与 Sentry SDK 自带的隐私清单保持一致。
- 其它所有类别（联系方式、位置、浏览记录、标识符、使用数据等）：**不收集**。

## 年龄分级问卷

全部选「无」。其中 “Unrestricted Web Access” 选 **No**：App 不是浏览器，不内置网页浏览功能。

## 出口合规（每次上传 build 时会问）

建议答法（以账号持有人确认为准）：

1. 是否使用加密：**是**（代理协议在内核里实现了 TLS、AES-GCM、ChaCha20 等标准算法）。
2. 选择 **“Standard encryption algorithms instead of, or in addition to, using or accessing the encryption within Apple's operating system”**。
3. 是否在法国销售：**否**（只上架美国、香港），因此无需上传法国申报文件。

答完后可把结论固化进 `ios/Runner/Info.plist`（`ITSAppUsesNonExemptEncryption`），以后上传不再逐次询问；固化前需要账号持有人确认。

## 审核备注（App Review Information → Notes）

```
ClashMiao is a network client for proxy configurations that the user already owns (a subscription URL or configuration file supplied by the user's own provider). The app does not operate any servers, does not sell or bundle a VPN service, and does not collect or transmit the user's traffic, DNS queries, browsing history or subscription contents. All configuration is stored on the device.

The app uses the NetworkExtension Packet Tunnel API (NEPacketTunnelProvider). On first connect iOS shows the standard "Add VPN Configurations" prompt; please tap Allow.

To test:
1. Copy the subscription URL below.
2. Open the app. On Home, tap "New Profile", then "Add From Clipboard".
3. Tap the large connect button on Home. The status changes to "Connected" and the egress IP shown on Home changes.
4. The "Lines" tab lists every line with its latency; tap one to switch.
5. Tap the connect button again to disconnect.

Reviewer subscription URL: [REVIEWER_SUBSCRIPTION_URL] (valid until [DATE])

No account or login is required. Optional crash reporting is off by default.
```

- `[REVIEWER_SUBSCRIPTION_URL]` 必须是审核专用、长期有效的订阅，不能用个人测试订阅。
- 联系人信息（姓名 / 电话 / 邮箱）由账号持有人填写。
