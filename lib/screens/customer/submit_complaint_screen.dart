import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/complaints_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../../widgets/countdown.dart';

/// شاشةُ فتح شكوى.
///
/// **تخدم الأدوار الثلاثة بنسخةٍ واحدة**: العميل والسائق وموظّف المغسلة.
/// والفرقُ بينهم في **قائمة الأنواع** وحدها — وهي من القاعدة لا من الشيفرة،
/// فلا `if` على الدور هنا ولا ثلاثُ شاشاتٍ تتباعد بمرور الوقت.
class SubmitComplaintScreen extends StatefulWidget {
  const SubmitComplaintScreen({
    super.key,
    required this.order,
    required this.role,
    this.parties = const [],
  });

  final LaundryOrder order;

  /// دورُ الشاكي **في هذا الطلب**: صاحبُ المغسلة قد يطلب لنفسه، فهو حينها
  /// عميلٌ لا مدير. والقاعدةُ تعيد اشتقاقَه على كلّ حال.
  final String role;

  /// أطرافُ الطلب الذين يجوز أن يُشتكى عليهم — (المعرّف، الاسم، الدور).
  final List<({String id, String name, String role})> parties;

  @override
  State<SubmitComplaintScreen> createState() => _SubmitComplaintScreenState();
}

class _SubmitComplaintScreenState extends State<SubmitComplaintScreen> {
  final _service = const ComplaintsService();
  final _description = TextEditingController();

  late Future<_FormData> _load = _fetch();

  ComplaintType? _type;
  String? _againstId;
  String? _againstRole;
  bool _busy = false;
  String? _error;

  Future<_FormData> _fetch() async {
    final results = await Future.wait([
      _service.types(laundryId: widget.order.laundryId, role: widget.role),
      _service.settings(widget.order.laundryId),
    ]);
    return _FormData(
      types: results[0] as List<ComplaintType>,
      settings: results[1] as ComplaintSettings,
    );
  }

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// متى تُقفل نافذةُ الشكوى على هذا الطلب؟
  ///
  /// **والطلبُ الجاري بلا مهلة**: لا معنى لمهلةٍ على شيءٍ لم ينتهِ بعد.
  DateTime? _deadline(ComplaintSettings s) {
    final o = widget.order;
    if (!o.status.isTerminal && o.status != OrderStatus.delivered) return null;
    final base = o.deliveredAt ?? o.createdAt;
    return base.add(Duration(hours: s.windowHours));
  }

  /// اختيارُ الطرف المقترَح لنوعٍ ما، إن كان في هذا الطلب أصلًا.
  void _applySuggested(ComplaintType t) {
    final match = widget.parties
        .where((p) => p.role == t.suggestedAgainst && p.id != Db.currentUser?.id)
        .firstOrNull;
    _againstId = match?.id;
    _againstRole = match?.role;
  }

  bool get _canSubmit =>
      _type != null && _description.text.trim().length >= 5 && !_busy;

  Future<void> _submit(ComplaintSettings settings) async {
    // **حارسُ المهلة عند الإرسال لا عند الفتح.** من فتح الشاشة قبل انقضائها
    // ثم أطال الكتابة كان يُرسل شكوى بعد إغلاق النافذة، فتُردّ بعد أن كتب.
    final deadline = _deadline(settings);
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      setState(() => _error =
          'انتهت مهلة الشكوى على هذا الطلب (${settings.windowHours} ساعة)');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.submit(
        typeId: _type!.id,
        description: _description.text,
        orderId: widget.order.id,
        laundryId: widget.order.laundryId,
        againstId: _againstId,
        againstRole: _againstRole,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فتحُ شكوى')),
      body: AsyncView<_FormData>(
        future: _load,
        onRetry: () => setState(() => _load = _fetch()),
        builder: (context, data) {
          if (!data.settings.isEnabled || data.types.isEmpty) {
            return const _Notice(
              icon: Icons.info_outline,
              text: 'استقبالُ الشكاوى غيرُ مفعّلٍ في هذه المغسلة حاليًّا.\n'
                  'تواصل مع الفرع مباشرةً.',
            );
          }

          final deadline = _deadline(data.settings);

          return Countdown(
            deadline: deadline,
            builder: (context, left, expired) {
              if (expired) {
                return _Notice(
                  icon: Icons.schedule,
                  text: 'انتهت مهلةُ الشكوى على هذا الطلب '
                      '(${data.settings.windowHours} ساعة من تسليمه).\n'
                      'تواصل مع الفرع مباشرةً.',
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OrderChip(order: widget.order),
                  const SizedBox(height: 12),
                  if (left != null) _WindowBanner(left: left),
                  const SizedBox(height: 16),

                  const Text('ما نوعُ المشكلة؟',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in data.types)
                        ChoiceChip(
                          label: Text(t.labelAr),
                          selected: _type?.id == t.id,
                          onSelected: (_) => setState(() {
                            _type = t;
                            _applySuggested(t);
                          }),
                        ),
                    ],
                  ),

                  if (widget.parties.length > 1) ...[
                    const SizedBox(height: 20),
                    const Text('على مَن؟',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'واختيارُ «الخدمة عمومًا» ليس تهرّبًا — أكثرُ المشكلات '
                      'ليست خطأ شخصٍ بعينه.',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('الخدمة عمومًا'),
                          selected: _againstId == null,
                          onSelected: (_) => setState(() {
                            _againstId = null;
                            _againstRole = null;
                          }),
                        ),
                        for (final p in widget.parties)
                          if (p.id != Db.currentUser?.id)
                            ChoiceChip(
                              label: Text(p.name),
                              selected: _againstId == p.id,
                              onSelected: (_) => setState(() {
                                _againstId = p.id;
                                _againstRole = p.role;
                              }),
                            ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text('ماذا حدث؟',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _description,
                    maxLines: 5,
                    maxLength: 1000,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'اذكر التفاصيل: أيُّ قطعةٍ، ومتى، وما الذي '
                          'لاحظتَه — كلَّما وضَح الوصف أسرعَ الحلّ.',
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],

                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed:
                        _canSubmit ? () => _submit(data.settings) : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('إرسال الشكوى'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سنردّ عليك، ولن تُغلق شكواك إلا بعد أن تقول أنت إنّها '
                    'حُلّت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FormData {
  const _FormData({required this.types, required this.settings});
  final List<ComplaintType> types;
  final ComplaintSettings settings;
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({required this.order});
  final LaundryOrder order;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.receipt_long_outlined),
          const SizedBox(width: 8),
          Text('طلب #${order.orderNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
}

/// **المهلةُ تُعرض ولا تُخفى.** إخفاؤها يجعل الرفضَ مفاجأة.
class _WindowBanner extends StatelessWidget {
  const _WindowBanner({required this.left});
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final urgent = left.inHours < 6;
    return Row(children: [
      Icon(Icons.schedule,
          size: 18, color: urgent ? Colors.orange.shade800 : Colors.black54),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          'يبقى أمامك ${formatRemaining(left)} لفتح شكوى على هذا الطلب',
          style: TextStyle(
            fontSize: 13,
            color: urgent ? Colors.orange.shade800 : Colors.black54,
            fontWeight: urgent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
