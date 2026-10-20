import 'dart:io';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:clashmiao/features/logs/application/box_log_stream_provider.dart';
import 'package:clashmiao/features/logs/application/log_filter_notifier.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/sub_page_scaffold.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:clashmiao/shared/components/motion_progress.dart';

/// 把核心（sing-box）日志行写到一个临时文件，供"分享核心日志"使用。
/// 抽成顶层函数是为了能在 logs_page_test.dart 里直接验证它和
/// [resolveAppLogSharePath] 返回的是两个不同的文件——这是"分享核心日志"
/// 和"分享应用日志"必须是两个真正不同数据源的核心验证点。
///
/// 写出前逐行过 [redactLogText]（与 app.log 同一个脱敏器）：内核日志里可能带
/// 订阅地址、出站的分享链接，导出文件会被用户发给别人。
@visibleForTesting
Future<String> writeCoreLogsTempFile(List<String> lines) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/clashmiao-core-logs.txt');
  await file.writeAsString(lines.map(redactLogText).join('\n'));
  return file.path;
}

/// "分享应用日志"用的文件路径：AppLogger 落地的本地 app.log 的**脱敏副本**
/// （写在临时目录），和上面的核心日志临时文件是完全独立的数据源。
///
/// 从不交出原始 app.log：升级前写下的旧内容可能还带着没脱敏的凭据。
@visibleForTesting
Future<String> resolveAppLogSharePath() async {
  final dir = await getTemporaryDirectory();
  final copy = await AppLogger.instance.writeRedactedCopy(dir);
  return copy.path;
}

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key, this.debugShowShareMenu});

  final bool? debugShowShareMenu;

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 分享核心（sing-box）日志：当前屏幕上看到的这些行，写到临时文件后分享。
  Future<void> _shareCoreLogs(List<String> lines) async {
    final path = await writeCoreLogsTempFile(lines);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'ClashMiao Core Logs'),
    );
  }

  /// 分享应用（Dart/Flutter）日志：AppLogger 落地的本地 app.log（脱敏副本），包含
  /// FlutterError.onError / PlatformDispatcher.onError 兜底捕获到的未处理
  /// 异常，和上面的核心日志是完全独立的数据源。
  Future<void> _shareAppLogs() async {
    final path = await resolveAppLogSharePath();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'ClashMiao App Logs'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final state = ref.watch(logFilterProvider);
    final notifier = ref.read(logFilterProvider.notifier);
    final logsAsync = ref.watch(boxLogStreamProvider);
    final theme = Theme.of(context);
    final showShareMenu =
        widget.debugShowShareMenu ??
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    return SubPageScaffold(
      title: t.logs.pageTitle,
      closeLabel: t.general.close,
      actions: [
        HeaderPillButton(
          onTap: state.paused ? notifier.resume : notifier.pause,
          icon: state.paused
              ? FluentIcons.play_20_regular
              : FluentIcons.pause_20_regular,
          label: state.paused ? t.logs.resumeTooltip : t.logs.pauseTooltip,
        ),
        HeaderPillButton(
          onTap: () async {
            try {
              await notifier.clear();
            } catch (error, st) {
              logAppFailure('logs.clear', error, st);
              if (!context.mounted) return;
              AppToast.error(context, t.logs.clearFailed);
            }
          },
          icon: FluentIcons.delete_lines_20_regular,
          label: t.logs.clearTooltip,
        ),
        if (showShareMenu)
          HeaderPillMenu<_LogAction>(
            label: t.general.showMore,
            icon: resolveAdaptiveIcon(
              apple: FluentIcons.more_horizontal_20_regular,
              other: FluentIcons.more_vertical_20_regular,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _LogAction.shareCoreLogs,
                child: Text(t.logs.shareCoreLogs),
              ),
              PopupMenuItem(
                value: _LogAction.shareAppLogs,
                child: Text(t.logs.shareAppLogs),
              ),
            ],
            onSelected: (action) async {
              switch (action) {
                case _LogAction.shareCoreLogs:
                  // 分享当前屏幕上过滤后可见的行，不能用未过滤的
                  // 原始流——用户特意用级别/关键词过滤日志（比如
                  // 避免带出服务器地址），分享出去的必须是他们
                  // 实际看到、以为在分享的那部分内容。
                  await _shareCoreLogs(state.lines);
                case _LogAction.shareAppLogs:
                  await _shareAppLogs();
              }
            },
          ),
      ],
      body: Column(
        children: [
          _LogsFilterBar(
            controller: _filterController,
            level: state.level,
            onQueryChanged: notifier.setQuery,
            onLevelChanged: notifier.setLevel,
          ),
          Expanded(child: _buildBody(context, t, state, logsAsync, theme)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Translations t,
    LogFilterState state,
    AsyncValue<void> logsAsync,
    ThemeData theme,
  ) {
    if (logsAsync.hasError) {
      logAppFailureOnce('logs.load', logsAsync.error!, logsAsync.stackTrace);
      return Center(child: Text(t.logs.loadFailed));
    }
    if (logsAsync.isLoading && state.lines.isEmpty) {
      return const Center(child: MotionProgress(strokeWidth: 4));
    }
    if (state.lines.isEmpty) {
      return Center(
        child: Text(
          t.logs.empty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return CustomScrollView(
      primary: false,
      reverse: true,
      slivers: [
        // reverse 列表从视口底边向上排：SliverPadding 的 bottom 在反向轴里就是视觉
        // 上的底边（最新一行所在的一端），留出手势条高度。放在列表后面会落到另一头。
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.builder(
            itemCount: state.lines.length,
            itemBuilder: (context, index) {
              final log = _ParsedLog.fromLine(state.lines[index]);
              return _LogEntryTile(log: log, showDivider: index != 0);
            },
          ),
        ),
      ],
    );
  }
}

enum _LogAction { shareCoreLogs, shareAppLogs }

class _LogsFilterBar extends ConsumerWidget {
  const _LogsFilterBar({
    required this.controller,
    required this.level,
    required this.onQueryChanged,
    required this.onLevelChanged,
  });

  final TextEditingController controller;
  final LogLevel level;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<LogLevel> onLevelChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Flexible(
              child: TextFormField(
                controller: controller,
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.logs.filterHint,
                ),
              ),
            ),
            const SizedBox(width: 16),
            DropdownButton<LogLevel>(
              value: level,
              borderRadius: BorderRadius.circular(4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              items: [
                DropdownMenuItem(
                  value: LogLevel.all,
                  child: Text(t.logs.allLevelsFilter),
                ),
                ...LogLevel.values
                    .where((e) => e != LogLevel.all)
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.name.toUpperCase()),
                      ),
                    ),
              ],
              onChanged: (value) {
                if (value == null) return;
                onLevelChanged(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.log, required this.showDivider});

  final _ParsedLog log;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (log.level != null || log.time != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (log.level != null)
                      Text(
                        log.level!.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: log.levelColor,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    if (log.time != null)
                      Text(log.time!, style: theme.textTheme.labelSmall),
                  ],
                ),
              Text(log.message, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (showDivider) const Divider(indent: 16, endIndent: 16, height: 4),
      ],
    );
  }
}

