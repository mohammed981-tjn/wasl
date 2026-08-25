import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/delivery_service.dart';
import '../../services/marketing_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// ساعات العمل والطاقة الاستيعابية.
///
/// **هذه الشاشة هي مدخل محرّك المواعيد.** كل رقمٍ فيها يظهر أثره مباشرةً في
/// «أقرب موعد متاح» الذي يراه العميل — ولذلك تحتها معاينةٌ تعرض فتحات الغد
/// بالفعل: من يضبط طاقةً أو مهلةً يجب أن يرى أثرها قبل أن يراه عميل.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  final _schedule = const ScheduleService();
  late Future<(List<BranchHours>, BookingSettings)> _future;
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
          ? Future.value((const <BranchHours>[], const BookingSettings(branchId: '')))
          : Future.wait([_schedule.hours(id), _schedule.bookingSettings(id)])
              .then((r) =>
                  (r[0] as List<BranchHours>, r[1] as BookingSettings));
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

  void _saved() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('حُفظ')));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final branch = context.watch<SessionService>().activeBranch;

    return AsyncView<(List<BranchHours>, BookingSettings)>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final (hours, booking) = data;
        final id = _branchId;
        if (id == null || branch == null) {
          return const Center(child: Text('اختر فرعًا'));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('المواعيد والطاقة',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'كل رقمٍ هنا يظهر أثره فورًا في المواعيد التي يراها العميل.'
                  : 'العرض فقط: التعديل لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _HoursCard(
              hours: hours,
              canEdit: canEdit,
              onSave: (h) async {
                try {
                  await _schedule.saveHours(id, h);
                  _saved();
                } catch (e) {
                  _showError(e);
                }
              },
            ),
            const SizedBox(height: 20),
            _CapacityCard(
              branch: branch,
              booking: booking,
              canEdit: canEdit,
              onSave: (s, capacity) async {
                try {
                  await _schedule.saveBookingSettings(s);
                  await _schedule.updateCapacity(id, capacity);
                  _saved();
                } catch (e) {
                  _showError(e);
                }
              },
            ),
            const SizedBox(height: 20),
            _SlotsPreview(branchId: id),
          ],
        );
      },
    );
  }
}

class _HoursCard extends StatefulWidget {
  const _HoursCard({
    required this.hours,
    required this.canEdit,
    required this.onSave,
  });

  final List<BranchHours> hours;
  final bool canEdit;
  final Future<void> Function(List<BranchHours>) onSave;

  @override
  State<_HoursCard> createState() => _HoursCardState();
}

class _HoursCardState extends State<_HoursCard> {
  late List<BranchHours> _hours;

  @override
  void initState() {
    super.initState();
    _hours = List.of(widget.hours);
  }

  Future<void> _pick(int index, {required bool opening}) async {
    final current = opening ? _hours[index].opensAt : _hours[index].closesAt;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 8,
          minute: int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0),
    );
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _hours[index] = opening
          ? _hours[index].copyWith(opensAt: v)
          : _hours[index].copyWith(closesAt: v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ساعات العمل',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('اليوم المغلق لا فتحة فيه إطلاقًا.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (var i = 0; i < _hours.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 80,
                        child: Text(_hours[i].dayNameAr,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600))),
                    Switch(
                      value: !_hours[i].isClosed,
                      onChanged: widget.canEdit
                          ? (v) => setState(() =>
                              _hours[i] = _hours[i].copyWith(isClosed: !v))
                          : null,
                    ),
                    const SizedBox(width: 8),
                    if (_hours[i].isClosed)
                      Text('مغلق',
                          style: TextStyle(
                              color: Theme.of(context).hintColor))
                    else ...[
                      OutlinedButton(
                        onPressed: widget.canEdit
                            ? () => _pick(i, opening: true)
                            : null,
                        child: Text(_hours[i].opensAt,
                            textDirection: TextDirection.ltr),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('—'),
                      ),
                      OutlinedButton(
                        onPressed: widget.canEdit
                            ? () => _pick(i, opening: false)
                            : null,
                        child: Text(_hours[i].closesAt,
                            textDirection: TextDirection.ltr),
                      ),
                    ],
                  ],
                ),
              ),
            if (widget.canEdit) ...[
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: () => widget.onSave(_hours),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الساعات'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapacityCard extends StatefulWidget {
  const _CapacityCard({
    required this.branch,
    required this.booking,
    required this.canEdit,
    required this.onSave,
  });

  final Branch branch;
  final BookingSettings booking;
  final bool canEdit;
  final Future<void> Function(BookingSettings, int) onSave;

  @override
  State<_CapacityCard> createState() => _CapacityCardState();
}

