import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:clashmiao/features/assets/state/geo_update_notifier.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(geoUpdateProvider);
    final notifier = ref.read(geoUpdateProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('规则库管理')),
      body: ListView(
        children: [GeoAsset.geoip, GeoAsset.geosite].map((asset) {
          final s = states[asset.type]!;
          return ListTile(
            title: Text(asset.filename),
            subtitle: s.error != null
                ? Text(s.error!, style: const TextStyle(color: Colors.red))
                : s.lastUpdated != null
                ? Text('更新于 ${_fmt(s.lastUpdated!)}')
                : const Text('未更新'),
            trailing: s.isUpdating
                ? SizedBox(
                    width: 120,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LinearProgressIndicator(value: s.progress),
                        Text(
                          '${(s.progress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ElevatedButton(
                    onPressed: asset.cdnUrl.isEmpty
                        ? null
                        : () => notifier.update(asset),
                    child: const Text('更新'),
                  ),
          );
        }).toList(),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
