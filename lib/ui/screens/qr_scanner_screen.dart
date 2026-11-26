import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/i18n.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(L10n.instance.tr('ui.scan_qr_code')),
        actions: [
          IconButton(
            tooltip: L10n.instance.tr('ui.switch_camera'),
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          IconButton(
            tooltip: L10n.instance.tr('ui.flash'),
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    trf('image.could_not_start_camera__arg_0', [error.errorDetails?.message ?? error.errorCode.name]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Text(
              L10n.instance.tr('share.place_the_sharing_qr_code_inside_the_frame'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
