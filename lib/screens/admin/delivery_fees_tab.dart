import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/delivery_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// رسوم التوصيل.
///
/// **ما يميّز هذه الشاشة**: فيها معاينةٌ حيّة. من يضبط شرائح المسافة يرى أثر
/// ضبطه على مسافةٍ ومبلغٍ يختارهما — قبل أن يكتشفه عميل. والمعاينة تنادي
/// `quote_delivery_fee` نفسها التي ينادينها تطبيق العميل، فلا فرق بين ما يُرى
/// هنا وما يُحصَّل هناك.
class DeliveryFeesTab extends StatefulWidget {
  const DeliveryFeesTab({super.key});

  @override
  State<DeliveryFeesTab> createState() => _DeliveryFeesTabState();
}

class _DeliveryFeesTabState extends State<DeliveryFeesTab> {
  final _delivery = const DeliveryService();
  late Future<(DeliverySettings?, List<DistanceTier>)> _future;
  String? _branchId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranchId;
    if (id != _branchId) {
      _branchId = id;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      final id = _branchId;
      _future = id == null
          ? Future.value((null, const <DistanceTier>[]))
          : Future.wait([_delivery.settings(id), _delivery.tiers(id)])
              .then((r) => (r[0] as DeliverySettings?, r[1] as List<DistanceTier>));
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

  Future<void> _save(DeliverySettings s) async {
    try {
      await _delivery.save(s);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;

    return AsyncView<(DeliverySettings?, List<DistanceTier>)>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final (settings, tiers) = data;
        final branchId = _branchId;
        if (branchId == null) {
          return const Center(child: Text('اختر فرعًا'));
        }

        final current = settings ??
            DeliverySettings(
                branchId: branchId, strategy: DeliveryStrategy.flat);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('رسوم التوصيل',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'الاستراتيجية والرسوم تُعدَّل من هنا — بلا تعديل تطبيق.'
                  : 'العرض فقط: التعديل لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (settings == null) ...[
              const SizedBox(height: 12),
              const _Warning(
                text: 'لا إعدادات توصيل لهذا الفرع بعد — والعميل لن يستطيع '
                    'الطلب حتى تُحفظ. اضبطها واحفظ.',
              ),
            ],
            const SizedBox(height: 20),

            _StrategyCard(
              settings: current,
              canEdit: canEdit,
              onSave: _save,
            ),
            const SizedBox(height: 20),

            if (current.strategy == DeliveryStrategy.distance)
              _TiersCard(
                branchId: branchId,
                tiers: tiers,
                canEdit: canEdit,
                delivery: _delivery,
                onChanged: _reload,
                onError: _showError,
              ),

            const SizedBox(height: 20),
            _QuotePreview(branchId: branchId, delivery: _delivery),
          ],
        );
      },
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: scheme.onTertiaryContainer))),
        ],
      ),
    );
  }
}

class _StrategyCard extends StatefulWidget {
  const _StrategyCard({
    required this.settings,
    required this.canEdit,
    required this.onSave,
  });

  final DeliverySettings settings;
  final bool canEdit;
  final Future<void> Function(DeliverySettings) onSave;

  @override
  State<_StrategyCard> createState() => _StrategyCardState();
}

