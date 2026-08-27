import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/models.dart';
import '../../services/complaints_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/countdown.dart';

/// «ملفّاتي» — شكاوى الشاكي وجوابُه عليها.
///
/// **وهذه الشاشة هي النظام كلُّه.** بلا سؤالِ «هل حُلّت فعلًا؟» يصير إغلاقُ
/// الشكوى قرارَ من اشتُكي إليه، ويصير المقياسُ عددَ ما ضُغط عليه زرُّ «تمّ».
/// وبه يصير المقياسُ كم شكوى **أقرّ أصحابُها** بحلّها — والرقمان يختلفان.
class MyComplaintsScreen extends StatefulWidget {
  const MyComplaintsScreen({super.key, this.role = 'customer'});

  final String role;

  @override
  State<MyComplaintsScreen> createState() => _MyComplaintsScreenState();
}

class _MyComplaintsScreenState extends State<MyComplaintsScreen> {
  final _service = const ComplaintsService();
  late Future<List<Complaint>> _load = _service.mine();

  void _reload() => setState(() => _load = _service.mine());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شكاويّ')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<Complaint>>(
          future: _load,
          onRetry: _reload,
          isEmpty: (list) => list.isEmpty,
          emptyMessage: 'لا شكاوى — ونرجو أن تبقى كذلك.',
          builder: (context, list) => ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => ComplaintCard(
              complaint: list[i],
              role: widget.role,
              onChanged: _reload,
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقةُ شكوى في شاشة صاحبها.
class ComplaintCard extends StatefulWidget {
  const ComplaintCard({
    super.key,
    required this.complaint,
    required this.role,
    required this.onChanged,
  });

  final Complaint complaint;
  final String role;
  final VoidCallback onChanged;

  @override
  State<ComplaintCard> createState() => _ComplaintCardState();
}

class _ComplaintCardState extends State<ComplaintCard> {
  final _service = const ComplaintsService();
  bool _busy = false;
  String? _error;
  bool _showChat = false;

  Future<void> _answer(bool solved) async {
    // **«لم تُحل» تُسأل عن سببها.** إعادةُ الشكوى بلا سببٍ تعيدها إلى موظّفٍ
    // لا يعرف ما الذي أخطأ فيه، فيكرّر الحلّ نفسه ويرتدّ ثانية.
    String? note;
    if (!solved) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => const _ReasonDialog(),
      );
      // إغلاقُ الحوار من خارجه = تراجُع، لا «لا سبب». والفرقُ أنّ الأوّل
      // يجب ألّا يرسل شيئًا.
      if (note == null) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.confirm(
        complaintId: widget.complaint.id,
        solved: solved,
        note: note,
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.complaint;
    final fmt = DateFormat('d MMMM • h:mm a', 'ar');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${c.typeLabel} ${c.displayNumber}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              _StatusPill(status: c.status, byTimeout: c.closedByTimeout),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                if (c.orderNumber != null) 'طلب #${c.orderNumber}',
                fmt.format(c.createdAt),
              ].join(' • '),
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),

            const SizedBox(height: 10),
            Text(c.description),

            // ── وعدُ الردّ: يُعرض ما دام لم يُردّ ─────────────────────────
            if (c.status == ComplaintStatus.open &&
                c.responseDueAt != null) ...[
              const SizedBox(height: 10),
              Countdown(
                deadline: c.responseDueAt,
                builder: (context, left, expired) => Row(children: [
                  Icon(expired ? Icons.error_outline : Icons.schedule,
                      size: 16,
                      color: expired ? Colors.red : Colors.black45),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      expired
                          // **ولا يُخفى تأخّرُنا عن الشاكي.** إخفاؤه يجعله
                          // يشكّ في أنّ أحدًا قرأها أصلًا.
                          ? 'تأخّرنا عن وعدنا بالردّ — نعتذر، وشكواك في الطابور'
                          : 'نردّ خلال ${formatRemaining(left!)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: expired ? Colors.red : Colors.black45,
                      ),
                    ),
                  ),
                ]),
              ),
            ],

            // ── ردُّ الإدارة ────────────────────────────────────────────
            if (c.resolution != null && c.resolution!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ردُّ الإدارة',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(c.resolution!),
                  ],
                ),
              ),
            ],

            // ── السؤال الذي يُغلق ───────────────────────────────────────
            if (c.awaitingConfirmation) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text('هل حُلّت مشكلتك فعلًا؟',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Countdown(
                deadline: c.autoCloseAt,
                builder: (context, left, expired) => Text(
                  left == null || expired
                      ? 'جوابُك يحسم الملفّ: «نعم» تُغلقه، و«لا» تعيده '
                          'للإدارة بأولويّة.'
                      : 'جوابُك يحسم الملفّ: «نعم» تُغلقه، و«لا» تعيده '
                          'للإدارة بأولويّة. وإن لم تُجب خلال '
                          '${formatRemaining(left)} أُغلق تلقائيًّا.',
                  style: const TextStyle(
                      fontSize: 12.5, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _answer(true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('نعم، حُلّت'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _answer(false),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('لا، لم تُحل'),
                  ),
                ),
              ]),
            ],

            if (c.wasReopened) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.replay, size: 15, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Text(
                  c.reopenCount == 1
                      ? 'أُعيدت مرّةً بعد أن قلتَ إنّها لم تُحل'
                      : 'أُعيدت ${c.reopenCount} مرّاتٍ',
                  style: TextStyle(
                      fontSize: 12.5, color: Colors.orange.shade800),
                ),
              ]),
            ],

            if (c.status == ComplaintStatus.closed && c.closedByTimeout) ...[
              const SizedBox(height: 10),
              const Text(
                // **ويُقال له إنّها أُغلقت بصمته لا برضاه** — كي يعرف أنّ
                // بابًا أُغلق دون أن يقرّر هو إغلاقه.
                'أُغلقت تلقائيًّا لانقضاء مهلة التأكيد. لك أن تفتح شكوى '
                'جديدةً إن بقيت المشكلة.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _showChat = !_showChat),
                icon: Icon(_showChat
                    ? Icons.keyboard_arrow_up
                    : Icons.chat_bubble_outline),
                label: Text(_showChat ? 'إخفاء المحادثة' : 'محادثة الإدارة'),
              ),
            ),
            if (_showChat)
              ComplaintChat(complaintId: c.id, role: widget.role),
          ],
        ),
      ),
    );
  }
}

