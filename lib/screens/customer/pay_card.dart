import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/payments_service.dart';
import '../../services/supabase_service.dart';

/// بطاقةُ «ادفع الآن» في شاشة التتبّع.
///
/// **الدفع خطوةٌ منفصلةٌ عن الطلب، وقابلةٌ للإعادة.** الطلب وُضع فعلًا، فلا
/// يجوز أن يضيّعه فشلُ صفحة الدفع أو إغلاقُها. ولذلك يبقى الزرّ هنا حتى يُدفع
/// الطلب أو يُغلق.
///
/// **ولا تُعلَن النتيجة من عودة المتصفّح.** العائد من صفحة المزوّد لا يُصدَّق:
/// إنما تُعتمد حالةُ الدفع من القاعدة، وهي لا تتغيّر إلا بإشعارٍ خلفيٍّ موقَّع.
class PayCard extends StatefulWidget {
  const PayCard({
    super.key,
    required this.order,
    required this.payments,
    required this.onPaid,
    this.autoOpen = false,
    this.onAutoOpened,
  });

  final LaundryOrder order;
  final List<Payment> payments;

  /// يُنادى بعد العودة من صفحة الدفع كي تُعاد قراءة الحالة من القاعدة.
  final VoidCallback onPaid;

  final bool autoOpen;
  final VoidCallback? onAutoOpened;

  @override
  State<PayCard> createState() => _PayCardState();
}

class _PayCardState extends State<PayCard> {
  final _payments = const PaymentsService();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpen) {
      widget.onAutoOpened?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) => _pay());
    }
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _payments.start(widget.order.id);
      final opened = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!opened) {
        setState(() => _error = 'تعذّر فتح صفحة الدفع في المتصفّح.');
      } else if (mounted) {
        widget.onPaid();
      }
    } on PaymentException catch (e) {
      if (mounted) setState(() => _error = e.messageAr);
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final order = widget.order;

    // المحاولة الفاشلة الأخيرة تُقال للعميل: «حاولتُ ولم يحدث شيء» أسوأ من
    // «رفضت البطاقة».
    final lastFailed = widget.payments
        .cast<Payment?>()
        .firstWhere((p) => p?.status == PaymentTxnStatus.failed,
            orElse: () => null);

    final cash = order.paymentMethod == PaymentMethod.cashOnDelivery ||
        order.paymentMethod == PaymentMethod.cashOnPickup;
    final when = order.paymentMethod == PaymentMethod.cashOnPickup
        ? 'عند الاستلام'
        : 'عند التسليم';

    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card, size: 20),
                const SizedBox(width: 8),
                Text(
                  cash ? 'الدفع نقدًا $when' : 'بانتظار الدفع',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text('${order.total.toStringAsFixed(2)} ر.س',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              cash
                  ? 'تدفع نقدًا $when — وتستطيع الدفع بالبطاقة الآن إن أردت.'
                  : 'أكمِل الدفع في صفحة مزوّد الدفع الآمنة.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (lastFailed?.failureMessage != null) ...[
              const SizedBox(height: 8),
              Text('آخر محاولة: ${lastFailed!.failureMessage}',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _pay,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_outline, size: 18),
                label: Text(_busy ? 'جارٍ الفتح…' : 'ادفع بالبطاقة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
