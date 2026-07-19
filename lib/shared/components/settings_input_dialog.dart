import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingsInputDialog<T> extends ConsumerStatefulWidget {
  const SettingsInputDialog({
    super.key,
    required this.title,
    required this.initialValue,
    this.mapTo,
    this.validator,
    this.valueFormatter,
    this.onReset,
    this.optionalAction,
    this.icon,
    this.digitsOnly = false,
    this.keyboardType,
    this.hint,
    this.onConfirm,
  });

  final String title;
  final T initialValue;
  final T? Function(String value)? mapTo;
  final bool Function(String value)? validator;
  final String Function(T value)? valueFormatter;
  final VoidCallback? onReset;
  final (String text, VoidCallback action)? optionalAction;
  final IconData? icon;
  final bool digitsOnly;
  final TextInputType? keyboardType;
  final String? hint;
  final Future<bool> Function(String value)? onConfirm;

  Future<T?> show(BuildContext context) {
    return showAiUiModal<T>(context: context, builder: (context) => this);
  }

  @override
  ConsumerState<SettingsInputDialog<T>> createState() =>
      _SettingsInputDialogState<T>();
}

class _SettingsInputDialogState<T>
    extends ConsumerState<SettingsInputDialog<T>> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text:
          widget.valueFormatter?.call(widget.initialValue) ??
          widget.initialValue.toString(),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final localizations = MaterialLocalizations.of(context);

    return AiUiModalWrapper(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 200.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 200.ms),
            const SizedBox(height: 20),
            _SettingsTextField(
                  controller: _textController,
                  title: widget.title,
                  hint: widget.hint,
                  digitsOnly: widget.digitsOnly,
                  keyboardType: widget.keyboardType,
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 250.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 250.ms),
            const SizedBox(height: 24),
            Row(
                  children: [
                    if (widget.onReset != null) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            widget.onReset!();
                            await Navigator.of(context).maybePop(null);
                          },
                          style: _outlineStyle(),
                          child: Text(t.general.reset.toUpperCase()),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Navigator.of(context).maybePop();
                        },
                        style: _outlineStyle(),
                        child: Text(
                          localizations.cancelButtonLabel.toUpperCase(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(localizations.okButtonLabel.toUpperCase()),
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 300.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 300.ms),
            if (widget.optionalAction != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        widget.optionalAction!.$2();
                        await Navigator.of(context).maybePop(_stringValue());
                      },
                      child: Text(widget.optionalAction!.$1.toUpperCase()),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 350.ms)
                  .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 350.ms),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (widget.validator?.call(text) == false) return;
    if (widget.onConfirm != null) {
      final ok = await widget.onConfirm!(text);
      if (!mounted || !ok) return;
    }
    final mapped = widget.mapTo?.call(text);
    if (widget.mapTo != null) {
      await Navigator.of(context).maybePop(mapped);
      return;
    }
    await Navigator.of(context).maybePop(_stringValue());
  }

  T? _stringValue() {
    if (T == String) return _textController.text.trim() as T;
    return null;
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.controller,
    required this.title,
    this.hint,
    this.digitsOnly = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String title;
  final String? hint;
  final bool digitsOnly;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      keyboardType: keyboardType,
      inputFormatters: [
        FilteringTextInputFormatter.singleLineFormatter,
        if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
      ],
      autocorrect: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint ?? title,
        hintStyle: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class SettingsSliderDialog extends ConsumerStatefulWidget {
  const SettingsSliderDialog({
    super.key,
    required this.title,
    required this.initialValue,
    this.onReset,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.labelGen,
  });

  final String title;
  final double initialValue;
  final VoidCallback? onReset;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value)? labelGen;

  Future<double?> show(BuildContext context) {
    return showAiUiModal<double>(context: context, builder: (context) => this);
  }

  @override
  ConsumerState<SettingsSliderDialog> createState() =>
      _SettingsSliderDialogState();
}

class _SettingsSliderDialogState extends ConsumerState<SettingsSliderDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(widget.min, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final localizations = MaterialLocalizations.of(context);
    final label = widget.labelGen?.call(_value);

    return AiUiModalWrapper(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 200.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 200.ms),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Slider(
                  value: _value,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  onChanged: (value) => setState(() => _value = value),
                  label: label,
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 250.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 250.ms),
            const SizedBox(height: 24),
            Row(
                  children: [
                    if (widget.onReset != null) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            widget.onReset!();
                            await Navigator.of(context).maybePop(null);
                          },
                          style: _outlineStyle(),
                          child: Text(t.general.reset.toUpperCase()),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await Navigator.of(context).maybePop();
                        },
                        style: _outlineStyle(),
                        child: Text(
                          localizations.cancelButtonLabel.toUpperCase(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await Navigator.of(context).maybePop(_value);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(localizations.okButtonLabel.toUpperCase()),
                      ),
                    ),
                  ],
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 300.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 300.ms),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