class _CapacityCardState extends State<_CapacityCard> {
  late final TextEditingController _capacity;
  late final TextEditingController _slot;
  late final TextEditingController _lead;
  late final TextEditingController _horizon;
  late final TextEditingController _maxOrders;
  late final TextEditingController _maxPieces;
  late final TextEditingController _cutoff;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _capacity =
        TextEditingController(text: '${widget.branch.dailyCapacityPieces}');
    _slot = TextEditingController(text: '${b.slotMinutes}');
    _lead = TextEditingController(text: '${b.leadTimeMinutes}');
    _horizon = TextEditingController(text: '${b.horizonDays}');
    _maxOrders = TextEditingController(text: '${b.maxOrdersPerSlot}');
    _maxPieces = TextEditingController(text: '${b.maxPiecesPerSlot}');
    _cutoff = TextEditingController(text: '${b.cutoffBeforeCloseMinutes}');
  }

  @override
  void dispose() {
    for (final c in [_capacity, _slot, _lead, _horizon, _maxOrders,
                     _maxPieces, _cutoff]) {
      c.dispose();
    }
    super.dispose();
  }

  int _v(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    Widget field(String label, TextEditingController c, String helper) =>
        TextField(
          controller: c,
          enabled: widget.canEdit,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: label, helperText: helper),
        );

    final fields = [
      field('الطاقة اليومية (قطعة)', _capacity, 'صفر = بلا سقف'),
      field('طول الفتحة (دقيقة)', _slot, '٦٠ يعطي «٥–٦»'),
      field('مهلة أقرب موعد (دقيقة)', _lead, 'صفر يعني موعدًا بدأ للتوّ'),
      field('الأفق (يوم)', _horizon, 'إلى أي مدًى يرى العميل مواعيد'),
      field('سقف الفتحة (طلب)', _maxOrders, 'صفر = بلا سقف'),
      field('سقف الفتحة (قطعة)', _maxPieces, 'صفر = بلا سقف'),
      field('قبل الإغلاق (دقيقة)', _cutoff, 'سائقٌ يخرج قبل الإغلاق لا يعود'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الطاقة والحجز',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'الطاقة تُقاس بالقطع لا بالطلبات: طلبٌ فيه بطانيتان ليس كطلبٍ '
              'فيه ثلاثين قطعة. والكيلو يُحسب أربع قطع، والسلّة خمس عشرة.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (wide)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final f in fields) SizedBox(width: 240, child: f),
                ],
              )
            else
              for (final f in fields)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12), child: f),
            if (widget.canEdit) ...[
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: () => widget.onSave(
                    BookingSettings(
                      branchId: widget.branch.id,
                      slotMinutes: _v(_slot),
                      leadTimeMinutes: _v(_lead),
                      horizonDays: _v(_horizon),
                      maxOrdersPerSlot: _v(_maxOrders),
                      maxPiecesPerSlot: _v(_maxPieces),
                      cutoffBeforeCloseMinutes: _v(_cutoff),
                    ),
                    _v(_capacity),
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الإعدادات'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// معاينة الفتحات — أثر الإعدادات كما يراه العميل.
class _SlotsPreview extends StatefulWidget {
  const _SlotsPreview({required this.branchId});

  final String branchId;

  @override
  State<_SlotsPreview> createState() => _SlotsPreviewState();
}

class _SlotsPreviewState extends State<_SlotsPreview> {
  final _delivery = const DeliveryService();
  Future<List<BookingSlot>>? _future;

  void _load() {
    setState(() {
      _future = _delivery.slots(branchId: widget.branchId, days: 2);
    });
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
            Row(
              children: [
                const Text('معاينة المواعيد',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('اعرض اليومين القادمين'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('ما يراه العميل بالضبط — بالفتحات المغلقة وأسبابها.',
                style: Theme.of(context).textTheme.bodySmall),
            if (_future != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: AsyncView<List<BookingSlot>>(
                  future: _future!,
                  onRetry: _load,
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'لا فتحات — راجع ساعات العمل',
                  builder: (context, slots) => ListView.builder(
                    itemCount: slots.length,
                    itemBuilder: (_, i) {
                      final s = slots[i];
                      final t = '${s.start.hour.toString().padLeft(2, '0')}:00';
                      final day = BranchHours
                          .weekdayNames[s.start.weekday % 7];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          s.isAvailable
                              ? Icons.check_circle_outline
                              : Icons.block,
                          color: s.isAvailable ? scheme.primary : scheme.outline,
                          size: 18,
                        ),
                        title: Text('$day  $t',
                            style: TextStyle(
                                color: s.isAvailable
                                    ? null
                                    : Theme.of(context).hintColor)),
                        subtitle: s.blockedReason == null
                            ? Text('${s.ordersBooked} طلب محجوز',
                                style:
                                    Theme.of(context).textTheme.bodySmall)
                            : Text(s.blockedReason!,
                                style: TextStyle(
                                    fontSize: 12, color: scheme.outline)),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
