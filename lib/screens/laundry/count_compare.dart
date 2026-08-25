import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/models.dart';

/// مقارنة المطلوب بالمجرود.
///
/// **الفرق يُعرض ولا يُطمس**: «طلب ٣ ووصل ٤» معلومةٌ تُحسم بها خلافاتٌ لاحقة،
/// وإخفاؤها يجعل القطعة الزائدة تُسلَّم بلا حساب أو تضيع بلا أثر.
class CountCompare extends StatelessWidget {
  const CountCompare({required this.order, required this.garments, super.key});

  final LaundryOrder order;
  final List<OrderGarment> garments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // المطلوب بالقطع: بنود «القطعة» وحدها تُقارَن — الوزن والسلّة لا يُعدّان.
    final expected = order.items
        .where((i) => i.unit == PricingUnit.piece)
        .fold<double>(0, (s, i) => s + i.quantity);
    final counted = garments.length;
    final hasWeighted =
        order.items.any((i) => i.unit != PricingUnit.piece);

    final match = expected == 0 || counted == expected.round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: match
            ? scheme.surfaceContainerHighest
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(match ? Icons.check_circle_outline : Icons.compare_arrows,
              color: match ? scheme.primary : scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expected == 0
                      ? 'جُرِدت $counted قطعة'
                      : 'طلب ${expected.toStringAsFixed(0)} — جُرِد $counted',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (!match)
                  Text(
                    counted > expected
                        ? 'وصلت ${counted - expected.round()} قطعة زائدة — سجّلها قبل الغسيل.'
                        : 'ينقص ${expected.round() - counted} قطعة عمّا طُلب.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (hasWeighted)
                  Text('وفي الطلب بنودٌ بالوزن أو بالسلّة لا تُعدّ بالقطعة.',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
