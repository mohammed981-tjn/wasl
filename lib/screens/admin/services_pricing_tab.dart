import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// الخدمات والأسعار.
///
/// **هذه الشاشة هي الوعد الأساسيّ للنظام**: «ثوب غسيل = ٨ ريال» صفٌّ يُعدَّل
/// من هنا، لا ثابتٌ في شيفرة Dart يحتاج إصدارًا جديدًا على المتجر ليُبدَّل.
/// وكذلك المدّة والحدّ الأدنى ووحدة القياس ومضاعِف الاستعجال.
///
/// وموظّف المغسلة **لا يفتحها**: سياسة `services_write` تشترط `branch_manager`
/// فأعلى، فحتى لو رآها بحزمةٍ معدَّلة لَما قبلت القاعدة حفظًا واحدًا.
class ServicesPricingTab extends StatefulWidget {
  const ServicesPricingTab({super.key});

  @override
  State<ServicesPricingTab> createState() => _ServicesPricingTabState();
}

class _ServicesPricingTabState extends State<ServicesPricingTab> {
  final _catalog = const CatalogService();
  late Future<List<LaundryService>> _future;
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
          ? Future.value(const <LaundryService>[])
          : _catalog.services(_laundryId!);
    });
  }

  bool get _canEdit => context
      .read<SessionService>()
      .hasRoleInActiveBranch({AppRole.branchManager});

  Future<void> _edit([LaundryService? existing]) async {
    final laundryId = _laundryId;
    if (laundryId == null) return;

    final result = await showDialog<LaundryService>(
      context: context,
      builder: (_) => _ServiceDialog(laundryId: laundryId, existing: existing),
    );
    if (result == null) return;

    try {
      if (existing == null) {
        await _catalog.create(result);
      } else {
        await _catalog.update(result);
      }
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _toggle(LaundryService s) async {
    try {
      await _catalog.setActive(s.id, !s.isActive);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(humanizeDbError(e))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;

    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('خدمة جديدة'),
            )
          : null,
      body: AsyncView<List<LaundryService>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا خدمات بعد — أضِف أوّل خدمة',
        builder: (context, services) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            Text('الخدمات والأسعار',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'كل ما هنا يُعدَّل فورًا — بلا إصدار تطبيق جديد.'
                  : 'العرض فقط: تعديل الأسعار لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final s in services)
              _ServiceCard(
                service: s,
                canEdit: canEdit,
                onEdit: () => _edit(s),
                onToggle: () => _toggle(s),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
  });

  final LaundryService service;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = !service.isActive;

    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Row(
            children: [
              Flexible(
                child: Text(service.nameAr,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              if (!service.isActive)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('موقوفة', style: TextStyle(fontSize: 11)),
                ),
              if (service.acceptsExpress)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.tertiaryContainer,
                    label: Text('استعجال ×${service.expressMultiplier}',
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Fact(icon: Icons.sell_outlined,
                    text: '${service.basePrice.toStringAsFixed(2)} ر.س / ${service.unit.labelAr}'),
                _Fact(icon: Icons.timer_outlined,
                    text: 'خلال ${service.turnaroundHours} ساعة'),
                if (service.minQuantity > 0)
                  _Fact(icon: Icons.filter_1_outlined,
                      text: 'حدّ أدنى ${service.minQuantity.toStringAsFixed(0)}'),
              ],
            ),
          ),
          trailing: canEdit
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: service.isActive ? 'إيقاف مؤقّت' : 'تفعيل',
                      onPressed: onToggle,
                      icon: Icon(service.isActive
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'تعديل',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).hintColor),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({required this.laundryId, this.existing});

  final String laundryId;
  final LaundryService? existing;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _hours;
  late final TextEditingController _minQty;
  late final TextEditingController _express;
  late PricingUnit _unit;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.nameAr ?? '');
    _price = TextEditingController(text: e?.basePrice.toStringAsFixed(2) ?? '');
    _hours = TextEditingController(text: '${e?.turnaroundHours ?? 24}');
    _minQty = TextEditingController(
        text: (e?.minQuantity ?? 0).toStringAsFixed(0));
    _express = TextEditingController(
        text: (e?.expressMultiplier ?? 1.0).toStringAsFixed(2));
    _unit = e?.unit ?? PricingUnit.piece;
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _hours.dispose();
    _minQty.dispose();
    _express.dispose();
    super.dispose();
  }

  String? _positive(String? v, {bool allowZero = true, double min = 0}) {
    if (v == null || v.trim().isEmpty) return 'مطلوب';
    final d = double.tryParse(v.trim());
    if (d == null) return 'أدخل رقمًا';
    if (d < min) return 'لا يقلّ عن $min';
    if (!allowZero && d == 0) return 'لا يكون صفرًا';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'خدمة جديدة' : 'تعديل الخدمة'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'اسم الخدمة', hintText: 'ثوب غسيل وكوي'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PricingUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'وحدة التسعير'),
                  items: [
                    for (final u in PricingUnit.values)
                      DropdownMenuItem(
                          value: u, child: Text('${u.labelAr} — ${u.promptAr}')),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? _unit),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'السعر (ر.س) لكل ${_unit.labelAr}',
                  ),
                  validator: (v) => _positive(v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مدّة التنفيذ (ساعة)',
                    helperText: 'تغذّي وعد الجاهزية ومحرّك المواعيد',
                  ),
                  validator: (v) => _positive(v, allowZero: false, min: 1),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minQty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحدّ الأدنى للكمّية',
                    helperText: 'صفر = بلا حدّ',
                  ),
                  validator: (v) => _positive(v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _express,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مضاعِف الاستعجال',
                    helperText: '1.0 = لا تقبل الاستعجال',
                  ),
                  validator: (v) => _positive(v, min: 1),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('مفعّلة'),
                  subtitle: const Text('الموقوفة لا تُعرض على العملاء'),
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
            final base = widget.existing;
            final built = LaundryService(
              id: base?.id ?? '',
              laundryId: widget.laundryId,
              categoryId: base?.categoryId,
              nameAr: _name.text.trim(),
              unit: _unit,
              basePrice: double.parse(_price.text.trim()),
              turnaroundHours: int.parse(_hours.text.trim()),
              minQuantity: double.parse(_minQty.text.trim()),
              expressMultiplier: double.parse(_express.text.trim()),
              isActive: _active,
              sortOrder: base?.sortOrder ?? 0,
            );
            Navigator.pop(context, built);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
