import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 订阅表单弹窗（新增 / 编辑 共用）
///
/// [profile] 不传 = 新增模式，传入 = 编辑模式
Future<void> showProfileFormDialog(
  BuildContext context,
  WidgetRef ref, {
  ProfileEntity? profile,
}) {
  final isEdit = profile != null;
  final nameCtrl = TextEditingController(text: profile?.name ?? '');
  final urlCtrl = TextEditingController(text: profile?.url ?? '');

  return showAiUiModal(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return AiUiModalWrapper(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                isEdit ? '编辑订阅' : '添加订阅',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 4),
                Text(
                  '输入订阅链接或从剪贴板粘贴',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 名称
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '订阅名称',
                  hintText: isEdit ? '' : '自动识别（可选）',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(FluentIcons.tag_24_regular),
                ),
              ),
              const SizedBox(height: 12),

              // 链接
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: '订阅链接',
                  hintText: 'https://',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(FluentIcons.link_24_regular),
                  suffixIcon: IconButton(
                    icon: const Icon(FluentIcons.clipboard_paste_24_regular),
                    tooltip: '从剪贴板粘贴',
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        urlCtrl.text = data.text!;
                      }
                    },
                  ),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),

              // 提交
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    if (isEdit) {
                      await _doEdit(context, ref, profile.id,
                          name: nameCtrl.text, url: urlCtrl.text);
                    } else {
                      final url = urlCtrl.text.trim();
                      if (url.isEmpty) return;
                      final name = nameCtrl.text.trim();
                      await _doAdd(context, ref, url,
                          customName: name.isEmpty ? null : name);
                    }
                  },
                  child: Text(isEdit ? '保存' : '添加'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _doAdd(
  BuildContext context,
  WidgetRef ref,
  String url, {
  String? customName,
}) async {
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.addByUrl(url, customName: customName);
    ref.invalidate(profileListProvider);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(offlineProxyGroupsProvider);
    if (context.mounted) AppToast.success(context, '添加成功');
  } catch (e) {
    if (context.mounted) AppToast.error(context, '添加失败: $e');
  }
}

Future<void> _doEdit(
  BuildContext context,
  WidgetRef ref,
  String id, {
  String? name,
  String? url,
}) async {
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.editProfile(id, newName: name, newUrl: url);
    ref.invalidate(profileListProvider);
    if (context.mounted) AppToast.success(context, '保存成功');
  } catch (e) {
    if (context.mounted) AppToast.error(context, '保存失败: $e');
  }
}
