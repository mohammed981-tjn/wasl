import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/complaints_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/countdown.dart';
import '../customer/my_complaints_screen.dart' show ComplaintChat;
import 'complaint_settings_screen.dart';

/// لوحةُ خدمة العملاء.
///
/// **الطابورُ يُرتَّب في القاعدة لا هنا.** ترتيبٌ في الجهاز يحتاج الصفوف
/// كلَّها، وهو ما يفعله كثيرٌ من اللوحات: تُبَثّ كلُّ شكوى إلى كلِّ جهاز ثم
/// تُرتَّب في الذاكرة. وذلك يعمل عند مئةٍ ويسقط عند عشرة آلاف — ويُسرّب مع
/// كلّ صفٍّ اسمَ عميلٍ وهاتفَه إلى جهازٍ قد يُسرق.
class ComplaintsTab extends StatefulWidget {
  const ComplaintsTab({super.key, required this.laundryId, this.branchId});

  final String laundryId;
  final String? branchId;

  @override
  State<ComplaintsTab> createState() => _ComplaintsTabState();
}

class _ComplaintsTabState extends State<ComplaintsTab> {
  final _service = const ComplaintsService();
  ComplaintStatus? _filter;

  late Future<_Board> _load = _fetch();

  Future<_Board> _fetch() async {
    final results = await Future.wait([
      _service.queue(branchId: widget.branchId, status: _filter),
      _service.summary(laundryId: widget.laundryId),
      _service.unnotifiedCount(widget.laundryId),
    ]);
    return _Board(
      queue: results[0] as List<Complaint>,
      summary: results[1] as ComplaintSummary,
      unnotified: results[2] as int,
    );
  }

  void _reload() => setState(() => _load = _fetch());

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<_Board>(
        future: _load,
        onRetry: _reload,
        builder: (context, board) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SettingsRow(laundryId: widget.laundryId, onReturn: _reload),
            const SizedBox(height: 8),
            _SummaryCard(summary: board.summary),
            if (board.unnotified > 0) ...[
              const SizedBox(height: 10),
              _UnnotifiedBanner(count: board.unnotified),
            ],
            const SizedBox(height: 12),
            _FilterBar(
              current: _filter,
              openCount: board.summary.openNow,
              onChanged: (s) {
                _filter = s;
                _reload();
              },
            ),
            const SizedBox(height: 12),
            if (board.queue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('لا شكاوى مطابقة.')),
              )
            else
              for (final c in board.queue) ...[
                _QueueCard(complaint: c, onChanged: _reload),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _Board {
  const _Board({
    required this.queue,
    required this.summary,
    required this.unnotified,
  });
  final List<Complaint> queue;
  final ComplaintSummary summary;

  /// حُلّت ولم يبلغ أصحابَها — لن تُغلق تلقائيًّا.
  final int unnotified;
}

/// **سطران يُقرآن معًا**: ما أُغلق بإقرار صاحبه، وما أُغلق بصمته.
///
/// وجمعُهما في «مغلقة: ٤٠» يجعل الصمتَ يبدو رضًا. وأكثرُ ما يُغلق بالصمت
/// مؤشّرُ خللٍ لا إنجاز.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final ComplaintSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('آخر ثلاثين يومًا',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(spacing: 20, runSpacing: 12, children: [
              _Stat(label: 'تنتظر عملًا', value: '${s.needsWork}'),
              _Stat(
                label: 'تجاوزت مهلة الردّ',
                value: '${s.slaBreached}',
                alert: s.slaBreached > 0,
              ),
              _Stat(
                label: 'أُغلقت بإقرار أصحابها',
                value: '${s.closedConfirmed}',
                good: true,
              ),
              _Stat(
                label: 'أُغلقت بالصمت',
                value: '${s.closedBySilence}',
                alert: s.closedBySilence > s.closedConfirmed,
              ),
              _Stat(
                label: 'ارتدّت',
                value: '${s.reopened}',
                alert: s.reopened > 0,
              ),
              if (s.medianResponseHours != null)
                _Stat(
                  label: 'وسيطُ زمن الردّ',
                  value: '${s.medianResponseHours!.toStringAsFixed(1)} س',
                ),
            ]),
            if (s.byType.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('وأكثرُها تكرارًا',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              // **القائمةُ المغلقة تُجمَّع، والنصُّ الحرُّ لا يُجمَّع.** وهذا
              // السطرُ هو ثمرةُ ذلك القرار: يقول أيُّ عطبٍ يتكرّر.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final e in (s.byType.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .take(5))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${e.key} · ${e.value}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.alert = false,
    this.good = false,
  });

  final String label;
  final String value;
  final bool alert;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = alert
        ? Colors.red
        : good
            ? Colors.green.shade700
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.current,
    required this.openCount,
    required this.onChanged,
  });

  final ComplaintStatus? current;
  final int openCount;
  final ValueChanged<ComplaintStatus?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text('الكلّ${openCount > 0 ? ' ($openCount جديدة)' : ''}'),
            selected: current == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final s in ComplaintStatus.values)
            ChoiceChip(
              label: Text(s.label),
              selected: current == s,
              onSelected: (_) => onChanged(s),
            ),
        ],
      );
}

