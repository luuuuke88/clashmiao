import 'dart:async';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Opens a full-screen QR scanner. Returns the scanned URL string,
/// or null if the user cancelled or camera permission was denied.
Future<String?> openQrScanner(BuildContext context) async {
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const QrScannerPage(),
    ),
  );
}

@visibleForTesting
class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({
    super.key,
    this.skipPermissionCheck = false,
    this.initialPermissionStatus,
  });

  const QrScannerPage.permissionDeniedPreview({super.key})
    : skipPermissionCheck = false,
      initialPermissionStatus = PermissionStatus.denied;

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();

  final bool skipPermissionCheck;
  final PermissionStatus? initialPermissionStatus;
}

class _QrScannerPageState extends ConsumerState<QrScannerPage>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    detectionTimeoutMs: 500,
    autoStart: false,
  );
  bool _scanned = false;
  bool _started = false;
  PermissionStatus? _permissionStatus;

  bool get _hasPermission =>
      widget.skipPermissionCheck || (_permissionStatus?.isGranted ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialPermissionStatus != null) {
      _permissionStatus = widget.initialPermissionStatus;
      if (widget.initialPermissionStatus!.isGranted) {
        unawaited(_startScanner());
      }
      return;
    }
    unawaited(_initializeScanner());
  }

  @override
  void dispose() {
    _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPermissionAndStartScanner());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_controller.stop());
      _started = false;
    }
  }

  Future<void> _initializeScanner() async {
    if (widget.skipPermissionCheck) {
      if (mounted) setState(() => _permissionStatus = PermissionStatus.granted);
      await _startScanner();
      return;
    }

    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permissionStatus = status);
    if (status.isGranted) await _startScanner();
  }

  Future<void> _checkPermissionAndStartScanner() async {
    if (widget.skipPermissionCheck) return;
    final status = await Permission.camera.status;
    if (!mounted) return;
    setState(() => _permissionStatus = status);
    if (status.isGranted && !_started) await _startScanner();
  }

  Future<void> _startScanner() async {
    if (!mounted || _started) return;
    try {
      await _controller.stop();
      await _controller.start();
      if (!mounted) return;
      setState(() => _started = true);
    } catch (error) {
      debugPrint('Error starting QR scanner: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);

    if (_permissionStatus == null && !widget.skipPermissionCheck) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return _PermissionDeniedView(
        title: t.profile.add.qrScanner.permissionDeniedError,
        actionLabel: 'Settings',
        onSettingsPressed: openAppSettings,
      );
    }

    return _ScannerView(
      controller: _controller,
      started: _started,
      onDetect: _handleDetect,
      torchTooltip: t.profile.add.qrScanner.torchSemanticLabel,
      cameraTooltip: t.profile.add.qrScanner.facingSemanticLabel,
      permissionError: t.profile.add.qrScanner.permissionDeniedError,
      unknownError: t.profile.add.qrScanner.unexpectedError,
    );
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    _scanned = true;
    Navigator.of(context, rootNavigator: true).pop(uri.toString());
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView({
    required this.controller,
    required this.started,
    required this.onDetect,
    required this.torchTooltip,
    required this.cameraTooltip,
    required this.permissionError,
    required this.unknownError,
  });

  final MobileScannerController controller;
  final bool started;
  final void Function(BarcodeCapture capture) onDetect;
  final String torchTooltip;
  final String cameraTooltip;
  final String permissionError;
  final String unknownError;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final overlaySize = (size.shortestSide - 12).clamp(0.0, 248.0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: Theme.of(
          context,
        ).iconTheme.copyWith(color: Colors.white, size: 32),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.flash_24_regular),
            tooltip: torchTooltip,
            onPressed: controller.toggleTorch,
          ),
          IconButton(
            icon: const Icon(FluentIcons.camera_switch_24_regular),
            tooltip: cameraTooltip,
            onPressed: controller.switchCamera,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: onDetect,
            errorBuilder: (_, error, __) {
              final message =
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? permissionError
                  : unknownError;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Icon(
                          FluentIcons.error_circle_24_regular,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (error.errorDetails?.message != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          error.errorDetails!.message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          if (started)
            CustomPaint(
              painter: ScannerOverlay(
                Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: overlaySize,
                  height: overlaySize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.title,
    required this.actionLabel,
    required this.onSettingsPressed,
  });

  final String title;
  final String actionLabel;
  final Future<bool> Function() onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: Theme.of(
          context,
        ).iconTheme.copyWith(color: Colors.white, size: 32),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onSettingsPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
class ScannerOverlay extends CustomPainter {
  ScannerOverlay(this.scanWindow);

  final Rect scanWindow;
  final double borderRadius = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Offset.zero & size);
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)),
      );

    final backgroundWithCutout = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(
      backgroundWithCutout,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant ScannerOverlay oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}
