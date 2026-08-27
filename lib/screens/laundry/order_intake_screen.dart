import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/laundry_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../customer/submit_complaint_screen.dart';
import 'count_compare.dart';

/// استقبال الطلب داخل المغسلة: جردُ القطع، ونقلُ المرحلة.
///
/// **الجرد هو الفرق بين مغسلةٍ ومستودع.** ما طلبه العميل تقدير، وما يجده
/// الفارز حقيقة — والفرق بينهما يُعرض هنا صراحةً لا يُطمس.
class OrderIntakeScreen extends StatefulWidget {
  const OrderIntakeScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderIntakeScreen> createState() => _OrderIntakeScreenState();
}

class _OrderIntakeScreenState extends State<OrderIntakeScreen> {
  final _ops = const LaundryOpsService();
  late Future<(LaundryOrder, List<OrderGarment>, List<OrderStatus>)> _future;

  /// الطلبُ كما جُلب — يحتاجه الشريطُ العلويّ، ويُضبط عند اكتمال الجلب لا
  /// في `build`: الشريطُ يُبنى قبل الجسد فيقرأ `null` أوّلَ مرّة.
  LaundryOrder? _order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final future = () async {
      final order = await _ops.order(widget.orderId);
      final garments = await _ops.garments(widget.orderId);
      final next = await _ops.allowedNext(order.status);
      return (order, garments, next);
    }();
    setState(() => _future = future);
    // الخطأ يعرضه `AsyncView`؛ وما يعنينا هنا ألّا يبقى زرُّ الشكوى معروضًا
    // على طلبٍ لم يُجلب.
    future.then(
      (data) {
        if (mounted) setState(() => _order = data.$1);
      },
      onError: (Object _) {
        if (mounted) setState(() => _order = null);
      },
    );
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
  }

  Future<void> _advance(OrderStatus to) async {
    setState(() => _busy = true);
    try {
      await _ops.advance(widget.orderId, to);
      _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGarment() async {
    final result = await showDialog<({String label, String? color, String? defect})>(
      context: context,
      builder: (_) => const _GarmentDialog(),
    );
    if (result == null) return;
    try {
      await _ops.addGarment(
        orderId: widget.orderId,
        labelAr: result.label,
        color: result.color,
        defectNotes: result.defect,
      );
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استقبال الطلب'),
        actions: [
          // **واختلافُ عدد القطع يُسجَّل شكوى لا يُروى شفاهًا.** «سلّمتُه
          // اثنتي عشرة» / «استلمتُ إحدى عشرة» نزاعٌ بلا سندٍ إن لم يُقيَّد
          // لحظتَه — وعندنا الباركودُ وعدُّ القطع في القاعدة، فالشكوى تُفتح
          // ومعها دليلٌ آليّ لا روايةُ طرفين.
          if (_order != null)
            IconButton(
              tooltip: 'مشكلةٌ في هذا الطلب',
              icon: const Icon(Icons.report_problem_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubmitComplaintScreen(
                    order: _order!,
                    role: 'laundry_staff',
                    parties: [
                      if (_order!.pickupDriverId != null)
                        (
                          id: _order!.pickupDriverId!,
                          name: 'سائق الاستلام',
                          role: 'driver'
                        ),
                      if (_order!.deliveryDriverId != null &&
                          _order!.deliveryDriverId != _order!.pickupDriverId)
                        (
                          id: _order!.deliveryDriverId!,
                          name: 'سائق التسليم',
                          role: 'driver'
                        ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<(LaundryOrder, List<OrderGarment>, List<OrderStatus>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (order, garments, next) = data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _OrderCard(order: order),
              const SizedBox(height: 16),
              CountCompare(order: order, garments: garments),
              const SizedBox(height: 16),
              _GarmentsCard(
                garments: garments,
                onAdd: _addGarment,
                onRemove: (g) async {
                  try {
                    await _ops.removeGarment(g.id);
                    _reload();
                  } catch (e) {
                    _showError(e);
                  }
                },
              ),
              const SizedBox(height: 16),
              _NextCard(next: next, busy: _busy, onPick: _advance),
            ],
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${order.orderNumber}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(order.customerName ?? 'عميل'),
                  Text(order.status.labelAr,
                      style: Theme.of(context).textTheme.bodySmall),
                  if (order.customerNotes?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text('ملاحظة: ${order.customerNotes}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            // رمز QR يُعرض ليُطبع أو يُمسح من شاشةٍ أخرى — الملصق قد يتلف،
            // والرمز هنا نسخةٌ احتياطية.
            if (order.barcode != null)
              Column(
                children: [
                  QrImageView(
                    data: order.barcode!,
                    size: 92,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 4),
                  Text(order.barcode!,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GarmentsCard extends StatelessWidget {
  const _GarmentsCard({
    required this.garments,
    required this.onAdd,
    required this.onRemove,
  });

  final List<OrderGarment> garments;
  final VoidCallback onAdd;
  final void Function(OrderGarment) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('القطع',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('قطعة'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('العيب يُوثَّق قبل الغسيل — بعده يصير كلمتَه ضدّ كلمتنا.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (garments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('لم تُجرَد قطعةٌ بعد.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else
              for (final g in garments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    g.hasDefect ? Icons.warning_amber_rounded : Icons.checkroom,
                    color: g.hasDefect ? scheme.error : null,
                  ),
                  title: Text(
                    [g.labelAr, if (g.color != null) g.color!].join(' — '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.barcode,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (g.hasDefect)
                        Text(g.defectNotes!,
                            style: TextStyle(
                                fontSize: 12, color: scheme.error)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onRemove(g),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
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
      return const Card(
        child: ListTile(
          leading: Icon(Icons.flag_outlined),
          title: Text('لا خطوة تالية من هنا'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الخطوة التالية',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            // أزرارٌ كبيرة: تُضغط بإبهامٍ مبلولٍ في مغسلة، لا بمؤشّر فأرة.
            for (final s in next)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: busy ? null : () => onPick(s),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    child: Text(s.labelAr),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GarmentDialog extends StatefulWidget {
  const _GarmentDialog();

  @override
  State<_GarmentDialog> createState() => _GarmentDialogState();
}

class _GarmentDialogState extends State<_GarmentDialog> {
  final _label = TextEditingController();
  final _color = TextEditingController();
  final _defect = TextEditingController();

  /// أشيعُ ما يُجرَد — نقرةٌ بدل كتابة. والفارز يسجّل عشرات القطع في الساعة.
  static const _common = [
    'ثوب', 'شماغ', 'بنطلون', 'قميص', 'عباءة',
    'فانلة', 'بشت', 'بطانية', 'مفرش',
  ];

  @override
  void dispose() {
    _label.dispose();
    _color.dispose();
    _defect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('قطعة جديدة'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _common)
                    ActionChip(
                      label: Text(c),
                      onPressed: () => setState(() => _label.text = c),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'نوع القطعة'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _color,
                decoration:
                    const InputDecoration(labelText: 'اللون (اختياريّ)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _defect,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'عيبٌ ملحوظ (اختياريّ)',
                  hintText: 'بقعة على الياقة، خيطٌ مفكوك…',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _label.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                    label: _label.text.trim(),
                    color: _color.text.trim().isEmpty
                        ? null
                        : _color.text.trim(),
                    defect: _defect.text.trim().isEmpty
                        ? null
                        : _defect.text.trim(),
                  )),
          child: const Text('تسجيل'),
        ),
      ],
    );
  }
}
