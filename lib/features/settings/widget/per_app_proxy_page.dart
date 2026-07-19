import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/features/settings/state/app_filter_notifier.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PerAppProxyPage extends ConsumerStatefulWidget {
  const PerAppProxyPage({
    super.key,
    this.debugAppsLoader,
    this.debugIconLoader,
  });

  /// 测试专用注入点：绕过真实 Pigeon 调用与 Platform.isAndroid 判断，
  /// 用来驱动"加载应用列表失败 → 错误态 + 重试"这条路径（真实的
  /// getInstalledApps 失败没法在非 Android 测试宿主机上从 method channel
  /// 层面复现，因为 Platform.isAndroid 会先短路掉真实调用）。
  @visibleForTesting
  final Future<List<pigeon.InstalledApp>> Function()? debugAppsLoader;

  /// 测试专用注入点：跟 [debugAppsLoader] 同一套思路，绕开真实
  /// getAppIconBase64 Pigeon 调用，驱动"图标加载成功 / 返回 null /
  /// 抛异常 / 缓存去重"几条路径。
  @visibleForTesting
  final Future<String?> Function(String packageName)? debugIconLoader;

  @override
  ConsumerState<PerAppProxyPage> createState() => _State();
}

class _State extends ConsumerState<PerAppProxyPage> {
  List<pigeon.InstalledApp>? _apps;
  bool _loadFailed = false;
  String _query = '';
  bool _isSearching = false;
  bool _showSystemApps = true;

  /// 每个 packageName 的图标只请求一次：列表滚动会反复重建同一行的
  /// itemBuilder，缓存的是 Future 本身（而不是已解码的字节），这样
  /// FutureBuilder 拿到的是同一个 Future 实例，不会重复触发 Pigeon 调用。
  /// 应用列表通常几十到一两百项，内存 Map 足够，没必要上磁盘缓存 / LRU。
  final Map<String, Future<Uint8List?>> _iconCache = {};

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loadFailed = false);
    final loader = widget.debugAppsLoader;
    if (loader == null && !Platform.isAndroid) {
      setState(() => _apps = const []);
      return;
    }
    try {
      final apps = loader != null
          ? await loader()
          : await pigeon.BoxHostApi().getInstalledApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loadFailed = false;
      });
    } catch (_) {
      // Pigeon 调用（或注入的测试 loader）失败：不能让 _apps 停在 null，
      // 否则 UI 永远显示加载动画、用户既不知道失败了也无法重试。
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  /// 取（或发起）某个包名的图标请求，结果按 packageName 缓存在
  /// `_iconCache` 里。加载失败（返回 null 或抛异常）一律降级为 null，
  /// 由调用方回退到通用图标——绝不能让一个应用的图标异常拖垮整个列表。
  Future<Uint8List?> _loadIcon(String packageName) {
    return _iconCache.putIfAbsent(packageName, () async {
      try {
        final loader = widget.debugIconLoader;
        final base64Icon = loader != null
            ? await loader(packageName)
            : (Platform.isAndroid
                  ? await pigeon.BoxHostApi().getAppIconBase64(packageName)
                  : null);
        if (base64Icon == null || base64Icon.isEmpty) return null;
        return base64Decode(base64Icon);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final filter = ref.watch(appFilterProvider);
    final notifier = ref.read(appFilterProvider.notifier);
    final localizations = MaterialLocalizations.of(context);

    final apps = _filteredApps(_apps ?? []);

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              title: TextFormField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '${localizations.searchFieldLabel}...',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              leading: IconButton(
                onPressed: () {
                  setState(() {
                    _query = '';
                    _isSearching = false;
                  });
                },
                icon: const Icon(Icons.close),
                tooltip: localizations.cancelButtonLabel,
              ),
            )
          : AppBar(
              title: Text(t.settings.network.perAppProxyPageTitle),
              actions: [
                IconButton(
                  icon: const Icon(FluentIcons.search_24_regular),
                  onPressed: () => setState(() => _isSearching = true),
                  tooltip: localizations.searchFieldLabel,
                ),
                PopupMenuButton<_PerAppMenuAction>(
                  icon: const AdaptiveIcon(
                    apple: FluentIcons.more_horizontal_24_regular,
                    other: FluentIcons.more_vertical_24_regular,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _PerAppMenuAction.toggleSystemApps:
                        setState(() => _showSystemApps = !_showSystemApps);
                      case _PerAppMenuAction.clearSelection:
                        notifier.clearSelection();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PerAppMenuAction.toggleSystemApps,
                      child: Text(
                        _showSystemApps
                            ? t.settings.network.hideSystemApps
                            : t.settings.network.showSystemApps,
                      ),
                    ),
                    PopupMenuItem(
                      value: _PerAppMenuAction.clearSelection,
                      child: Text(t.settings.network.clearSelection),
                    ),
                  ],
                ),
              ],
            ),
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedModesHeader(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioGroup<String>(
                      groupValue: filter.nativeMode,
                      onChanged: (value) async {
                        if (value == null) return;
                        await notifier.setMode(value);
                        if (value == 'off' && context.mounted) {
                          await Navigator.of(context).maybePop();
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeTile(
                            value: 'off',
                            title: t.settings.network.perAppProxyModes.offMsg,
                          ),
                          _ModeTile(
                            value: 'include',
                            title:
                                t.settings.network.perAppProxyModes.includeMsg,
                          ),
                          _ModeTile(
                            value: 'exclude',
                            title:
                                t.settings.network.perAppProxyModes.excludeMsg,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
          ),
          if (_apps == null && !_loadFailed)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadFailed)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.settings.network.perAppProxyLoadFailedMsg),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadApps,
                      child: Text(t.settings.network.perAppProxyRetry),
                    ),
                  ],
                ),
              ),
            )
          else if (apps.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  Platform.isAndroid
                      ? t.settings.network.perAppProxyEmptyMsg
                      : t.settings.network.perAppProxyAndroidOnlyMsg,
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                final selected = filter.packages.contains(app.packageName);
                return CheckboxListTile(
                  title: Text(app.appName, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    app.packageName,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: selected,
                  onChanged: (_) => notifier.togglePackage(app.packageName),
                  secondary: SizedBox(
                    width: 48,
                    height: 48,
                    child: FutureBuilder<Uint8List?>(
                      future: _loadIcon(app.packageName),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes != null) {
                          return Image.memory(
                            bytes,
                            width: 48,
                            height: 48,
                            gaplessPlayback: true,
                          );
                        }
                        // 加载中 / 加载失败 / 返回 null 统一降级为通用图标，
                        // 不额外画转圈——图标区域小，转圈动画反而更显突兀。
                        return const Icon(FluentIcons.apps_24_regular);
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  List<pigeon.InstalledApp> _filteredApps(List<pigeon.InstalledApp> apps) {
    final query = _query.trim().toLowerCase();
    return apps.where((app) {
      if (!_showSystemApps && app.isSystemApp) return false;
      if (query.isEmpty) return true;
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.value, required this.title});

  final String value;
  final String title;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(title: Text(title), dense: true, value: value);
  }
}

class _PinnedModesHeader extends SliverPersistentHeaderDelegate {
  const _PinnedModesHeader({required this.child});

  final Widget child;

  @override
  double get minExtent => kMinInteractiveDimension * 3 + 1;

  @override
  double get maxExtent => kMinInteractiveDimension * 3 + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(elevation: overlapsContent ? 1 : 0, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedModesHeader oldDelegate) {
    return oldDelegate.child != child;
  }
}

enum _PerAppMenuAction { toggleSystemApps, clearSelection }
