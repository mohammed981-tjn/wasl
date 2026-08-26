import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/feedback_service.dart';
import '../../services/supabase_service.dart';

/// بطاقةُ التقييم في شاشة التتبّع.
///
/// **تُسأل النجمة أوّلًا ثم يُفتح ما بعدها.** سؤالُ العميل عن سببٍ ونصٍّ
/// وتقييمِ سائقٍ قبل أن يضغط نجمةً واحدة يجعله يُغلق الشاشة — والتقييم الذي
/// لا يُبدأ لا يكتمل.
///
/// **والأسبابُ تتبع النجمة**: من أعطى خمسًا لا يُسأل «ما الذي أزعجك؟»، ومن
/// أعطى واحدةً لا تُعرض عليه «كيٌّ ممتاز».
class RatingCard extends StatefulWidget {
  const RatingCard({
    super.key,
    required this.orderId,
    required this.existing,
    required this.onSaved,
    this.hasDriver = true,
  });

  final String orderId;
  final OrderRating? existing;
  final VoidCallback onSaved;
  final bool hasDriver;

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<RatingCard> {
  final _feedback = const FeedbackService();
  final _comment = TextEditingController();

  late int _stars = widget.existing?.stars ?? 0;
  late int? _deliveryStars = widget.existing?.deliveryStars;
  late final Set<String> _tags = {...?widget.existing?.tags};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _comment.text = widget.existing?.comment ?? '';
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  List<String> get _suggested => _stars >= 4
      ? FeedbackService.positiveTags
      : FeedbackService.negativeTags;

  Future<void> _save() async {
    if (_stars == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _feedback.rate(
        orderId: widget.orderId,
        stars: _stars,
        deliveryStars: _deliveryStars,
        tags: _tags.toList(),
        comment: _comment.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('شكرًا — وصل تقييمك.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rated = widget.existing != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rated ? 'تقييمك' : 'كيف كانت الخدمة؟',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              rated
                  ? 'تستطيع تعديله ما دامت المهلة مفتوحة.'
                  : 'نجمةٌ واحدة تكفي — والباقي إن أردت.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),

            _Stars(
              value: _stars,
              onChanged: (v) => setState(() {
                _stars = v;
                // تبديلُ الاتّجاه يُلغي أسبابًا لم تعد تُعرض — وإلّا حُفظ
                // «سريع» مع نجمةٍ واحدة.
                _tags.removeWhere((t) => !_suggested.contains(t));
              }),
            ),

            if (_stars > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in _suggested)
                    FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _tags.add(t);
                        } else {
                          _tags.remove(t);
                        }
                      }),
                    ),
                ],
              ),

              if (widget.hasDriver) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('التوصيل',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    _Stars(
                      value: _deliveryStars ?? 0,
                      size: 26,
                      onChanged: (v) => setState(() => _deliveryStars = v),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _comment,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'ملاحظة (اختياريّة)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy
                      ? 'جارٍ الإرسال…'
                      : (rated ? 'تحديث التقييم' : 'إرسال')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged, this.size = 34});

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            iconSize: size,
            // نجمةٌ مضغوطةٌ مرّةً أخرى تُلغي التقييم: من ضغط الثالثة خطأً
            // يجب أن يستطيع الرجوع.
            onPressed: () => onChanged(value == i ? 0 : i),
            icon: Icon(
              i <= value ? Icons.star_rounded : Icons.star_border_rounded,
              color: i <= value ? scheme.tertiary : scheme.outline,
            ),
          ),
      ],
    );
  }
}
