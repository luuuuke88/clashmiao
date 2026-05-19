import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/model/advanced_config.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileAdvancedSheet extends ConsumerStatefulWidget {
  const ProfileAdvancedSheet({super.key, required this.profile});
  final ProfileEntity profile;

  @override
  ConsumerState<ProfileAdvancedSheet> createState() => _State();
}

class _State extends ConsumerState<ProfileAdvancedSheet> {
  late AdvancedConfig _config =
      widget.profile.advancedConfig ?? const AdvancedConfig();
  late final _dnsCtrl = TextEditingController(
    text: _config.remoteDnsOverride ?? '',
  );
  late final _fragRangeCtrl = TextEditingController(
    text: _config.fragmentRange ?? '10-30',
  );

  @override
  void dispose() {
    _dnsCtrl.dispose();
    _fragRangeCtrl.dispose();
    super.dispose();
  }

  AdvancedConfig _currentConfig() => AdvancedConfig(
    remoteDnsOverride: _dnsCtrl.text.isEmpty ? null : _dnsCtrl.text,
    muxEnabled: _config.muxEnabled,
    muxProtocol: _config.muxProtocol,
    muxConcurrency: _config.muxConcurrency,
    fragmentEnabled: _config.fragmentEnabled,
    fragmentRange: _fragRangeCtrl.text.isEmpty ? null : _fragRangeCtrl.text,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('高级配置', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _dnsCtrl,
            decoration: const InputDecoration(
              labelText: 'DNS 覆盖',
              hintText: '例：https://8.8.8.8/dns-query',
            ),
          ),
          SwitchListTile(
            title: const Text('启用 Mux'),
            subtitle: const Text('多路复用，减少握手延迟'),
            value: _config.muxEnabled,
            onChanged: (v) => setState(
              () => _config = AdvancedConfig(
                remoteDnsOverride: _dnsCtrl.text.isEmpty ? null : _dnsCtrl.text,
                muxEnabled: v,
                muxProtocol: _config.muxProtocol,
                muxConcurrency: _config.muxConcurrency,
                fragmentEnabled: _config.fragmentEnabled,
                fragmentRange: _fragRangeCtrl.text.isEmpty
                    ? null
                    : _fragRangeCtrl.text,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('启用 Fragment'),
            subtitle: const Text('分片，绕过 SNI 探测'),
            value: _config.fragmentEnabled,
            onChanged: (v) => setState(
              () => _config = AdvancedConfig(
                remoteDnsOverride: _dnsCtrl.text.isEmpty ? null : _dnsCtrl.text,
                muxEnabled: _config.muxEnabled,
                muxProtocol: _config.muxProtocol,
                muxConcurrency: _config.muxConcurrency,
                fragmentEnabled: v,
                fragmentRange: _fragRangeCtrl.text.isEmpty
                    ? null
                    : _fragRangeCtrl.text,
              ),
            ),
          ),
          if (_config.fragmentEnabled)
            TextField(
              controller: _fragRangeCtrl,
              decoration: const InputDecoration(
                labelText: 'Fragment Range',
                hintText: '例：10-30',
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final updated = widget.profile.copyWith(advancedConfig: _currentConfig());
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.updateProfile(updated);
    if (mounted) Navigator.of(context).pop();
  }
}
