/// 依赖运行平台的能力判断。
///
/// 与 `build_config.dart` 分开：那里只放编译期常量和纯 Dart 的判断，不依赖
/// Flutter，可以被 model 层等纯 Dart 代码引用；这里需要
/// `defaultTargetPlatform`，所以放在单独的文件里。
library;

import 'package:clashmiao/core/env/build_config.dart';
import 'package:flutter/foundation.dart';

/// 更新只能由应用商店分发的平台。iOS 包只能从 App Store / TestFlight 安装，
/// App 自己检查更新、再引导去站外下载，既做不到也违反审核指南，所以这类平台
/// 不提供更新检查。
bool get updatesManagedByStore => defaultTargetPlatform == TargetPlatform.iOS;

/// 是否能做更新检查：平台允许、构建没关掉，且两条来源任意一条可用。
bool get hasUpdateCheck =>
    !updatesManagedByStore &&
    !updateCheckDisabled &&
    (updateManifestUrl.isNotEmpty || githubRepoSlug.isNotEmpty);
