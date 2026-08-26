import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/orders_service.dart';
import '../../services/reports_service.dart';
import '../../services/session_service.dart';
import '../../widgets/async_view.dart';

/// لوحة تشغيل اليوم.
///
/// **الأرقام هنا محسوبةٌ من الطلبات لا مقروءةٌ من عدّادات**: عدّادٌ يُزاد عند
/// كل حدث ينحرف عن الحقيقة عند أوّل استثناء، والانحراف في رقمٍ يُبنى عليه قرار
/// أسوأ من غيابه.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _orders = const OrdersService();
  final _reports = const ReportsService();
  late Future<(TodayOperations, List<OrderAtRisk>)> _future;
  String? _branchId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branch = context.watch<SessionService>().activeBranchId;
    if (branch != _branchId) {
      _branchId = branch;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      final id = _branchId;
      _future = id == null
          ? Future.value((
              const TodayOperations(
                  byStatus: {}, revenue: 0, ordersToday: 0, lateCount: 0),
              <OrderAtRisk>[]
            ))
          : () async {
              final ops = await _orders.todayOperations(id);
              // الإنذار تكميليّ: تعذّرُه لا يُخفي أرقام اليوم.
              var risk = <OrderAtRisk>[];
              try {
                risk = await _reports.atRisk(id);
              } catch (_) {
                risk = const [];
              }
              return (ops, risk);
            }();
    });
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
        locale: 'ar', symbol: 'ر.س', decimalDigits: 2);

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<(TodayOperations, List<OrderAtRisk>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (ops, atRisk) = data;
          return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Text('تشغيل اليوم',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث'),
              ],
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(
                    label: 'طلبات اليوم',
                    value: '${ops.ordersToday}',
                    icon: Icons.receipt_long_outlined),
                _Stat(
                    label: 'إيراد اليوم',
                    value: money.format(ops.revenue),
                    icon: Icons.payments_outlined),
                _Stat(
                    label: 'متوسّط الطلب',
                    value: money.format(ops.averageOrderValue),
                    icon: Icons.calculate_outlined),
                _Stat(
                    label: 'متأخّر',
                    value: '${ops.lateCount}',
                    icon: Icons.schedule_outlined,
                    // التأخير وحده يُلوَّن: لونٌ على كل بطاقة لا يميّز شيئًا.
                    danger: ops.lateCount > 0),
              ],
            ),
            if (atRisk.isNotEmpty) ...[
              const SizedBox(height: 24),
              AtRiskCard(items: atRisk),
            ],
            const SizedBox(height: 28),

            Text('أين الطلبات الآن',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('كل مرحلةٍ وعددُ ما فيها — من الاستلام حتى التسليم.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),

            _StageBoard(byStatus: ops.byStatus),
          ],
        );
        },
      ),
    );
  }
}

/// شريطٌ يعرض مراحل الطلب بترتيبها الحقيقيّ.
///
/// والترتيب مأخوذٌ من ترتيب [OrderStatus] نفسه لا من قائمةٍ تُكتب هنا: مرحلةٌ
/// تُضاف غدًا في القاعدة تظهر في مكانها بلا تعديل شاشة.
class _StageBoard extends StatelessWidget {
  const _StageBoard({required this.byStatus});

  final Map<OrderStatus, int> byStatus;

  static const _tracked = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.pickupAssigned,
    OrderStatus.pickupEnRoute,
    OrderStatus.pickedUp,
    OrderStatus.atLaundry,
    OrderStatus.sorting,
    OrderStatus.washing,
    OrderStatus.drying,
    OrderStatus.ironing,
    OrderStatus.packaging,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in _tracked)
          _StageChip(
            label: s.labelAr,
            count: byStatus[s] ?? 0,
            highlight: s.isInsideLaundry,
            scheme: scheme,
          ),
      ],
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.count,
    required this.highlight,
    required this.scheme,
  });

  final String label;
  final int count;
  final bool highlight;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final empty = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: empty
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : (highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: empty ? scheme.outline : scheme.onSurface,
              )),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: empty ? scheme.outline : scheme.onSurface,
              )),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.primary;
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: danger ? scheme.error.withValues(alpha: 0.4)
                          : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// الطلبات المعرَّضة للتأخير.
///
/// **«متأخّر» معلومةٌ متأخّرة** — حين يتجاوز الطلبُ وعدَه يكون العميل قد انتظر،
/// وكلُّ ما بقي اعتذار. وهذه البطاقة تجيب سؤالًا أسبق: أيُّ طلبٍ لم يتأخّر
/// بعدُ وسيتأخّر؟ — فيُستعجَل أو يُعتذَر عنه **قبل** أن يشتكي صاحبُه.
///
/// **ولا يُخفى ضعفُ التقدير**: فرعٌ جديدٌ بلا تاريخٍ لا يُعطي تنبّؤًا، ويُقال
/// ذلك صراحةً بدل عرض رقمٍ يُصدَّق ولا يستحقّ.
class AtRiskCard extends StatelessWidget {
  const AtRiskCard({super.key, required this.items});

  final List<OrderAtRisk> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('h:mm a', 'ar');

    // المتأخّر فعلًا أوّلًا، ثم الأقربُ إلى التأخّر.
    final sorted = [...items]..sort((a, b) {
        if (a.alreadyLate != b.alreadyLate) return a.alreadyLate ? -1 : 1;
        return b.lateByMinutes.compareTo(a.lateByMinutes);
      });
    final predicted = sorted.where((o) => !o.alreadyLate).length;
    final weak = sorted.any((o) => !o.confident);

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    predicted > 0
                        ? '$predicted طلبًا يُتوقَّع أن يتأخّر'
                        : 'طلباتٌ تجاوزت وعدَها',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Text('${sorted.length}',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: scheme.error)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'محسوبٌ من مُدد الأطوار كما وقعت في هذا الفرع — لا من تقدير.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (weak) ...[
              const SizedBox(height: 6),
              Text(
                'بعضُ التقديرات ضعيف: تاريخُ الفرع قصير. تزداد دقّتُه مع كل طلبٍ يمرّ.',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ],
            const SizedBox(height: 10),

            for (final o in sorted.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: o.alreadyLate
                            ? scheme.error
                            : scheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        o.alreadyLate ? 'تأخّر' : 'سيتأخّر',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: o.alreadyLate ? scheme.onError : scheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('#${o.orderNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (o.isExpress) const Icon(Icons.bolt, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${o.status.labelAr} — وُعِد ${df.format(o.promisedReadyAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      o.confident ? 'بـ${o.lateLabel}' : '؟',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: scheme.error),
                    ),
                  ],
                ),
              ),

            if (sorted.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('و${sorted.length - 6} غيرها — في «الطلبات».',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
