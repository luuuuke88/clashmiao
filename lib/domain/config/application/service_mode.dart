// 服务模式（仅线路 / 系统线路 / VPN）的唯一口径。
//
// 快速设置弹层、配置选项页、启动配置（`enable-tun`）都从这里取值，三处不会再
// 各算各的。之前的问题（真机验收 BUG-3 / BUG-4）：
// - 选中态按 `enableTun → tun；setSystemProxy → 系统线路；否则仅线路` 推导，但
//   移动端根本没有「系统线路」这一档，而 `setSystemProxy` 的默认值是 true——
//   从没手动选过的用户落在一个不存在的档位上，分段控件两段都不亮；
// - 移动端启动配置无条件 `enable-tun=true`，选了「仅线路」也不会进入请求，
//   协调器看到同一份配置原样无操作，界面却显示已切换。
//
// 现在：Android 只有两档，「仅线路」当且仅当两个开关都关（只有用户在移动端点
// 「仅线路」才会写出这个组合），其余（含默认值）都是 VPN——这也是升级前实际
// 一直在跑的形态。Android 上这一档直接决定请求里的 `enable-tun`，原生协调器据
// 此选择 Service 类（VPN / 纯代理），形态随请求走、进 revision。iOS 恒为 VPN，
// 不提供选择。原则：界面上的可选档位（能力）与启动参数（显式设置）分开算——
// 界面只藏一个平台上不能生效的档位，**不改写**用户持久化的显式设置。

import 'dart:io';

import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:flutter/foundation.dart';

/// 用户可见的服务模式。
enum ServiceMode {
  /// 仅线路：只开本地代理端口，不接管系统流量。
  proxyOnly,

  /// 系统线路（仅桌面端）：改系统代理设置。
  systemProxy,

  /// VPN / TUN：接管全部流量。
  vpn,
}

/// 运行平台的形态；只用于服务模式口径。
enum ServiceModePlatform { android, ios, desktop }

/// 测试用：覆盖当前平台（宿主机上跑测试时 `Platform.isAndroid` 恒为 false）。
@visibleForTesting
ServiceModePlatform? debugServiceModePlatformOverride;

ServiceModePlatform get serviceModePlatform {
  final override = debugServiceModePlatformOverride;
  if (override != null) return override;
  if (Platform.isAndroid) return ServiceModePlatform.android;
  if (Platform.isIOS) return ServiceModePlatform.ios;
  return ServiceModePlatform.desktop;
}

/// 当前平台提供的档位：只列真正能生效的档，不给必定无效或必定失败的选项。
/// [settings] 只用于桌面端：已持久化的显式 TUN 设置要能看到、能切走。
///
/// - Android：仅线路 / VPN（没有「系统线路」：改系统代理需要 root）。
/// - iOS：只有 VPN。Packet Tunnel 恒以 TUN 形态运行，「仅线路」在 iOS 上什么
///   也不会改变，所以不提供；界面用 `t.config.serviceModeIosVpnOnly` 说明边界。
/// - 桌面端：仅线路 / 系统线路，**不主动提供** TUN 档：仓库里不带 wintun 驱动，
///   macOS 的 entitlements 也只有 `network.client/server`，普通桌面进程起 tun
///   设备会失败。桌面因此默认只做到"系统代理级接管"，泄漏面（不遵循系统代理的
///   程序会直连）由 `t.config.desktopProxyScopeNotice` 明确告知，不藏着。
///   但这不能证明所有桌面 TUN 路径都无效（例如以足够权限运行的 Linux），所以
///   已持久化的 `enableTun=true`（旧版本、备份恢复）照旧生效（见
///   [kernelEnableTun]），档位列表里也带上 VPN 显示为选中，用户随时能切走；
///   一旦切走，它就不再出现。
List<ServiceMode> serviceModeChoices(NetworkSettings settings) =>
    switch (serviceModePlatform) {
      ServiceModePlatform.android => const [
        ServiceMode.proxyOnly,
        ServiceMode.vpn,
      ],
      ServiceModePlatform.ios => const [ServiceMode.vpn],
      ServiceModePlatform.desktop =>
        settings.enableTun
            ? const [
                ServiceMode.proxyOnly,
                ServiceMode.systemProxy,
                ServiceMode.vpn,
              ]
            : const [ServiceMode.proxyOnly, ServiceMode.systemProxy],
    };

