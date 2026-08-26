import 'package:flutter/material.dart';
// intl يصدّر `TextDirection` خاصًّا به يحجب نظيرَ Flutter، فيُخفى.
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/feedback_service.dart';
import '../../services/orders_service.dart';
import '../../services/payments_service.dart';
import '../../widgets/async_view.dart';
import 'pay_card.dart';
import 'rating_card.dart';

/// تتبّع الطلب.
///
/// **الخطّ الزمنيّ كاملٌ منذ اللحظة الأولى** — لا المراحل المنقضية وحدها. من
/// يرى الطريق كلَّه يعرف أين هو منه وكم بقي؛ ومن يرى ما مضى فقط يسأل «وماذا
/// بعد؟» — وسؤالُه يصل الدعم.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    this.justPlaced = false,
    this.payNow = false,
  });

  final String orderId;

  /// وصل إلى هنا من إتمام الطلب — فيُهنَّأ مرّةً ولا يُترك في شاشةٍ باردة.
  final bool justPlaced;

  /// اختار البطاقة، فتُفتح صفحة الدفع من تلقاء نفسها مرّةً واحدة.
  final bool payNow;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _orders = const OrdersService();
  late Future<(LaundryOrder, List<OrderEvent>, List<Payment>, OrderRating?)>
      _future;

  /// يُفتح الدفع تلقائيًّا **مرّةً**: فتحُه عند كل إعادة بناءٍ يفتح نوافذ بلا
  /// عدد على من عاد من الصفحة ولم يدفع.
  bool _autoPayDone = false;

  /// المسار المعتاد كما يراه العميل. والحالات الاستثنائية (موقوف، ملغى) لا
  /// تُعرض في الخطّ بل تُعلَن فوقه: مكانُها ليس خطوةً في طريق.
  static const _path = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.pickedUp,
    OrderStatus.atLaundry,
    OrderStatus.washing,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = () async {
        final o = await _orders.byId(widget.orderId);
        final e = await _orders.events(widget.orderId);
        // الدفعات تكميليّة: تعذّرها لا يُخفي تتبّع الطلب.
        List<Payment> p = const [];
        try {
          p = await const PaymentsService().ofOrder(widget.orderId);
        } catch (_) {
          p = const [];
        }
        OrderRating? rating;
        if (o.status == OrderStatus.delivered) {
          try {
            rating = await const FeedbackService().ratingOf(widget.orderId);
          } catch (_) {
            rating = null;
          }
        }
        return (o, e, p, rating);
      }();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تتبّع الطلب'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<
          (LaundryOrder, List<OrderEvent>, List<Payment>, OrderRating?)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (order, events, payments, rating) = data;
          final reached = {for (final e in events) e.toStatus};
          final df = DateFormat('MM-dd HH:mm');

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.justPlaced) ...[
                _Success(orderNumber: order.orderNumber),
                const SizedBox(height: 20),
              ],
              _Head(order: order),
              // التقييم أوّلًا بعد التسليم: هو ما جاء لأجله من رسالة «سُلّم».
              if (order.status == OrderStatus.delivered) ...[
                const SizedBox(height: 16),
                RatingCard(
                  orderId: order.id,
                  existing: rating,
                  hasDriver: order.deliveryDriverId != null,
                  onSaved: _reload,
                ),
              ],
              if (PaymentsService.owesPayment(order)) ...[
                const SizedBox(height: 16),
                PayCard(
                  order: order,
                  payments: payments,
                  autoOpen: widget.payNow && !_autoPayDone,
                  onAutoOpened: () => _autoPayDone = true,
                  onPaid: _reload,
                ),
              ],
              const SizedBox(height: 24),

              if (order.status == OrderStatus.cancelled ||
                  order.status == OrderStatus.onHold ||
                  order.status == OrderStatus.refunded)
                _Exception(status: order.status)
              else
                for (var i = 0; i < _path.length; i++)
                  _Step(
                    label: _path[i].labelAr,
                    done: reached.contains(_path[i]) ||
                        order.status.index > _path[i].index,
                    current: order.status == _path[i],
                    isLast: i == _path.length - 1,
                    at: events
                        .cast<OrderEvent?>()
                        .firstWhere((e) => e?.toStatus == _path[i],
                            orElse: () => null)
                        ?.createdAt,
                    format: df,
                  ),

              const SizedBox(height: 24),
              _Items(order: order),
            ],
          );
        },
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.orderNumber});

  final int orderNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, size: 44, color: scheme.primary),
          const SizedBox(height: 10),
          Text('استلمنا طلبك',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: scheme.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text('رقم الطلب #$orderNumber — احتفظ به.',
              style: TextStyle(color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${order.orderNumber}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text('${order.total.toStringAsFixed(2)} ر.س',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(order.branchName ?? '',
                style: Theme.of(context).textTheme.bodySmall),
            if (order.pickupSlotStart != null)
              Text('الاستلام: ${df.format(order.pickupSlotStart!)}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (order.promisedReadyAt != null)
              Text('الجاهزية المتوقّعة: ${df.format(order.promisedReadyAt!)}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Exception extends StatelessWidget {
  const _Exception({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              switch (status) {
                OrderStatus.cancelled => 'أُلغي هذا الطلب.',
                OrderStatus.refunded => 'استُردّ مبلغ هذا الطلب.',
                _ => 'الطلب موقوفٌ مؤقّتًا — سيتواصل معك الفرع.',
              },
              style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.current,
    required this.isLast,
    required this.format,
    this.at,
  });

  final String label;
  final bool done;
  final bool current;
  final bool isLast;
  final DateTime? at;
  final DateFormat format;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = done || current;
    final color = current
        ? scheme.primary
        : (done ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? color : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: color),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: current ? FontWeight.w900 : FontWeight.w600,
                      color: active ? null : scheme.outline,
                    ),
                  ),
                  if (at != null)
                    Text(format.format(at!),
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الفاتورة',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final it in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${it.serviceNameAr} × '
                            '${it.quantity.toStringAsFixed(it.unit == PricingUnit.kilogram ? 1 : 0)}'),
                      ),
                      Text('${it.lineTotal.toStringAsFixed(2)} ر.س'),
                    ],
                  ),
                ),
              const Divider(height: 20),
              _row(context, 'المجموع', order.subtotal),
              _row(context, 'التوصيل', order.deliveryFee),
              if (order.discountAmount > 0)
                _row(context, 'الخصم', -order.discountAmount),
              if (order.vatAmount > 0)
                _row(context, 'ضريبة القيمة المضافة', order.vatAmount),
              const SizedBox(height: 4),
              _row(context, 'الإجمالي', order.total, bold: true),
            ],
          ),
        ),
      );

  Widget _row(BuildContext context, String label, double v,
          {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight:
                            bold ? FontWeight.w800 : FontWeight.w400))),
            Text('${v.toStringAsFixed(2)} ر.س',
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      );
}
