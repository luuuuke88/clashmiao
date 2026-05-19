import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Opens a full-screen QR scanner. Returns the scanned URL string,
/// or null if the user cancelled or camera permission was denied.
Future<String?> openQrScanner(BuildContext context) async {
  final status = await Permission.camera.request();
  if (!status.isGranted) return null;
  if (!context.mounted) return null;
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描订阅二维码')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_scanned) return;
          final raw = capture.barcodes.firstOrNull?.rawValue;
          if (raw != null && raw.isNotEmpty) {
            _scanned = true;
            Navigator.of(context).pop(raw);
          }
        },
      ),
    );
  }
}
