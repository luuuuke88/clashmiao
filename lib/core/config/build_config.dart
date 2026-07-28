/// 编译期注入的构建参数（`--dart-define`）集中声明处。
///
/// ## 为什么要集中
///
/// 这些 `String.fromEnvironment` 原本散落在 6 个文件里，各自带着不同的
/// 默认值和不同的"没配置时怎么办"策略。后果有两个，都在体检时暴露过：
///
/// 1. **没人知道一共有哪些参数**，于是 `release.yml` 里一个 `--dart-define`
///    都没传——所有正式包里这些值全是空的：Sentry 永不初始化（线上崩溃完全
///    不可见）、"检查更新"永远回"已是最新"、隐私政策/服务条款点了没反应。
/// 2. **没配置时的行为是"静默无效"**——按钮还在，点了什么都不发生。用户会
///    认为这个 App 有坏按钮，而不是"这个功能没提供"。
///
/// 所以这里统一声明，并且给每个"外链型"参数配一个 `hasXxx` 判断，让 UI 能
/// 做到**没配置就不显示入口**，而不是显示一个死链。
library;

/// Sentry 上报地址。空 = 完全不初始化 Sentry SDK。
///
/// 注意这只是"编译期有没有 DSN"，是否真的上报还要看用户的数据分析开关
/// （两者是 AND 关系，见 `main.dart` 的 `bootstrapSentryGatedApp`）。
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// GitHub 仓库 slug（`owner/repo`），更新检查用。空 = 不做更新检查。
const githubRepoSlug = String.fromEnvironment('GITHUB_REPO_SLUG');

/// 源码仓库地址。这一项有兜底默认值，所以永远可用。
const githubRepoUrl = String.fromEnvironment(
  'GITHUB_REPO_URL',
  defaultValue: 'https://github.com/clashmiao/clashmiao-client',
);

/// Telegram 频道地址。空 = 关于页不显示这一项。
const telegramChannelUrl = String.fromEnvironment('TELEGRAM_CHANNEL_URL');

/// 隐私政策页面地址。空 = 关于页不显示这一项。
///
/// **上架必需**：Google Play 与 App Store 都要求提供可访问的隐私政策链接。
const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

/// 服务条款页面地址。保留为发布构建可注入的公共配置。
///
/// **上架必需**，同 [privacyPolicyUrl]。
const termsAndConditionsUrl = String.fromEnvironment(
  'TERMS_AND_CONDITIONS_URL',
);

/// geoip 规则库 CDN 地址。空 = Geo 资源页的下载会诚实失败。
const geoipCdnUrl = String.fromEnvironment('GEOIP_CDN_URL');

/// geosite 规则库 CDN 地址。空 = 同上。
const geositeCdnUrl = String.fromEnvironment('GEOSITE_CDN_URL');

/// 是否配置了 Telegram 频道——没配置时关于页不显示这一项入口。
bool get hasTelegramChannel => telegramChannelUrl.isNotEmpty;

/// 是否配置了隐私政策链接。
bool get hasPrivacyPolicy => privacyPolicyUrl.isNotEmpty;

/// 是否配置了服务条款链接。
bool get hasTermsAndConditions => termsAndConditionsUrl.isNotEmpty;

/// 是否能做更新检查（需要 GitHub repo slug）。
bool get hasUpdateCheck => githubRepoSlug.isNotEmpty;
