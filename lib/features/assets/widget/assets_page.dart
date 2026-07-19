import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:clashmiao/features/assets/state/geo_update_notifier.dart';
import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/tip_card.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final states = ref.watch(geoUpdateProvider);
    final hasMissingAsset = [
      GeoAsset.geoip,
      GeoAsset.geosite,
    ].any((asset) => states[asset.type]?.lastUpdated == null);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(t.settings.geoAssets.pageTitle),
            pinned: true,
            actions: [
              PopupMenuButton<_AssetsAction>(
                icon: const AdaptiveIcon(
                  apple: FluentIcons.more_horizontal_24_regular,
                  other: FluentIcons.more_vertical_24_regular,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _AssetsAction.addRecommended:
                      ref.read(geoUpdateProvider.notifier).addRecommended();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _AssetsAction.addRecommended,
                    child: Text(t.settings.geoAssets.addRecommended),
                  ),
                ],
              ),
            ],
          ),
          if (hasMissingAsset)
            SliverToBoxAdapter(
              child: TipCard(
                message: t.settings.geoAssets.missingGeoAssetsMsg,
              ),
            ),
          _AssetSection(
            title: t.settings.geoAssets.geoip,
            asset: GeoAsset.geoip,
          ),
          const SliverToBoxAdapter(child: Divider(indent: 16, endIndent: 16)),
          _AssetSection(
            title: t.settings.geoAssets.geosite,
            asset: GeoAsset.geosite,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

enum _AssetsAction { addRecommended }

class _AssetSection extends ConsumerWidget {
  const _AssetSection({required this.title, required this.asset});

  final String title;
  final GeoAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(geoUpdateProvider);
    final state = states[asset.type] ?? const GeoUpdateState();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ListTile(
            title: Text('$title ›'),
            titleTextStyle: Theme.of(context).textTheme.headlineSmall,
            dense: true,
          ),
        ),
        SliverToBoxAdapter(
          child: _GeoAssetTile(asset: asset, state: state),
        ),
      ],
    );
  }
}

class _GeoAssetTile extends ConsumerWidget {
  const _GeoAssetTile({required this.asset, required this.state});

  final GeoAsset asset;
  final GeoUpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final fileMissing = state.lastUpdated == null;

    return ListTile(
      title: Text(asset.filename),
      isThreeLine: true,
      subtitle: state.isUpdating
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: state.progress),
                const SizedBox(height: 4),
                Text('${(state.progress * 100).toInt()}%'),
              ],
            )
          : Text.rich(
              TextSpan(
                children: [
                  if (state.error != null)
                    TextSpan(
                      text: state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (fileMissing)
                    TextSpan(
                      text: t.settings.geoAssets.fileMissing,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else ...[
                    if (asset.sizeBytes != null) ...[
                      TextSpan(text: _formatBytes(asset.sizeBytes!)),
                      const TextSpan(text: ' • '),
                    ],
                    TextSpan(text: _formatDate(state.lastUpdated!)),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
      trailing: PopupMenuButton<_GeoAssetAction>(
        icon: const AdaptiveIcon(
          apple: FluentIcons.more_horizontal_24_regular,
          other: FluentIcons.more_vertical_24_regular,
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: !state.isUpdating && asset.cdnUrl.isNotEmpty,
            value: _GeoAssetAction.update,
            child: Text(
              fileMissing
                  ? t.settings.geoAssets.download
                  : t.settings.geoAssets.update,
            ),
          ),
        ],
        onSelected: (action) async {
          switch (action) {
            case _GeoAssetAction.update:
              await ref.read(geoUpdateProvider.notifier).update(asset);
              if (!context.mounted) return;
              final next = ref.read(geoUpdateProvider)[asset.type];
              if (next?.error != null) {
                AppToast.error(context, t.settings.geoAssets.failureMsg);
              } else {
                AppToast.success(context, t.settings.geoAssets.successMsg);
              }
          }
        },
      ),
    );
  }
}

enum _GeoAssetAction { update }

String _formatDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
