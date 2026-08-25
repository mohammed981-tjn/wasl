import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/orders_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import 'orders_tab.dart';

/// تفصيل الطلب: بنوده، وسجلّ أحداثه، ونقلُ حالته.
///
/// **الأزرار تُبنى من جدول `order_transitions` لا من قائمةٍ في الشيفرة.** فمسار
/// التشغيل إن تغيّر — أُضيفت مرحلة، أو مُنع انتقال — تغيّرت الأزرار بلا إصدار.
/// ولو ضغط المستخدم زرًّا لا يخوّله دوره، رفضه المحفّز في القاعدة وظهر السبب:
/// الشاشة تُخفي، والقاعدة تمنع.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _orders = const OrdersService();
  late Future<(LaundryOrder, List<OrderEvent>, List<OrderStatus>)> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = () async {
        final order = await _orders.byId(widget.orderId);
        final events = await _orders.events(widget.orderId);
        final next = await _orders.allowedNext(order.status);
        return (order, events, next);
      }();
    });
  }

  Future<void> _advance(OrderStatus to) async {
    setState(() => _busy = true);
    try {
      await _orders.advance(widget.orderId, to);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفصيل الطلب'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<(LaundryOrder, List<OrderEvent>, List<OrderStatus>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (order, events, next) = data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Header(order: order),
              const SizedBox(height: 20),
              _ItemsCard(order: order),
              const SizedBox(height: 20),
              _NextActions(
                next: next,
                busy: _busy,
                onPick: _advance,
              ),
              const SizedBox(height: 20),
              _Timeline(events: events),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('طلب #${order.orderNumber}',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                OrderStatusChip(status: order.status),
                const Spacer(),
                if (order.isLate)
                  Chip(
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                    label: const Text('متأخّر'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Line(label: 'العميل', value: order.customerName ?? '—'),
            _Line(label: 'الفرع', value: order.branchName ?? '—'),
            _Line(label: 'حالة الدفع', value: order.paymentStatus.labelAr),
            if (order.barcode != null)
              _Line(label: 'الباركود', value: order.barcode!),
            if (order.pickupSlotStart != null)
              _Line(
                  label: 'موعد الاستلام',
                  value: df.format(order.pickupSlotStart!)),
            if (order.promisedReadyAt != null)
              _Line(
                  label: 'وعد الجاهزية',
                  value: df.format(order.promisedReadyAt!)),
            if (order.deliverySlotStart != null)
              _Line(
                  label: 'موعد التسليم',
                  value: df.format(order.deliverySlotStart!)),
            if (order.customerNotes?.isNotEmpty == true)
              _Line(label: 'ملاحظات العميل', value: order.customerNotes!),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('البنود',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (order.items.isEmpty)
              Text('لا بنود مسجَّلة بعد.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final it in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${it.serviceNameAr} × '
                          '${it.quantity.toStringAsFixed(it.unit == PricingUnit.piece ? 0 : 1)} '
                          '${it.unit.labelAr}',
                        ),
                      ),
                      Text('${it.lineTotal.toStringAsFixed(2)} ر.س',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            const Divider(height: 24),
            _Money(label: 'المجموع', value: order.subtotal),
            _Money(label: 'التوصيل', value: order.deliveryFee),
            if (order.discountAmount > 0)
              _Money(label: 'الخصم', value: -order.discountAmount),
            if (order.vatAmount > 0)
              _Money(label: 'ضريبة القيمة المضافة', value: order.vatAmount),
            const SizedBox(height: 4),
            _Money(label: 'الإجمالي', value: order.total, bold: true),
          ],
        ),
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.label, required this.value, this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
            ),
            Text('${value.toStringAsFixed(2)} ر.س',
                style: TextStyle(
                    fontSize: bold ? 16 : 14,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      );
}

/// الانتقالات الممكنة — مقروءةً من القاعدة.
class _NextActions extends StatelessWidget {
  const _NextActions({
    required this.next,
    required this.busy,
    required this.onPick,
  });

  final List<OrderStatus> next;
  final bool busy;
  final void Function(OrderStatus) onPick;

  @override
  Widget build(BuildContext context) {
    if (next.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('لا انتقال بعد هذه الحالة'),
          subtitle: Text('انتهى مسار هذا الطلب.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الخطوة التالية',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'الخيارات مقروءةٌ من جدول الانتقالات في القاعدة. وإن لم يخوّلك '
              'دورُك أحدَها، رفضه الخادم وأخبرك بالسبب.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in next)
                  OutlinedButton(
                    onPressed: busy ? null : () => onPick(s),
                    child: Text(s.labelAr),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<OrderEvent> events;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MM-dd HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('السجلّ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (events.isEmpty)
              Text('لا أحداث بعد.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle,
                          size: 8,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.fromStatus == null
                                  ? e.toStatus.labelAr
                                  : '${e.fromStatus!.labelAr} ← ${e.toStatus.labelAr}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              [
                                df.format(e.createdAt),
                                // منفّذٌ فارغ = «النظام»، لا اسمٌ يُختلق.
                                e.actorName ?? e.note ?? 'النظام',
                                if (e.actorRole != null) e.actorRole!.labelAr,
                              ].join('  •  '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
