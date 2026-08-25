import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/laundry_service.dart';
import '../../services/supabase_service.dart';
import 'order_intake_screen.dart';

/// مسحُ ملصق الطلب أو القطعة.
///
/// **الإدخال اليدوي ليس احتياطًا ثانويًّا بل ندٌّ للكاميرا**: الملصق يبتلّ،
/// والكاميرا تُمنع في المتصفّح، والهاتف القديم لا يركّز — ولا يجوز أن يقف
/// خطُّ التشغيل لأجل ذلك. لذا يظهر حقلُ الكتابة دائمًا أسفل الشاشة.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ops = const LaundryOpsService();
  final _manual = TextEditingController();

  // noDuplicates وحدَه لا يكفي: المسح يتكرّر بعد أن يفتح المستخدم شاشةً
  // ويعود، فنمنع المعالجة المتوازية بعلَمٍ صريح.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _busy = false;

  @override
  void dispose() {
    _manual.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);

    try {
      final hit = await _ops.resolve(code);
      if (!mounted) return;
      if (hit == null) {
        _say('لا يوجد طلبٌ بالرمز «$code».');
        setState(() => _busy = false);
        return;
      }

      if (hit.isGarment) {
        _say('قطعة: ${hit.garmentLabel ?? ''} — طلب #${hit.orderNumber}');
      }
      // استبدالٌ لا إضافة: الرجوع من شاشة الطلب يعود إلى خطّ التشغيل مباشرةً،
      // ولا يُعيد فتح كاميرا صارت خلف الشاشة.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderIntakeScreen(orderId: hit.orderId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _say(humanizeDbError(e));
      setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _open(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مسح الملصق'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (!state.isInitialized || !state.isRunning) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'إطفاء الضوء' : 'تشغيل الضوء',
                onPressed: () => _controller.toggleTorch(),
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, _) => _CameraUnavailable(
                    message: _cameraMessage(error),
                  ),
                  overlayBuilder: (context, constraints) => IgnorePointer(
                    child: Center(
                      child: Container(
                        width: constraints.maxWidth * 0.72,
                        height: constraints.maxWidth * 0.72,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Material(
            color: scheme.surface,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        enabled: !_busy,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _open,
                        decoration: const InputDecoration(
                          labelText: 'أو اكتب الرمز / رقم الطلب',
                          hintText: 'WSL-10042',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : () => _open(_manual.text),
                      child: const Text('فتح'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cameraMessage(MobileScannerException error) =>
      switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'لم يُسمح باستخدام الكاميرا. اكتب الرمز يدويًّا بالأسفل.',
        MobileScannerErrorCode.unsupported =>
          'الكاميرا غير مدعومة على هذا الجهاز. اكتب الرمز يدويًّا بالأسفل.',
        _ => 'تعذّر تشغيل الكاميرا. اكتب الرمز يدويًّا بالأسفل.',
      };
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
