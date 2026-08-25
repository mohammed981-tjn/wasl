import 'package:flutter/material.dart';
// intl يصدّر `TextDirection` خاصًّا به يحجب نظيرَ Flutter، فيُخفى.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/marketing_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// الكوبونات.
///
/// **يُعرض الاستهلاك لا الإعداد وحده**: كوبونٌ حدُّه مئةٌ واستُهلك تسعًا
/// وتسعين معلومةٌ تشغيلية، وإخفاؤها يجعل نفادَه مفاجأةً للعميل على الشاشة.
class CouponsTab extends StatefulWidget {
  const CouponsTab({super.key});

  @override
  State<CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<CouponsTab> {
  final _marketing = const MarketingService();
  late Future<List<Coupon>> _future;
  String? _laundryId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranch?.laundryId;
    if (id != _laundryId) {
      _laundryId = id;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = _laundryId == null
          ? Future.value(const <Coupon>[])
          : _marketing.coupons(_laundryId!);
    });
  }

  bool get _canEdit => context
      .read<SessionService>()
      .hasRoleInActiveBranch({AppRole.branchManager});

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
  }

  Future<void> _edit([Coupon? existing]) async {
    final laundryId = _laundryId;
    if (laundryId == null) return;
    final result = await showDialog<Coupon>(
      context: context,
      builder: (_) => _CouponDialog(laundryId: laundryId, existing: existing),
    );
    if (result == null) return;
    try {
      await _marketing.save(result);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('كوبون جديد'),
            )
          : null,
      body: AsyncView<List<Coupon>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا كوبونات بعد',
        builder: (context, coupons) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            Text('الكوبونات',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'الحدود أهمّ من القيمة: كوبونٌ بلا سقفٍ يُنشر فيُستهلك في ساعة.'
                  : 'العرض فقط: التعديل لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final c in coupons)
              _CouponCard(
                coupon: c,
                canEdit: canEdit,
                onEdit: () => _edit(c),
                onToggle: () async {
                  try {
                    await _marketing.setActive(c.id, !c.isActive);
                    _reload();
                  } catch (e) {
                    _showError(e);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
  });

  final Coupon coupon;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('yyyy-MM-dd');

    // سببُ التوقّف يُقال بعينه: «موقوف» و«منتهٍ» و«نفد» ثلاثة قرارات مختلفة.
    final (statusText, statusColor) = switch (coupon) {
      _ when !coupon.isActive => ('موقوف', scheme.outline),
      _ when coupon.isExpired => ('انتهت صلاحيته', scheme.error),
      _ when coupon.isExhausted => ('نفد', scheme.error),
      _ => ('يعمل', scheme.primary),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(coupon.code,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
                const SizedBox(width: 10),
                Text(coupon.valueLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusText,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
                const Spacer(),
                if (canEdit) ...[
                  IconButton(
                    tooltip: coupon.isActive ? 'إيقاف' : 'تفعيل',
                    onPressed: onToggle,
                    icon: Icon(coupon.isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline),
                  ),
                  IconButton(
                      tooltip: 'تعديل',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (coupon.maxDiscount != null)
                  _Fact('بحدّ أقصى ${coupon.maxDiscount!.toStringAsFixed(0)} ر.س'),
                if (coupon.minSubtotal > 0)
                  _Fact('يبدأ من ${coupon.minSubtotal.toStringAsFixed(0)} ر.س'),
                _Fact(coupon.maxUsesTotal == 0
                    ? 'استُهلك ${coupon.redemptions} مرّة (بلا حدّ)'
                    : 'استُهلك ${coupon.redemptions} من ${coupon.maxUsesTotal}'),
                _Fact(coupon.maxUsesPerUser == 0
                    ? 'بلا حدٍّ لكل عميل'
                    : '${coupon.maxUsesPerUser} لكل عميل'),
                if (coupon.firstOrderOnly) const _Fact('لأول طلب فقط'),
                if (coupon.endsAt != null)
                  _Fact('حتى ${df.format(coupon.endsAt!)}'),
              ],
            ),
            // شريطُ الاستهلاك يُرى قبل أن يُفاجئ: من يقترب من حدّه يُمدَّد أو
            // يُوقَف بقرار، لا بشكوى عميل.
            if (coupon.maxUsesTotal > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (coupon.redemptions / coupon.maxUsesTotal).clamp(0, 1),
                  minHeight: 6,
                  color: coupon.isExhausted ? scheme.error : scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.bodySmall);
}

class _CouponDialog extends StatefulWidget {
  const _CouponDialog({required this.laundryId, this.existing});

  final String laundryId;
  final Coupon? existing;

  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _maxDiscount;
  late final TextEditingController _minSubtotal;
  late final TextEditingController _maxTotal;
  late final TextEditingController _maxPerUser;
  late CouponKind _kind;
  late bool _firstOnly;
  late bool _active;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _value = TextEditingController(
        text: e == null ? '' : e.value.toStringAsFixed(2));
    _maxDiscount =
        TextEditingController(text: e?.maxDiscount?.toStringAsFixed(2) ?? '');
    _minSubtotal =
        TextEditingController(text: (e?.minSubtotal ?? 0).toStringAsFixed(2));
    _maxTotal = TextEditingController(text: '${e?.maxUsesTotal ?? 0}');
    _maxPerUser = TextEditingController(text: '${e?.maxUsesPerUser ?? 1}');
    _kind = e?.kind ?? CouponKind.percentage;
    _firstOnly = e?.firstOrderOnly ?? false;
    _active = e?.isActive ?? true;
    _endsAt = e?.endsAt;
  }

  @override
  void dispose() {
    for (final c in [_code, _value, _maxDiscount, _minSubtotal, _maxTotal,
                     _maxPerUser]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsValue = _kind != CouponKind.freeDelivery;
    final df = DateFormat('yyyy-MM-dd');

    return AlertDialog(
      title: Text(widget.existing == null ? 'كوبون جديد' : 'تعديل الكوبون'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  textDirection: TextDirection.ltr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'الرمز',
                    hintText: 'WELCOME30',
                    helperText: 'يُقارَن بلا حساسيةٍ لحالة الأحرف',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CouponKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'النوع'),
                  items: [
                    for (final k in CouponKind.values)
                      DropdownMenuItem(value: k, child: Text(k.labelAr)),
                  ],
                  onChanged: (v) => setState(() => _kind = v ?? _kind),
                ),
                if (needsValue) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _value,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _kind == CouponKind.percentage
                          ? 'النسبة (٪)'
                          : 'المبلغ (ر.س)',
                    ),
                    validator: (v) {
                      final d = double.tryParse(v?.trim() ?? '');
                      if (d == null) return 'أدخل رقمًا';
                      if (d <= 0) return 'أكبر من صفر';
                      if (_kind == CouponKind.percentage && d > 100) {
                        return 'النسبة لا تتجاوز ١٠٠';
                      }
                      return null;
                    },
                  ),
                ],
                if (_kind == CouponKind.percentage) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _maxDiscount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سقف الخصم (ر.س)',
                      helperText:
                          'بدونه يبتلع كوبونُ نصفٍ فاتورةَ سجّادٍ بألف ريال',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minSubtotal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'أقلّ قيمة طلب', helperText: 'صفر = بلا حدّ'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _maxTotal,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'حدّ الاستخدام الكلّي',
                            helperText: 'صفر = بلا حدّ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxPerUser,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'لكل عميل'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ينتهي في'),
                  subtitle: Text(_endsAt == null
                      ? 'بلا تاريخ انتهاء'
                      : df.format(_endsAt!)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_endsAt != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _endsAt = null),
                        ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today_outlined),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endsAt ??
                                now.add(const Duration(days: 30)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 730)),
                          );
                          if (picked != null) setState(() => _endsAt = picked);
                        },
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _firstOnly,
                  onChanged: (v) => setState(() => _firstOnly = v),
                  title: const Text('لأول طلب فقط'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('مفعّل'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              Coupon(
                id: widget.existing?.id ?? '',
                laundryId: widget.laundryId,
                code: _code.text.trim().toUpperCase(),
                kind: _kind,
                value: double.tryParse(_value.text.trim()) ?? 0,
                maxDiscount: _maxDiscount.text.trim().isEmpty
                    ? null
                    : double.tryParse(_maxDiscount.text.trim()),
                minSubtotal: double.tryParse(_minSubtotal.text.trim()) ?? 0,
                endsAt: _endsAt,
                maxUsesTotal: int.tryParse(_maxTotal.text.trim()) ?? 0,
                maxUsesPerUser: int.tryParse(_maxPerUser.text.trim()) ?? 1,
                firstOrderOnly: _firstOnly,
                isActive: _active,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
