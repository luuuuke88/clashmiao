import 'dart:io';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/logs/state/log_filter_notifier.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把核心（sing-box）日志行写到一个临时文件，供"分享核心日志"使用。
/// 抽成顶层函数是为了能在 logs_page_test.dart 里直接验证它和
/// [resolveAppLogSharePath] 返回的是两个不同的文件——这是"分享核心日志"
/// 和"分享应用日志"必须是两个真正不同数据源的核心验证点。
@visibleForTesting
Future<String> writeCoreLogsTempFile(List<String> lines) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/clashmiao-core-logs.txt');
  await file.writeAsString(lines.join('\n'));
  return file.path;
}

/// "分享应用日志"用的文件路径：AppLogger 落地的本地 app.log，和上面的核心
/// 日志临时文件是完全独立的数据源。
@visibleForTesting
Future<String> resolveAppLogSharePath() => AppLogger.instance.getLogFilePath();

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
    await Share.shareXFiles([XFile(path)], text: 'ClashMiao Core Logs');
  }

  /// 分享应用（Dart/Flutter）日志：AppLogger 落地的本地 app.log，包含
  /// FlutterError.onError / PlatformDispatcher.onError 兜底捕获到的未处理
  /// 异常，和上面的核心日志是完全独立的数据源。
  Future<void> _shareAppLogs() async {
    final path = await resolveAppLogSharePath();
    await Share.shareXFiles([XFile(path)], text: 'ClashMiao App Logs');
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

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    forceElevated: innerBoxIsScrolled,
                    title: Text(t.logs.pageTitle),
                    actions: [
                      IconButton(
                        onPressed: state.paused
                            ? notifier.resume
                            : notifier.pause,
                        icon: Icon(
                          state.paused
                              ? FluentIcons.play_20_regular
                              : FluentIcons.pause_20_regular,
                        ),
                        tooltip: state.paused
                            ? t.logs.resumeTooltip
                            : t.logs.pauseTooltip,
                        iconSize: 20,
                      ),
                      IconButton(
                        onPressed: () async {
                          try {
                            await notifier.clear();
                          } catch (error) {
                            if (!context.mounted) return;
                            AppToast.error(context, error.toString());
                          }
                        },
                        icon: const Icon(FluentIcons.delete_lines_20_regular),
                        tooltip: t.logs.clearTooltip,
                        iconSize: 20,
                      ),
                      if (showShareMenu)
                        PopupMenuButton<_LogAction>(
                          icon: const AdaptiveIcon(
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
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _LogsFilterHeaderDelegate(
                      child: _LogsFilterBar(
                        controller: _filterController,
                        level: state.level,
                        onQueryChanged: notifier.setQuery,
                        onLevelChanged: notifier.setLevel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            if (logsAsync.hasError) {
              return Center(child: Text('日志读取失败: ${logsAsync.error}'));
            }
            if (logsAsync.isLoading && state.lines.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.lines.isEmpty) {
              return CustomScrollView(
                primary: false,
                slivers: [
                  SliverOverlapInjector(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '暂无日志',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return CustomScrollView(
              primary: false,
              reverse: true,
              slivers: [
                SliverList.builder(
                  itemCount: state.lines.length,
                  itemBuilder: (context, index) {
                    final log = _ParsedLog.fromLine(state.lines[index]);
                    return _LogEntryTile(log: log, showDivider: index != 0);
                  },
                ),
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

class _LogsFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _LogsFilterHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _LogsFilterHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
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
