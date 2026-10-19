/// 深链 URI → 导入意图的纯解析逻辑。
///
/// 背景：`AndroidManifest.xml` 的 intent-filter 已经注册了
/// `sing-box://import-remote-profile`、`clash://install-config`、
/// `clashmeta://…`、`clashmiao://install-sub`、`clashmiao://import` 这几个
/// scheme/host 组合（点链接能拉起 App），但拉起后 URI 内容此前被直接丢弃。
/// 本文件是唯一负责"URI 里到底装了什么、该怎么导入"这个判断的地方——不依赖
/// AppLinks 实例、不需要真实 Android 环境，纯函数，方便单测覆盖已注册的每个
/// scheme/host 组合。
///
/// ## 解析约定
/// Android 对同一个 `<intent-filter>` 内的多个 `<data>` 标签是把各自的
/// scheme 集合、host 集合分别取"并集"，不是按声明顺序两两配对——具体到
/// 本仓库的 manifest，`sing-box`/`clash`/`clashmeta`/`clashmiao` 这 4 个
/// scheme 中的任意一个，配上 `import-remote-profile`/`install-config`/
/// `install-sub`/`import` 这 4 个 host 中的任意一个，实际上都会命中并拉起
/// App（例如 `clashmeta://install-sub?...`、`clash://import?...` 都合法）。
/// 这意味着 scheme 本身对导入行为没有实际影响（只是链接发布方选用的
/// "品牌前缀"），真正决定行为的是 host——所以下面按 host 分发，忽略 scheme。
///
/// - host `install-sub` / `install-config` / `import-remote-profile`：
///   三者语义都是"这里有一个远程订阅/配置的 URL，去抓取它"。统一从
///   `?url=` query 参数取值（[Uri.queryParameters] 已自动 URL-decode），
///   产出 [DeepLinkFetchUrl]，调用方应走 `ProfileRepository.addByUrl`。
/// - host `import`（仅在 clashmiao 场景下有独立意义的通用动词）：语义更
///   模糊——既可能是"给个订阅 URL"，也可能是"这就是要导入的节点内容"
///   （例如分享一条 `vless://...` 单节点链接）。处理方式：同样先取
///   `?url=` 参数值，再嗅探它的内容——如果是已知的单节点代理 URI scheme
///   （见下方 `kDeepLinkProxyUriSchemes`），产出
///   [DeepLinkImportContent]（调用方应走 `ProfileRepository.addByContent`，
///   不发起网络请求，直接把内容喂给 native parse）；如果是 http(s) URL，
///   产出 [DeepLinkFetchUrl]；两者都不是的其它内容，同样归为
///   [DeepLinkImportContent] 兜底（反正也不是能 fetch 的 URL，与其当 URL
///   请求必然失败，不如当字面内容交给 native parse 去判断，失败信息至少
///   更直接）。
/// - 缺少 `url` 参数、或参数为空白：[DeepLinkMissingPayload]。
/// - host 不在上述已注册范围内：[DeepLinkUnrecognized]（正常情况下 Android
///   不会把这种链接路由到本 App——intent-filter 根本不会匹配、系统不会
///   拉起我们；这里只是防御性兜底，方便单测直接构造任意 [Uri]）。
///
/// 可选的 `?name=` 参数（同样自动 URL-decode）会作为自定义名称透传给
/// `addByUrl` 的 `customName` / `addByContent` 的 `name`。
library;

/// 深链解析出的导入意图。
sealed class DeepLinkIntent {
  const DeepLinkIntent();
}

/// 需要发起 HTTP 请求抓取的订阅/配置地址（对应 `ProfileRepository.addByUrl`）。
final class DeepLinkFetchUrl extends DeepLinkIntent {
  const DeepLinkFetchUrl(this.url, {this.customName});

  /// 待抓取的订阅/配置 URL（已 URL-decode）。
  final String url;

  /// 可选的自定义订阅名称（来自 `?name=`）。
  final String? customName;