/// محادثةُ الشكوى.
///
/// **منفصلةٌ عن دردشة الطلب**: تلك بين العميل والسائق أثناء التوصيل، وهذه
/// بين الشاكي والإدارة بعده. وخلطُهما يجعل سائقًا يقرأ شكوى عليه.
class ComplaintChat extends StatefulWidget {
  const ComplaintChat({
    super.key,
    required this.complaintId,
    required this.role,
    this.allowInternal = false,
  });

  final String complaintId;
  final String role;

  /// لموظّفي خدمة العملاء وحدهم: ملاحظةٌ لا تصل شاشةَ الشاكي.
  final bool allowInternal;

  @override
  State<ComplaintChat> createState() => _ComplaintChatState();
}

class _ComplaintChatState extends State<ComplaintChat> {
  final _service = const ComplaintsService();
  final _input = TextEditingController();
  late Future<List<ComplaintMessage>> _load =
      _service.messages(widget.complaintId);
  bool _internal = false;
  bool _busy = false;

  void _reload() =>
      setState(() => _load = _service.messages(widget.complaintId));

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.send(
        complaintId: widget.complaintId,
        body: body,
        role: widget.role,
        internal: _internal,
      );
      _input.clear();
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeDbError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Db.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<List<ComplaintMessage>>(
          future: _load,
          builder: (context, snap) {
            final msgs = snap.data ?? const <ComplaintMessage>[];
            if (msgs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا رسائل بعد.',
                    style: TextStyle(fontSize: 12.5, color: Colors.black45)),
              );
            }
            return Column(
              children: [
                for (final m in msgs)
                  _Bubble(message: m, mine: m.senderId == me),
              ],
            );
          },
        ),
        if (widget.allowInternal)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _internal,
            onChanged: (v) => setState(() => _internal = v ?? false),
            title: const Text('ملاحظةٌ داخليّة — لا يراها الشاكي',
                style: TextStyle(fontSize: 13)),
          ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'اكتب رسالة…',
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ]),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ComplaintMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final internal = message.isInternal;
    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: internal
              ? Colors.amber.withValues(alpha: 0.18)
              : mine
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (internal)
              const Text('داخليّة',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text(message.body),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.byTimeout});
  final ComplaintStatus status;
  final bool byTimeout;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ComplaintStatus.open => (Colors.blue, status.label),
      ComplaintStatus.inProgress => (Colors.orange, status.label),
      ComplaintStatus.resolved => (Colors.purple, status.label),
      // **الإغلاقُ بالصمت يُميَّز في الشاشة كما يُميَّز في التقرير.**
      ComplaintStatus.closed =>
        byTimeout ? (Colors.grey, 'أُغلقت تلقائيًّا') : (Colors.green, 'مغلقة'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('ما الذي بقي؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اكتب ما لم يُحلّ — يذهب مباشرةً إلى من يراجع شكواك، وشكواك '
              'ترتفع إلى أوّل الطابور.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجُع'),
          ),
          FilledButton(
            // نصٌّ فارغ مقبول: الرفضُ نفسُه إشارة، ولا يُحبَس خلف كتابة.
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('أرسِل'),
          ),
        ],
      );
}