class _QueueCard extends StatefulWidget {
  const _QueueCard({required this.complaint, required this.onChanged});
  final Complaint complaint;
  final VoidCallback onChanged;

  @override
  State<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<_QueueCard> {
  final _service = const ComplaintsService();
  bool _busy = false;
  bool _open = false;

  Future<void> _claim() async {
    setState(() => _busy = true);
    try {
      await _service.claim(widget.complaint.id);
      widget.onChanged();
    } catch (e) {
      _toast(humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    final decision = await showModalBottomSheet<_Decision>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ResolveSheet(complaint: widget.complaint),
    );
    // إغلاقُ الورقة من خارجها = تراجُع لا «حلٌّ بلا إجراء».
    if (decision == null) return;

    setState(() => _busy = true);
    try {
      final result = await _service.resolve(
        complaintId: widget.complaint.id,
        resolution: decision.resolution,
        refundPercent: decision.refundPercent,
        loyaltyPoints: decision.loyaltyPoints,
        warnAgainst: decision.warn,
        internalNote: decision.internalNote,
      );
      if (!mounted) return;
      _toast(result.actions.isEmpty
          ? 'سُجِّل الحلّ — وبقي أن يؤكّده صاحبُ الشكوى'
          : '${result.actions.join(' + ')} — وبقي تأكيدُ صاحب الشكوى');
      widget.onChanged();
    } catch (e) {
      _toast(humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final fmt = DateFormat('d MMM • h:mm a', 'ar');

    return Card(
      // **المرتدَّةُ تُميَّز بحافّة**: قال صاحبُها «لم تُحل» مرّةً، فحلٌّ ثانٍ
      // من الجنس نفسه سيرتدّ ثانية.
      shape: c.wasReopened
          ? RoundedRectangleBorder(
              side: BorderSide(color: Colors.orange.shade700, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${c.typeLabel} ${c.displayNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              if (c.slaBreached)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('تجاوزت المهلة',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.bold)),
                ),
              Text(c.status.label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                c.submittedByName ?? 'مجهول',
                if (c.orderNumber != null) 'طلب #${c.orderNumber}',
                fmt.format(c.createdAt),
              ].join(' • '),
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            if (c.againstName != null) ...[
              const SizedBox(height: 2),
              Text('على: ${c.againstName}',
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ],

            if (c.wasReopened) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.replay, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ارتدّت ${c.reopenCount} — الحلُّ السابق لم يقنع صاحبَها',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
            ],

            const SizedBox(height: 10),
            Text(c.description,
                maxLines: _open ? null : 3,
                overflow: _open ? null : TextOverflow.ellipsis),

            if (c.status == ComplaintStatus.resolved &&
                c.autoCloseAt != null) ...[
              const SizedBox(height: 8),
              Countdown(
                deadline: c.autoCloseAt,
                builder: (context, left, expired) => Text(
                  expired
                      ? 'انقضت مهلةُ التأكيد — تُغلق في الكنسة القادمة'
                      : 'بانتظار تأكيد صاحبها — ${formatRemaining(left!)}',
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black45),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Row(children: [
              if (c.status == ComplaintStatus.open)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _claim,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('التقاطها'),
                ),
              if (c.status.needsStaff) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _resolve,
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('قرارُ الحلّ'),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ),
            ]),

            if (_open) ...[
              if (c.internalNote != null && c.internalNote!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('ملاحظةٌ داخليّة: ${c.internalNote}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
              const SizedBox(height: 6),
              ComplaintChat(
                complaintId: c.id,
                role: 'customer_service',
                allowInternal: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Decision {
  const _Decision({
    required this.resolution,
    this.refundPercent,
    this.loyaltyPoints,
    this.warn = false,
    this.internalNote,
  });

  final String resolution;
  final double? refundPercent;
  final int? loyaltyPoints;
  final bool warn;
  final String? internalNote;
}

/// ورقةُ قرار الحلّ.
///
/// **تُدخَل نسبةٌ لا مبلغ.** المبلغُ يُقرأ من الطلب في القاعدة ويُسقَّف بما
/// تبقّى من المقبوض؛ ومبلغٌ يُكتب هنا مبلغٌ يُملى على القاعدة، وأوّلُ خطأٍ
/// فيه مالٌ يخرج ولا يعود.
class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet({required this.complaint});
  final Complaint complaint;

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  final _resolution = TextEditingController();
  final _internal = TextEditingController();
  final _points = TextEditingController();

  double _refund = 0;
  bool _warn = false;

  @override
  void dispose() {
    _resolution.dispose();
    _internal.dispose();
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWarn = widget.complaint.againstRole == 'driver' &&
        widget.complaint.againstId != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('قرارُ الحلّ — ${widget.complaint.displayNumber}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'وما تكتبه هنا يقرؤه صاحبُ الشكوى، ثم يُسأل: هل حُلّت فعلًا؟',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),

            const SizedBox(height: 14),
            TextField(
              controller: _resolution,
              maxLines: 3,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'الردُّ على الشاكي',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            Text('استرداد: ${_refund.round()}%',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text(
              // **رسمُ التوصيل خدمةٌ أُدّيت.** يُقال هنا صراحةً كي لا يُفاجأ
              // من رأى المبلغ أصغرَ ممّا حسب.
              'النسبةُ من قيمة الخدمة (بلا رسم التوصيل). والمئةُ وحدها تشمل '
              'الإجماليّ — والمبلغ يُقرأ من الطلب لا مِن هنا.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Slider(
              value: _refund,
              max: 100,
              divisions: 20,
              label: '${_refund.round()}%',
              onChanged: (v) => setState(() => _refund = v),
            ),

            const SizedBox(height: 8),
            TextField(
              controller: _points,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'تعويضٌ بالنقاط (اختياريّ)',
                helperText: 'بابُ التعويض حين لا يكون ثمّ ما يُستردّ — '
                    'كطلبٍ دُفع نقدًا.',
                border: OutlineInputBorder(),
              ),
            ),

            if (canWarn) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _warn,
                onChanged: (v) => setState(() => _warn = v ?? false),
                title: const Text('تسجيلُ إنذارٍ على السائق'),
                subtitle: const Text(
                  'يُسجَّل صفًّا يُراجَع ويسقط. وببلوغ الحدّ يُمنع من قبول '
                  'جديد — ولا تُقطع جولتُه الجارية.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],

            const SizedBox(height: 8),
            TextField(
              controller: _internal,
              maxLines: 2,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'ملاحظةٌ داخليّة (لا يراها الشاكي)',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تراجُع'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _Decision(
                      resolution: _resolution.text,
                      refundPercent: _refund > 0 ? _refund : null,
                      loyaltyPoints: int.tryParse(_points.text.trim()),
                      warn: _warn,
                      internalNote: _internal.text,
                    ),
                  ),
                  child: const Text('تنفيذُ القرار'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'كلُّ ما فوق يقع في معاملةٍ واحدة: استردادٌ وتعويضٌ وإنذارٌ '
              'وختم — أو لا شيء.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}


/// **شكاوى حُلّت ولم يبلغ أصحابَها.**
///
/// لن تُغلق تلقائيًّا: الكنسُ يشترط أن يكون صاحبُها قد سُئل، وإلّا كان
/// الإغلاقُ بالصمت إغلاقًا بالجهل. فتبقى في الطابور — **والسببُ يُعرض هنا
/// بدل أن يُكتشف بعد شهرٍ من التساؤل عن صفوفٍ لا تتحرّك.**
class _UnnotifiedBanner extends StatelessWidget {
  const _UnnotifiedBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.notifications_off_outlined, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? 'شكوى حُلّت ولم يبلغ صاحبَها ردُّها'
                      : '$count شكاوى حُلّت ولم يبلغ أصحابَها ردُّها',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  'لن تُغلق تلقائيًّا — لا يُغلق ملفٌّ على من لم يُسأل. '
                  'راجع قوالبَ رسائل الشكاوى.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ]),
      );
}


/// **بابُ الضبط في الطابور لا في قائمةٍ بعيدة.** من يقرأ «ثلاثُ شكاوى
/// تجاوزت مهلة الردّ» هو من يريد تعديلَ تلك المهلة — أو تعديلَ رسالةٍ لم
/// تصل. وإبعادُ الزرّ عن الرقم يجعل الرقمَ ملاحظةً لا فعلًا.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.laundryId, required this.onReturn});

  final String laundryId;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    // **خدمةُ العملاء تعالج ولا تُشرّع**: من يملك تمديد مهلة التأكيد يملك
    // إغلاق ما يشاء بالصمت. والقاعدةُ تفرضه كذلك — وهذا يوافقها لا يحلّ محلّها.
    final canEdit =
        session.hasRoleInActiveBranch({AppRole.branchManager});

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: laundryId.isEmpty
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComplaintSettingsScreen(
                      laundryId: laundryId,
                      canEdit: canEdit,
                    ),
                  ),
                );
                onReturn();
              },
        icon: const Icon(Icons.tune, size: 18),
        label: Text(canEdit ? 'ضبطُ الشكاوى' : 'إعداداتُ الشكاوى (عرض)'),
      ),
    );
  }
}
