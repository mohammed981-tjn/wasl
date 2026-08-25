import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/laundry_service.dart';
import '../../widgets/async_view.dart';
import '../admin/orders_tab.dart' show OrderStatusChip;
import 'order_intake_screen.dart';

/// طلبات مرحلةٍ واحدة.
///
/// **مرتَّبةٌ بوعد الجاهزية لا بوقت الوصول**: من وُعِد أوّلًا يُنجَز أوّلًا،
/// والترتيب بالوصول يجعل طلبًا مستعجلًا ينتظر خلف طلبٍ مهله يومان.
class StageOrdersScreen extends StatefulWidget {
  const StageOrdersScreen({
    super.key,
    required this.branchId,
    required this.stage,
  });

  final String branchId;
  final OrderStatus stage;

  @override
  State<StageOrdersScreen> createState() => _StageOrdersScreenState();
}

class _StageOrdersScreenState extends State<StageOrdersScreen> {
  final _ops = const LaundryOpsService();
  late Future<List<LaundryOrder>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _future = _ops.ofStage(widget.branchId, widget.stage));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stage.labelAr),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<List<LaundryOrder>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا طلبات في «${widget.stage.labelAr}»',
        builder: (context, orders) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final o = orders[i];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrderIntakeScreen(orderId: o.id),
                  ));
                  _reload();
                },
                leading: CircleAvatar(
                  backgroundColor: o.isLate
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: Text('#${o.orderNumber}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(o.customerName ?? 'عميل',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (o.isExpress)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: Icon(Icons.bolt,
                            size: 16,
                            color: Theme.of(context).colorScheme.tertiary),
                      ),
                    if (o.isLate)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          label: const Text('متأخّر',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    o.barcode ?? '—',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                trailing: OrderStatusChip(status: o.status),
              ),
            );
          },
        ),
      ),
    );
  }
}
