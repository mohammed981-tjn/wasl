import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/orders_service.dart';
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
  late Future<TodayOperations> _future;
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
      _future = _branchId == null
          ? Future.value(const TodayOperations(
              byStatus: {}, revenue: 0, ordersToday: 0, lateCount: 0))
          : _orders.todayOperations(_branchId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
        locale: 'ar', symbol: 'ر.س', decimalDigits: 2);

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<TodayOperations>(
        future: _future,
        onRetry: _reload,
        builder: (context, ops) => ListView(
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
        ),
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
