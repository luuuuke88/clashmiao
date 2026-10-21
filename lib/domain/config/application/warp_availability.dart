import 'package:flutter/foundation.dart';

/// 这个平台上是否提供 WARP。
///
/// iOS 不提供：启用 WARP 要用本机向 Cloudflare 注册账号，而 App Store 审核
/// 指南 5.4 要求 VPN 类 App 不把用户数据交给第三方；WARP 本身又是实验性功能，
/// iOS 首发不带。不提供时所有入口都不显示，已存的开关也按关闭处理。
bool get isWarpAvailable => defaultTargetPlatform != TargetPlatform.iOS;