class _StrategyCardState extends State<_StrategyCard> {
  late DeliveryStrategy _strategy;
  late TextEditingController _pickup;
  late TextEditingController _deliveryFee;
  late TextEditingController _combined;
  late TextEditingController _freeAbove;
  late TextEditingController _radius;
  late TextEditingController _minOrder;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _strategy = s.strategy;
    _pickup = TextEditingController(text: s.flatPickupFee.toStringAsFixed(2));
    _deliveryFee =
        TextEditingController(text: s.flatDeliveryFee.toStringAsFixed(2));
    _combined =
        TextEditingController(text: s.combinedFee?.toStringAsFixed(2) ?? '');
    _freeAbove = TextEditingController(
        text: s.freeAboveSubtotal?.toStringAsFixed(2) ?? '');
    _radius = TextEditingController(text: s.maxRadiusKm.toStringAsFixed(1));
    _minOrder =
        TextEditingController(text: s.minOrderSubtotal.toStringAsFixed(2));
  }

  @override
  void dispose() {
    for (final c in [_pickup, _deliveryFee, _combined, _freeAbove, _radius,
                     _minOrder]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _optional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  double _required(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.canEdit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الاستراتيجية',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<DeliveryStrategy>(
              segments: [
                for (final s in DeliveryStrategy.values)
                  ButtonSegment(value: s, label: Text(s.labelAr)),
              ],
              selected: {_strategy},
              onSelectionChanged:
                  enabled ? (v) => setState(() => _strategy = v.first) : null,
            ),
            const SizedBox(height: 20),

            if (_strategy == DeliveryStrategy.flat) ...[
              _Row(children: [
                _Field(label: 'رسم الاستلام', controller: _pickup, enabled: enabled),
                _Field(label: 'رسم التسليم', controller: _deliveryFee, enabled: enabled),
              ]),
              const SizedBox(height: 12),
            ],

            _Row(children: [
              _Field(
                label: 'رسم الرحلتين معًا',
                controller: _combined,
                enabled: enabled,
                helper: 'اتركه فارغًا ليُجمع الرسمان',
              ),
              _Field(
                label: 'توصيل مجاني فوق',
                controller: _freeAbove,
                enabled: enabled,
                helper: 'اتركه فارغًا لإلغاء الإعفاء',
              ),
            ]),
            const SizedBox(height: 12),
            _Row(children: [
              _Field(label: 'أقصى مسافة (كم)', controller: _radius, enabled: enabled),
              _Field(
                label: 'أقلّ قيمة طلب',
                controller: _minOrder,
                enabled: enabled,
              ),
            ]),

            if (enabled) ...[
              const SizedBox(height: 20),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: () => widget.onSave(DeliverySettings(
                    branchId: widget.settings.branchId,
                    strategy: _strategy,
                    flatPickupFee: _required(_pickup),
                    flatDeliveryFee: _required(_deliveryFee),
                    combinedFee: _optional(_combined),
                    freeAboveSubtotal: _optional(_freeAbove),
                    maxRadiusKm: _required(_radius),
                    minOrderSubtotal: _required(_minOrder),
                  )),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (!wide) {
      return Column(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? helper;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, helperText: helper),
      );
}

class _TiersCard extends StatelessWidget {
  const _TiersCard({
    required this.branchId,
    required this.tiers,
    required this.canEdit,
    required this.delivery,
    required this.onChanged,
    required this.onError,
  });

  final String branchId;
  final List<DistanceTier> tiers;
  final bool canEdit;
  final DeliveryService delivery;
  final VoidCallback onChanged;
  final void Function(Object) onError;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('شرائح المسافة',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (canEdit)
                  TextButton.icon(
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('شريحة'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الحدّ الأدنى شامل والأعلى غير شامل، والقاعدة ترفض التداخل. '
              'ومسافةٌ لا تغطّيها شريحةٌ تُعلَن غير قابلة للخدمة — لا مجّانية.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (tiers.isEmpty)
              const Text('لا شرائح بعد.')
            else
              for (final t in tiers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.straighten, size: 20),
                  title: Text('من ${t.fromKm.toStringAsFixed(1)} '
                      'إلى ${t.toKm.toStringAsFixed(1)} كم'),
                  subtitle: Text('استلام ${t.pickupFee.toStringAsFixed(2)} '
                      '• تسليم ${t.deliveryFee.toStringAsFixed(2)} ر.س'),
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            try {
                              await delivery.removeTier(t.id);
                              onChanged();
                            } catch (e) {
                              onError(e);
                            }
                          },
                        )
                      : null,
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final from = TextEditingController();
    final to = TextEditingController();
    final pickup = TextEditingController();
    final drop = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('شريحة مسافة'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: from, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'من (كم)')),
              TextField(controller: to, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'إلى (كم)')),
              TextField(controller: pickup, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'رسم الاستلام')),
              TextField(controller: drop, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'رسم التسليم')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إضافة')),
        ],
      ),
    );

    if (ok != true) return;
    try {
      await delivery.addTier(
        branchId: branchId,
        fromKm: double.tryParse(from.text.trim()) ?? 0,
        toKm: double.tryParse(to.text.trim()) ?? 0,
        pickupFee: double.tryParse(pickup.text.trim()) ?? 0,
        deliveryFee: double.tryParse(drop.text.trim()) ?? 0,
      );
      onChanged();
    } catch (e) {
      onError(e);
    }
  }
}

/// معاينة الرسم — نفس الدالّة التي ينادينها تطبيق العميل.
class _QuotePreview extends StatefulWidget {
  const _QuotePreview({required this.branchId, required this.delivery});

  final String branchId;
  final DeliveryService delivery;

  @override
  State<_QuotePreview> createState() => _QuotePreviewState();
}

class _QuotePreviewState extends State<_QuotePreview> {
  // المسجد النبويّ مركزًا افتراضيًّا: أوضح نقطةٍ يعرفها من يضبط فرعًا في المدينة.
  final _lat = TextEditingController(text: '24.4672');
  final _lng = TextEditingController(text: '39.6142');
  final _subtotal = TextEditingController(text: '80');
  DeliveryQuote? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _subtotal.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() { _busy = true; _error = null; });
    try {
      final q = await widget.delivery.quote(
        branchId: widget.branchId,
        lat: double.tryParse(_lat.text.trim()) ?? 0,
        lng: double.tryParse(_lng.text.trim()) ?? 0,
        subtotal: double.tryParse(_subtotal.text.trim()) ?? 0,
      );
      if (mounted) setState(() => _result = q);
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('معاينة الرسم',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('جرّب إعداداتك قبل أن يجرّبها عميل.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            _Row(children: [
              _Field(label: 'خط العرض', controller: _lat, enabled: true),
              _Field(label: 'خط الطول', controller: _lng, enabled: true),
              _Field(label: 'قيمة الطلب', controller: _subtotal, enabled: true),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('احسب'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _result!.serviceable
                      ? scheme.primaryContainer
                      : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _result!.serviceable
                          ? '${_result!.fee.toStringAsFixed(2)} ر.س'
                          : 'غير قابل للخدمة',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    // السبب يُعرض دائمًا: الرقم بلا سببه يُترك، وشكواه تصل الدعم.
                    if (_result!.reason != null) Text(_result!.reason!),
                    if (_result!.distanceKm != null)
                      Text('المسافة: ${_result!.distanceKm!.toStringAsFixed(2)} كم',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