class _ParsedLog {
  const _ParsedLog({this.level, this.time, required this.message});

  final String? level;
  final String? time;
  final String message;

  Color get levelColor {
    switch (level?.toLowerCase()) {
      case 'error':
      case 'fatal':
        return const Color(0xFFEF4444);
      case 'warn':
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
        return const Color(0xFF3B82F6);
      case 'debug':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF64748B);
    }
  }

  factory _ParsedLog.fromLine(String line) {
    final sanitized = sanitizeLogLine(line);
    final timeMatch = RegExp(
      r'(\d{2}:\d{2}:\d{2}(?:\.\d+)?|\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})',
    ).firstMatch(sanitized);
    final levelMatch = RegExp(
      r'\b(trace|debug|info|warn|warning|error|fatal)\b',
      caseSensitive: false,
    ).firstMatch(sanitized);

    var message = sanitized.trim();
    if (timeMatch != null) {
      message = message.replaceFirst(timeMatch.group(0)!, '').trim();
    }
    if (levelMatch != null) {
      message = message.replaceFirst(levelMatch.group(0)!, '').trim();
    }
    message = message
        .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
        .replaceFirst(RegExp(r'^[-|:]\s*'), '')
        .trim();

    return _ParsedLog(
      level: levelMatch?.group(0),
      time: timeMatch?.group(0),
      message: message.isEmpty ? sanitized : message,
    );
  }
}