  @override
  String toString() => 'DeepLinkFetchUrl(url: $url, customName: $customName)';
}

/// 已经是可直接喂给 native parse 的字面内容（单节点代理 URI 等），对应
/// `ProfileRepository.addByContent`。
final class DeepLinkImportContent extends DeepLinkIntent {
  const DeepLinkImportContent(this.content, {this.customName});

  /// 待导入的字面内容（已 URL-decode）。
  final String content;

  /// 可选的自定义名称（来自 `?name=`）。
  final String? customName;

  @override
  String toString() =>
      'DeepLinkImportContent(content: $content, customName: $customName)';
}

/// 命中已注册的 scheme/host，但没带可用的 payload（缺 `url` 参数，或参数为
/// 空白）。
final class DeepLinkMissingPayload extends DeepLinkIntent {
  const DeepLinkMissingPayload();

  @override
  String toString() => 'DeepLinkMissingPayload()';
}

/// scheme/host 不在已注册范围内——正常情况下 Android 不会把这种链接路由过来
/// （intent-filter 不匹配），这里只是防御性兜底。
final class DeepLinkUnrecognized extends DeepLinkIntent {
  const DeepLinkUnrecognized();

  @override
  String toString() => 'DeepLinkUnrecognized()';
}

/// 支持的单节点代理 URI scheme 白名单，仅本文件使用（单测也遍历它来覆盖
/// 每个 scheme）。这份名单目前是文档性质的：`parseDeepLink` 的 `import`
/// 分支实际只需要判断"是不是 http(s) URL"——凡是不匹配 http(s) 的输入都会
/// 统一落到 [DeepLinkImportContent] 兜底，效果与显式比对这份名单一致，
/// 因此它是否命中并不影响实际解析结果。
const kDeepLinkProxyUriSchemes = [
  'ss',
  'vless',
  'vmess',
  'trojan',
  'hysteria',
  'hysteria2',
  'tuic',
];

const _installSubHost = 'install-sub';
const _installConfigHost = 'install-config';
const _importRemoteProfileHost = 'import-remote-profile';
const _importHost = 'import';

/// 解析一个深链 [Uri]，产出对应的导入意图。完整约定见文件头注释。
DeepLinkIntent parseDeepLink(Uri uri) {
  final host = uri.host.toLowerCase();
  final rawUrl = uri.queryParameters['url']?.trim();
  final customName = _extractCustomName(uri);

  switch (host) {
    case _installSubHost:
    case _installConfigHost:
    case _importRemoteProfileHost:
      if (rawUrl == null || rawUrl.isEmpty) {
        return const DeepLinkMissingPayload();
      }
      return DeepLinkFetchUrl(rawUrl, customName: customName);

    case _importHost:
      if (rawUrl == null || rawUrl.isEmpty) {
        return const DeepLinkMissingPayload();
      }
      // looksLikeProxyUri 与 looksLikeHttpUrl 天然互斥（scheme 前缀不同），
      // 所以下面的 !looksLikeProxyUri 恒真，实际只由 looksLikeHttpUrl 决定
      // 分支；保留这个判断只是让"已知代理 scheme → 走内容兜底"这条意图在
      // 代码里显式可见。
      final looksLikeProxyUri = kDeepLinkProxyUriSchemes.any(
        (scheme) => rawUrl.startsWith('$scheme://'),
      );
      final looksLikeHttpUrl =
          rawUrl.startsWith('http://') || rawUrl.startsWith('https://');
      if (!looksLikeProxyUri && looksLikeHttpUrl) {
        return DeepLinkFetchUrl(rawUrl, customName: customName);
      }
      return DeepLinkImportContent(rawUrl, customName: customName);

    default:
      return const DeepLinkUnrecognized();
  }
}

String? _extractCustomName(Uri uri) {
  final name = uri.queryParameters['name']?.trim();
  return (name == null || name.isEmpty) ? null : name;
}
