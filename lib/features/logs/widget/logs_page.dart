import 'dart:io';

import 'package:clashmiao/features/logs/state/log_filter_notifier.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final _scrollController = ScrollController();
  bool _showSearch = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _export(List<String> lines) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/clashmiao-logs.txt');
    await file.writeAsString(lines.join('\n'));
    await Share.shareXFiles([XFile(file.path)], text: 'ClashMiao Logs');
  }

  Color _levelColor(String line) {
    if (line.contains('[ERROR]')) return Colors.red;
    if (line.contains('[WARN]')) return Colors.orange;
    if (line.contains('[INFO]')) return Colors.blue;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logFilterProvider);
    final notifier = ref.read(logFilterProvider.notifier);

    ref.listen(logFilterProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索日志...',
                  border: InputBorder.none,
                ),
                onChanged: notifier.setQuery,
              )
            : const Text('日志'),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch
                  ? FluentIcons.dismiss_20_regular
                  : FluentIcons.search_20_regular,
            ),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchController.clear();
                notifier.setQuery('');
              }
            },
          ),
          IconButton(
            icon: const Icon(FluentIcons.share_20_regular),
            onPressed: state.lines.isEmpty ? null : () => _export(state.lines),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: LogLevel.values.map((level) {
                final selected = level == state.level;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(level.name.toUpperCase()),
                    selected: selected,
                    onSelected: (_) => notifier.setLevel(level),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: state.lines.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: state.lines.length,
              itemBuilder: (context, i) {
                final line = state.lines[i];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 6, top: 2),
                      color: _levelColor(line),
                    ),
                    Expanded(
                      child: SelectableText(
                        line,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
