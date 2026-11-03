import 'package:clashmiao/core/logger/sentry_redaction.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 生产环境的 Sentry 配置（main.dart 的 `SentryFlutter.init` 只调这一个函数）。
///
/// 抽出来是为了让测试能拿到与生产完全相同的配置：脱敏回调是否挂上、事务是否
/// 真的会经过 `beforeSendTransaction`，都要在测试里锁住。
void configureSentryOptions(
  SentryFlutterOptions options, {
  required String dsn,
}) {
  options.dsn = dsn;
  options.tracesSampleRate = 0.05;
  // sentry 10 默认 traceLifecycle = stream：span 逐个发送，**不再经过**
  // beforeSendTransaction，下面的事务脱敏会被整体绕过。必须显式用 static，让
  // 性能数据仍以整个事务的形式发送、走同一个脱敏器。改回 stream 之前要先用
  // beforeSendSpan 重做脱敏（sentry_options_test 会因此失败）。
  options.traceLifecycle = SentryTraceLifecycle.static;
  options.attachScreenshot = false;
  options.sendDefaultPii = false;
  // 发送前与 app.log 同一个脱敏器：订阅地址凭据、分享链接不随上报离开设备。
  // 请求整块丢弃、contexts 只留白名单，其余字段逐项脱敏。
  options.beforeSend = (event, hint) => redactSentryEvent(event);
  options.beforeSendTransaction = (transaction, hint) =>
      redactSentryTransaction(transaction);
  // `print` / `debugPrint` 的文本不进面包屑：它们是自由文本，里面可能有节点名
  // 之类的裸域名，脱敏器认不出来。需要上报的诊断走 [logAppFailure] 的固定标签。
  options.enablePrintBreadcrumbs = false;
  options.beforeBreadcrumb = (breadcrumb, hint) => redactBreadcrumb(breadcrumb);
  // 结构化日志（Sentry Logs）：App 不使用，也没有逐字段的脱敏路径；万一被某个
  // 集成打开，整体丢弃，不让未过滤的日志正文 / 属性离开设备。
  options.beforeSendLog = (log, hint) => null;
}
