import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/customer_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../admin/orders_tab.dart' show OrderStatusChip;
import 'order_tracking_screen.dart';

/// سجلّ طلبات العميل.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final _service = const CustomerService();
  late Future<List<LaundryOrder>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final id = Db.currentUser?.id;
    setState(() {
      _future = id == null
          ? Future.value(const <LaundryOrder>[])
          : _service.myOrders(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: AsyncView<List<LaundryOrder>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا طلبات بعد',
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
                    builder: (_) => OrderTrackingScreen(orderId: o.id),
                  ));
                  _reload();
                },
                title: Row(
                  children: [
                    Text('#${o.orderNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    OrderStatusChip(status: o.status),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${o.items.length} خدمة  •  '
                    '${o.total.toStringAsFixed(2)} ر.س',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                trailing: const Icon(Icons.chevron_left),
              ),
            );
          },
        ),
      ),
    );
  }
}