/// [settings] 当前对应的档位；结果一定在 `serviceModeChoices(settings)` 里。
ServiceMode serviceModeOf(NetworkSettings settings) {
  switch (serviceModePlatform) {
    case ServiceModePlatform.ios:
      return ServiceMode.vpn;
    case ServiceModePlatform.android:
      return !settings.enableTun && !settings.setSystemProxy
          ? ServiceMode.proxyOnly
          : ServiceMode.vpn;
    case ServiceModePlatform.desktop:
      if (settings.enableTun) return ServiceMode.vpn;
      return settings.setSystemProxy
          ? ServiceMode.systemProxy
          : ServiceMode.proxyOnly;
  }
}

/// 启动配置里的 `enable-tun`。
///
/// - Android：由服务模式决定，原生协调器按它选择 Service 类（VPN / 纯代理）；
/// - iOS：Packet Tunnel 只能以 TUN 形态运行，恒为 true（不改变 iOS 现有行为）；
/// - 桌面端：尊重显式设置 `enableTun`。界面不主动提供 TUN 档（见
///   [serviceModeChoices]），但不替用户改写已持久化的设置：有权限的环境里它
///   本来就能工作，强制关掉会让这类用户升级后"显示已连接、实际失去全局接管"。
bool kernelEnableTun(NetworkSettings settings) {
  return switch (serviceModePlatform) {
    ServiceModePlatform.android => serviceModeOf(settings) == ServiceMode.vpn,
    ServiceModePlatform.ios => true,
    ServiceModePlatform.desktop => settings.enableTun,
  };
}

/// 只对 TUN 生效的设置（严格路由、TUN 实现）此刻是否会起作用：内核真的以 TUN
/// 形态运行时才会。与 [kernelEnableTun] 同一口径：Android「仅线路」、桌面未开
/// TUN 时为 false——这时界面不展示这些设置，免得给出改了也没有任何效果的选项。
bool tunSettingsTakeEffect(NetworkSettings settings) =>
    kernelEnableTun(settings);

/// 服务模式在当前平台是否只有一档、用户无从选择（iOS 恒为 VPN）。界面据此不画
/// 选择控件，而是说明边界。
bool get serviceModeIsFixed => serviceModePlatform == ServiceModePlatform.ios;

/// 运行时配置是否保留订阅配置里的 tun inbound：桌面端一律剥——桌面的 TUN 只由
/// 显式设置经 `enable-tun` 交给内核创建，不让订阅里自带的 tun inbound 绕过这个
/// 开关；移动端与 [kernelEnableTun] 一致，Android「仅线路」跑在纯代理 Service
/// 里，配置里留着 tun 内核启动即失败。
bool runtimeKeepsTunInbound(NetworkSettings settings) =>
    serviceModePlatform != ServiceModePlatform.desktop &&
    kernelEnableTun(settings);

/// 把 [mode] 写进网络设置（两个开关互斥）。
Future<void> applyServiceMode(
  NetworkSettingsNotifier notifier,
  ServiceMode mode,
) async {
  switch (mode) {
    case ServiceMode.proxyOnly:
      await notifier.setEnableTun(false);
      await notifier.setSystemProxy(false);
    case ServiceMode.systemProxy:
      await notifier.setEnableTun(false);
      await notifier.setSystemProxy(true);
    case ServiceMode.vpn:
      await notifier.setSystemProxy(false);
      await notifier.setEnableTun(true);
  }
}
