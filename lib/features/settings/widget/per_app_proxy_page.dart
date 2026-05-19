import 'dart:io';
import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:clashmiao/features/settings/state/app_filter_notifier.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PerAppProxyPage extends ConsumerStatefulWidget {
  const PerAppProxyPage({super.key});

  @override
  ConsumerState<PerAppProxyPage> createState() => _State();
}

class _State extends ConsumerState<PerAppProxyPage> {
  List<pigeon.InstalledApp>? _apps;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    if (!Platform.isAndroid) return;
    final api = pigeon.BoxHostApi();
    final apps = await api.getInstalledApps();
    if (mounted) setState(() => _apps = apps);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(appFilterProvider);
    final notifier = ref.read(appFilterProvider.notifier);

    final apps = _apps ?? [];
    final filtered = apps
        .where(
          (a) =>
              _query.isEmpty ||
              a.appName.toLowerCase().contains(_query.toLowerCase()) ||
              a.packageName.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final userApps = filtered.where((a) => !a.isSystemApp).toList();
    final systemApps = filtered.where((a) => a.isSystemApp).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('每应用代理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索应用...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: _apps == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('启用每应用过滤'),
                        value: filter.enabled,
                        onChanged: notifier.setEnabled,
                      ),
                      if (filter.enabled)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'allow',
                                label: Text('仅允许以下'),
                              ),
                              ButtonSegment(
                                value: 'block',
                                label: Text('全部，以下除外'),
                              ),
                            ],
                            selected: {filter.mode},
                            onSelectionChanged: (s) =>
                                notifier.setMode(s.first),
                          ),
                        ),
                    ],
                  ),
                ),
                _AppList(
                  title: '用户应用',
                  apps: userApps,
                  selectedPackages: filter.packages,
                  onToggle: notifier.togglePackage,
                ),
                if (systemApps.isNotEmpty)
                  _AppList(
                    title: '系统应用',
                    apps: systemApps,
                    selectedPackages: filter.packages,
                    onToggle: notifier.togglePackage,
                    initiallyExpanded: false,
                  ),
              ],
            ),
    );
  }
}

class _AppList extends StatelessWidget {
  const _AppList({
    required this.title,
    required this.apps,
    required this.selectedPackages,
    required this.onToggle,
    this.initiallyExpanded = true,
  });
  final String title;
  final List<pigeon.InstalledApp> apps;
  final List<String> selectedPackages;
  final void Function(String) onToggle;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: ExpansionTile(
        title: Text('$title (${apps.length})'),
        initiallyExpanded: initiallyExpanded,
        children: apps.map((app) {
          return CheckboxListTile(
            title: Text(app.appName),
            subtitle: Text(
              app.packageName,
              style: const TextStyle(fontSize: 11),
            ),
            value: selectedPackages.contains(app.packageName),
            onChanged: (_) => onToggle(app.packageName),
            dense: true,
          );
        }).toList(),
      ),
    );
  }
}
