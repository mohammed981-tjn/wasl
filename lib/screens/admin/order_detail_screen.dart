import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/orders_service.dart';
import '../../services/payments_service.dart';
import '../../services/session_service.dart';
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
  late Future<(LaundryOrder, List<OrderEvent>, List<OrderStatus>,
      List<BranchDriver>, List<Payment>)> _future;
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
        // فشلُ جلب السائقين لا يُفشل الشاشة: التفصيل والسجلّ يُقرآن ولو تعذّر
        // الإسناد.
        List<BranchDriver> drivers = const [];
        try {
          drivers = await _orders.branchDrivers(order.branchId);
        } catch (_) {
          drivers = const [];
        }
        List<Payment> payments = const [];
        try {
          payments = await const PaymentsService().ofOrder(widget.orderId);
        } catch (_) {
          payments = const [];
        }
        return (order, events, next, drivers, payments);
      }();
    });
  }

  Future<void> _assign(bool pickup, String? driverId) async {
    setState(() => _busy = true);
    try {
      await _orders.assignDriver(
          orderId: widget.orderId, pickup: pickup, driverId: driverId);
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

  Future<void> _refund(Payment payment) async {
    final result = await showDialog<({double amount, String reason})>(
      context: context,
      builder: (_) => _RefundDialog(payment: payment),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      final failure = await const PaymentsService().refund(
        paymentId: payment.id,
        amount: result.amount,
        reason: result.reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure ?? 'نُفِّذ الاسترداد.')));
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
      body: AsyncView<(LaundryOrder, List<OrderEvent>, List<OrderStatus>,
          List<BranchDriver>, List<Payment>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (order, events, next, drivers, payments) = data;
          final session = context.watch<SessionService>();
          final canAssign = session.isSuperAdmin ||
              session.roles.any((r) =>
                  r.branchId == order.branchId &&
                  (r.role == AppRole.branchManager ||
                      r.role == AppRole.customerService));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Header(order: order),
              const SizedBox(height: 20),
              _ItemsCard(order: order),
              if (canAssign) ...[
                const SizedBox(height: 20),
                _DispatchCard(
                  order: order,
                  drivers: drivers,
                  busy: _busy,
                  onAssign: _assign,
                ),
              ],
              const SizedBox(height: 20),
              _PaymentsCard(
                payments: payments,
                canRefund: session.isSuperAdmin ||
                    session.hasRole(AppRole.accountant),
                busy: _busy,
                onRefund: _refund,
              ),
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

/// الإسناد: من يستلم ومن يسلّم.
///
/// **مرحلتان لا خانةٌ واحدة**: الطلب يُستلم في يومٍ ويُسلَّم في آخر، وقد
/// يحملهما سائقان — فخانةٌ واحدة تُخفي هذه الحقيقة وتُجبر الإدارة على إعادة
/// الكتابة فوق إسنادٍ لم ينته بعد.
class _DispatchCard extends StatelessWidget {
  const _DispatchCard({
    required this.order,
    required this.drivers,
    required this.busy,
    required this.onAssign,
  });

  final LaundryOrder order;
  final List<BranchDriver> drivers;
  final bool busy;
  final void Function(bool pickup, String? driverId) onAssign;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الإسناد',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (drivers.isEmpty)
              Text('لا سائق بدورٍ في هذا الفرع بعد — يُضاف من «الموظّفون».',
                  style: Theme.of(context).textTheme.bodySmall)
            else ...[
              Text('الرقم بجانب الاسم: مهامُّه المفتوحة الآن.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              _Picker(
                label: 'سائق الاستلام',
                value: order.pickupDriverId,
                drivers: drivers,
                enabled: !busy,
                onChanged: (v) => onAssign(true, v),
              ),
              const SizedBox(height: 12),
              _Picker(
                label: 'سائق التسليم',
                value: order.deliveryDriverId,
                drivers: drivers,
                enabled: !busy,
                onChanged: (v) => onAssign(false, v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.drivers,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<BranchDriver> drivers;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // المسنَد قد لا يكون في القائمة (سُحب دوره بعد الإسناد): يُعرض «بلا إسناد»
    // بدل أن ينهار الـDropdown على قيمةٍ لا عنصر لها.
    final known = drivers.any((d) => d.id == value);

    return DropdownButtonFormField<String?>(
      initialValue: known ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        helperText: value != null && !known ? 'المسنَد لم يعد سائقًا في الفرع' : null,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('بلا إسناد')),
        for (final d in drivers)
          DropdownMenuItem<String?>(
            value: d.id,
            child: Text('${d.name}  •  ${d.activeJobs}'),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// الدفعات وما استُردّ منها.
///
/// **تُعرض المحاولات الفاشلة كذلك**: «حاول ثلاثًا ثم دفع نقدًا» معلومةٌ تُقرأ
/// حين يتّصل العميل، ولوحةٌ تُظهر الناجحة وحدها تجعل شكواه بلا سياق.
class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({
    required this.payments,
    required this.canRefund,
    required this.busy,
    required this.onRefund,
  });

  final List<Payment> payments;
  final bool canRefund;
  final bool busy;
  final void Function(Payment) onRefund;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الدفعات',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (payments.isEmpty)
              Text('لا محاولة دفعٍ بالبطاقة على هذا الطلب.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final p in payments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (p.status) {
                      PaymentTxnStatus.captured => Icons.check_circle_outline,
                      PaymentTxnStatus.failed => Icons.cancel_outlined,
                      PaymentTxnStatus.pending => Icons.hourglass_empty,
                      _ => Icons.credit_card,
                    },
                    color: p.status == PaymentTxnStatus.failed
                        ? scheme.error
                        : p.status == PaymentTxnStatus.captured
                            ? scheme.primary
                            : scheme.outline,
                  ),
                  title: Text('${p.amount.toStringAsFixed(2)} ر.س — ${p.label}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.status.labelAr),
                      if (p.refunded > 0)
                        Text('استُردّ منها ${p.refunded.toStringAsFixed(2)} ر.س',
                            style: const TextStyle(fontSize: 12)),
                      if (p.failureMessage != null)
                        Text(p.failureMessage!,
                            style: TextStyle(fontSize: 12, color: scheme.error)),
                    ],
                  ),
                  trailing: canRefund && p.refundable > 0
                      ? TextButton(
                          onPressed: busy ? null : () => onRefund(p),
                          child: const Text('استرداد'),
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

/// حوار الاسترداد.
///
/// **السبب مطلوبٌ لا اختياريّ**: استردادٌ بلا سبب لا يُراجَع بعد شهر، وسطرٌ
/// واحد يكفي لأن يُعرف لماذا خرج المال.
class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.payment});

  final Payment payment;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final _amount =
      TextEditingController(text: widget.payment.refundable.toStringAsFixed(2));
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final reason = _reason.text.trim();
    if (amount <= 0 || amount > widget.payment.refundable) {
      setState(() => _error =
          'المبلغ بين ٠ و${widget.payment.refundable.toStringAsFixed(2)} ر.س');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'اكتب سببًا يُراجَع لاحقًا');
      return;
    }
    Navigator.of(context).pop((amount: amount, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استرداد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('القابل للاسترداد: '
              '${widget.payment.refundable.toStringAsFixed(2)} ر.س'),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'المبلغ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'تأخّر التسليم، قطعة تالفة…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('نفّذ')),
      ],
    );
  }
}
