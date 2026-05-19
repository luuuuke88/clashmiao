import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileDetailSheet extends ConsumerStatefulWidget {
  const ProfileDetailSheet({super.key, required this.profile});
  final ProfileEntity profile;

  @override
  ConsumerState<ProfileDetailSheet> createState() => _State();
}

class _State extends ConsumerState<ProfileDetailSheet> {
  late final _nameCtrl = TextEditingController(text: widget.profile.name);
  late final _uaCtrl = TextEditingController(
    text: widget.profile.customUserAgent ?? '',
  );
  late final _notesCtrl = TextEditingController(
    text: widget.profile.notes ?? '',
  );
  late int _intervalHours = widget.profile.updateInterval.inHours;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _uaCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

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
          Text('订阅详情', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _uaCtrl,
            decoration: const InputDecoration(
              labelText: 'User-Agent',
              hintText: '留空使用默认',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: [1, 6, 12, 24, 72].contains(_intervalHours)
                ? _intervalHours
                : 24,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 小时')),
              DropdownMenuItem(value: 6, child: Text('6 小时')),
              DropdownMenuItem(value: 12, child: Text('12 小时')),
              DropdownMenuItem(value: 24, child: Text('24 小时')),
              DropdownMenuItem(value: 72, child: Text('72 小时')),
            ],
            onChanged: (v) => setState(() => _intervalHours = v ?? 24),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: '备注'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final repo = await ref.read(profileRepositoryProvider.future);
    final updated = widget.profile.copyWith(
      name: _nameCtrl.text.trim(),
      customUserAgent: _uaCtrl.text.trim().isEmpty ? null : _uaCtrl.text.trim(),
      updateInterval: Duration(hours: _intervalHours),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await repo.updateProfile(updated);
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously
    Navigator.of(context).pop();
    ref.invalidate(profileListProvider);
  }
}
