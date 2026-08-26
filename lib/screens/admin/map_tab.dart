import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/delivery_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/wasl_map.dart';

/// خريطةُ التشغيل: أين السائقون، وأين حدودُ الخدمة.
///
/// **شاشةٌ واحدةٌ لهما معًا لا شاشتان**: سؤالُ المشغّل ليس «أين سائقي؟» ولا
/// «ما حدودي؟» بل «هل يغطّي من عندي ما رسمتُه؟» — وهو سؤالٌ لا يُجاب على
/// خريطتين متجاورتين.
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _delivery = const DeliveryService();
  final _controller = MapController();

  late Future<(List<DriverPin>, List<DeliveryZone>)> _future;
  String? _branchId;
  Timer? _refresh;

  /// نقاطُ منطقةٍ قيد الرسم. فارغةٌ = لا رسم جارٍ.
  final List<LatLng> _drawing = [];
  bool _drawMode = false;
  bool _showZones = true;
  String? _editingZoneId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranchId;
    if (id != _branchId) {
      _branchId = id;
      _reload();
    }
  }

  @override
  void initState() {
    super.initState();
    // مواقع السائقين تتغيّر بلا تفاعلٍ من الناظر: خريطةٌ لا تُحدَّث إلا بالضغط
    // تُعرض قديمةً ويُظنّ أن السائق واقف.
    _refresh = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && !_drawMode) _reload();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      final id = _branchId;
      _future = id == null
          ? Future.value((<DriverPin>[], <DeliveryZone>[]))
          : () async {
              final pins = await _delivery.driverPins(id);
              final zones = await _delivery.zones(id);
              return (pins, zones);
            }();
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _canEdit => context
      .read<SessionService>()
      .hasRoleInActiveBranch({AppRole.branchManager});

  void _startDrawing({DeliveryZone? from}) {
    setState(() {
      _drawMode = true;
      _editingZoneId = from?.id;
      _drawing
        ..clear()
        ..addAll([
          if (from != null)
            for (final (lat, lng) in from.ring) LatLng(lat, lng),
        ]);
      // الحلقة تصل مغلقةً من القاعدة، والنقطة المكرّرة في الرسم تربك السحب.
      if (_drawing.length > 1 && _drawing.first == _drawing.last) {
        _drawing.removeLast();
      }
    });
  }

  void _cancelDrawing() {
    setState(() {
      _drawMode = false;
      _editingZoneId = null;
      _drawing.clear();
    });
  }

  Future<void> _saveDrawing(List<DeliveryZone> zones) async {
    if (_drawing.length < 3) {
      _say('المنطقة تحتاج ثلاث نقاطٍ على الأقل.');
      return;
    }
    final existing = _editingZoneId == null
        ? null
        : zones.cast<DeliveryZone?>().firstWhere(
            (z) => z?.id == _editingZoneId,
            orElse: () => null);

    final result = await showDialog<_ZoneForm>(
      context: context,
      builder: (_) => _ZoneDialog(existing: existing),
    );
    if (result == null) return;

    final branchId = _branchId;
    if (branchId == null) return;

    try {
      await _delivery.saveZone(
        id: _editingZoneId,
        branchId: branchId,
        nameAr: result.name,
        ring: [for (final p in _drawing) (p.latitude, p.longitude)],
        pickupFee: result.pickupFee,
        deliveryFee: result.deliveryFee,
        combinedFee: result.combinedFee,
        priority: result.priority,
        isActive: result.active,
      );
      _cancelDrawing();
      _reload();
      _say('حُفظت المنطقة.');
    } catch (e) {
      _say(humanizeDbError(e));
    }
  }

  Future<void> _deleteZone(DeliveryZone zone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف «${zone.nameAr}»؟'),
        content: const Text(
            'الطلبات القديمة تحتفظ برسومها المجمَّدة — والحذف يمسّ ما يأتي فقط.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _delivery.deleteZone(zone.id);
      _reload();
    } catch (e) {
      _say(humanizeDbError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final branch = context.watch<SessionService>().activeBranch;
    final canEdit = _canEdit;

    return AsyncView<(List<DriverPin>, List<DeliveryZone>)>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final (pins, zones) = data;
        final center = branch?.lat != null && branch?.lng != null
            ? LatLng(branch!.lat!, branch.lng!)
            : kMedina;

        return Column(
          children: [
            _Toolbar(
              drawMode: _drawMode,
              canEdit: canEdit,
              showZones: _showZones,
              pointCount: _drawing.length,
              onToggleZones: () => setState(() => _showZones = !_showZones),
              onStartDraw: () => _startDrawing(),
              onUndo: _drawing.isEmpty
                  ? null
                  : () => setState(() => _drawing.removeLast()),
              onCancel: _cancelDrawing,
              onSave: () => _saveDrawing(zones),
              onRefresh: _reload,
            ),
            Expanded(
              child: Stack(
                children: [
                  WaslMap(
                    controller: _controller,
                    initialCenter: center,
                    initialZoom: 12,
                    onTap: _drawMode
                        ? (p) => setState(() => _drawing.add(p))
                        : null,
                    children: [
                      if (_showZones)
                        PolygonLayer(
                          polygons: [
                            for (final z in zones)
                              if (z.ring.length >= 3 && z.id != _editingZoneId)
                                Polygon(
                                  points: [
                                    for (final (lat, lng) in z.ring)
                                      LatLng(lat, lng)
                                  ],
                                  color: (z.isActive
                                          ? scheme.primary
                                          : scheme.outline)
                                      .withValues(alpha: 0.15),
                                  borderColor: z.isActive
                                      ? scheme.primary
                                      : scheme.outline,
                                  borderStrokeWidth: 2,
                                ),
                          ],
                        ),

                      // المنطقة قيد الرسم فوق الجميع، وبلونٍ مختلف.
                      if (_drawing.length >= 2)
                        PolygonLayer(polygons: [
                          Polygon(
                            points: _drawing,
                            color: scheme.tertiary.withValues(alpha: 0.25),
                            borderColor: scheme.tertiary,
                            borderStrokeWidth: 3,
                          ),
                        ]),
                      if (_drawing.isNotEmpty)
                        MarkerLayer(markers: [
                          for (var i = 0; i < _drawing.length; i++)
                            Marker(
                              point: _drawing[i],
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: scheme.tertiary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                        ]),

                      MarkerLayer(markers: [
                        if (branch?.lat != null && branch?.lng != null)
                          waslMarker(
                            at: LatLng(branch!.lat!, branch.lng!),
                            icon: Icons.storefront,
                            color: scheme.secondary,
                            label: branch.nameAr,
                          ),
                        for (final p in pins)
                          waslMarker(
                            at: LatLng(p.lat, p.lng),
                            icon: Icons.local_shipping,
                            color: p.isStale || !p.isOnline
                                ? scheme.outline
                                : scheme.primary,
                            label: '${p.name ?? 'سائق'} • ${p.ageLabel}',
                          ),
                      ]),
                    ],
                  ),
                  if (_drawMode)
                    PositionedDirectional(
                      top: 8,
                      start: 8,
                      end: 8,
                      child: _Hint(
                        text: _drawing.isEmpty
                            ? 'انقر على الخريطة لوضع أوّل نقطة.'
                            : 'انقر لإضافة نقطة. ثلاثٌ على الأقل، والحلقة تُغلق تلقائيًّا.',
                      ),
                    ),
                ],
              ),
            ),
            _Legend(pins: pins, zones: zones, canEdit: canEdit,
                onEdit: (z) => _startDrawing(from: z), onDelete: _deleteZone),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.drawMode,
    required this.canEdit,
    required this.showZones,
    required this.pointCount,
    required this.onToggleZones,
    required this.onStartDraw,
    required this.onUndo,
    required this.onCancel,
    required this.onSave,
    required this.onRefresh,
  });

  final bool drawMode;
  final bool canEdit;
  final bool showZones;
  final int pointCount;
  final VoidCallback onToggleZones;
  final VoidCallback onStartDraw;
  final VoidCallback? onUndo;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('خريطة التشغيل',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (!drawMode) ...[
            FilterChip(
              label: const Text('المناطق'),
              selected: showZones,
              onSelected: (_) => onToggleZones(),
            ),
            if (canEdit)
              ActionChip(
                avatar: const Icon(Icons.draw_outlined, size: 16),
                label: const Text('ارسم منطقة'),
                onPressed: onStartDraw,
              ),
            ActionChip(
              avatar: const Icon(Icons.refresh, size: 16),
              label: const Text('تحديث'),
              onPressed: onRefresh,
            ),
          ] else ...[
            Chip(label: Text('$pointCount نقطة')),
            ActionChip(
              avatar: const Icon(Icons.undo, size: 16),
              label: const Text('تراجع'),
              onPressed: onUndo,
            ),
            ActionChip(
              avatar: const Icon(Icons.close, size: 16),
              label: const Text('إلغاء'),
              onPressed: onCancel,
            ),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('حفظ المنطقة'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// أسفل الخريطة: السائقون والمناطق مقروءةً بالنصّ لا بالدبابيس وحدها.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.pins,
    required this.zones,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DriverPin> pins;
  final List<DeliveryZone> zones;
  final bool canEdit;
  final void Function(DeliveryZone) onEdit;
  final void Function(DeliveryZone) onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 132,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: [
          if (pins.isEmpty)
            Text('لا سائق يُرسل موقعه الآن.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in pins)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      p.isStale || !p.isOnline
                          ? Icons.cloud_off
                          : Icons.local_shipping,
                      size: 16,
                      color: p.isStale || !p.isOnline ? scheme.outline : null,
                    ),
                    label: Text(
                      '${p.name ?? 'سائق'} • ${p.ageLabel}'
                      '${p.activeJobs > 0 ? ' • ${p.activeJobs} مهمّة' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          for (final z in zones)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: Icon(Icons.layers_outlined,
                  color: z.isActive ? scheme.primary : scheme.outline),
              title: Text(
                '${z.nameAr} — ${z.areaKm2.toStringAsFixed(1)} كم²'
                '${z.isActive ? '' : ' (موقوفة)'}',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                'استلام ${z.pickupFee.toStringAsFixed(0)} • '
                'تسليم ${z.deliveryFee.toStringAsFixed(0)} • '
                'أولوية ${z.priority}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: !canEdit
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'تعديل الحدود',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => onEdit(z),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => onDelete(z),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

typedef _ZoneForm = ({
  String name,
  double pickupFee,
  double deliveryFee,
  double? combinedFee,
  int priority,
  bool active,
});

class _ZoneDialog extends StatefulWidget {
  const _ZoneDialog({this.existing});
  final DeliveryZone? existing;

  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  late final _name = TextEditingController(text: widget.existing?.nameAr ?? '');
  late final _pickup = TextEditingController(
      text: (widget.existing?.pickupFee ?? 0).toStringAsFixed(2));
  late final _delivery = TextEditingController(
      text: (widget.existing?.deliveryFee ?? 0).toStringAsFixed(2));
  late final _combined = TextEditingController(
      text: widget.existing?.combinedFee?.toStringAsFixed(2) ?? '');
  late final _priority =
      TextEditingController(text: '${widget.existing?.priority ?? 0}');
  late bool _active = widget.existing?.isActive ?? true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _pickup, _delivery, _combined, _priority]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسمًا يُعرف به الحيّ');
      return;
    }
    Navigator.of(context).pop((
      name: name,
      pickupFee: double.tryParse(_pickup.text.trim()) ?? 0,
      deliveryFee: double.tryParse(_delivery.text.trim()) ?? 0,
      combinedFee: double.tryParse(_combined.text.trim()),
      priority: int.tryParse(_priority.text.trim()) ?? 0,
      active: _active,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'منطقة جديدة' : 'تعديل المنطقة'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم المنطقة',
                  hintText: 'قباء، العوالي، وسط المدينة…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pickup,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رسم الاستلام',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _delivery,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رسم التسليم',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _combined,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'رسم مجمَّع (اختياريّ)',
                        helperText: 'يحلّ محلّ الاثنين معًا',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _priority,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الأولوية',
                        helperText: 'الأعلى يفوز عند التداخل',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('مفعَّلة'),
              ),
              if (_error != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
