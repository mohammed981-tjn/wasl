import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/orders_service.dart';
import '../../services/session_service.dart';
import '../../widgets/async_view.dart';
import 'order_detail_screen.dart';

/// قائمة الطلبات.
///
/// **الترشيح بمجموعاتٍ تشغيلية لا بحالةٍ واحدة**: من يفتح هذه الشاشة يسأل «ما
/// الذي ينتظرني؟» لا «أرني ما حالته `drying`». فالمجموعات تطابق السؤال:
/// جديد، عند السائق، داخل المغسلة، جاهز، متأخّر.
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

/// مرشّحٌ تشغيليّ — مجموعةُ حالاتٍ يسأل عنها المشغّل سؤالًا واحدًا.
enum _Filter {
  all('الكل', null),
  incoming('جديد', {OrderStatus.placed, OrderStatus.accepted}),
  withDriver('عند السائق', {
    OrderStatus.pickupAssigned,
    OrderStatus.pickupEnRoute,
    OrderStatus.pickedUp,
    OrderStatus.deliveryAssigned,
    OrderStatus.outForDelivery,
  }),
  inLaundry('داخل المغسلة', {
    OrderStatus.atLaundry,
    OrderStatus.sorting,
    OrderStatus.washing,
    OrderStatus.drying,
    OrderStatus.ironing,
    OrderStatus.packaging,
  }),
  ready('جاهز', {OrderStatus.ready}),
  onHold('موقوف', {OrderStatus.onHold}),
  done('منتهٍ', {
    OrderStatus.delivered,
    OrderStatus.cancelled,
    OrderStatus.refunded,
  });

  const _Filter(this.labelAr, this.statuses);
  final String labelAr;
  final Set<OrderStatus>? statuses;
}

class _OrdersTabState extends State<OrdersTab> {
  final _orders = const OrdersService();
  final _searchCtl = TextEditingController();

  late Future<List<LaundryOrder>> _future;
  String? _branchId;
  _Filter _filter = _Filter.all;
  String _search = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranchId;
    if (id != _branchId) {
      _branchId = id;
      _reload();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _branchId == null
          ? Future.value(const <LaundryOrder>[])
          : _orders.list(_branchId!,
              statuses: _filter.statuses, search: _search);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('الطلبات',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث'),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtl,
                decoration: InputDecoration(
                  hintText: 'رقم الطلب أو الباركود',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchCtl.clear();
                            _search = '';
                            _reload();
                          },
                        ),
                ),
                onSubmitted: (v) {
                  _search = v;
                  _reload();
                },
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(f.labelAr),
                          selected: _filter == f,
                          onSelected: (_) {
                            _filter = f;
                            _reload();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncView<List<LaundryOrder>>(
            future: _future,
            onRetry: _reload,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: _search.isNotEmpty
                ? 'لا طلب بهذا الرقم'
                : 'لا طلبات في «${_filter.labelAr}»',
            builder: (context, orders) => ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => OrderRow(
                order: orders[i],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(orderId: orders[i].id),
                  ));
                  _reload();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// صفٌّ في قائمة الطلبات.
class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order, this.onTap});

  final LaundryOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('MM-dd HH:mm').format(order.createdAt);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: order.isLate
              ? scheme.errorContainer
              : scheme.primaryContainer,
          child: Text('#${order.orderNumber}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                order.customerName?.trim().isNotEmpty == true
                    ? order.customerName!
                    : 'عميل',
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OrderStatusChip(status: order.status),
            if (order.isExpress)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Icon(Icons.bolt, size: 16, color: scheme.tertiary),
              ),
            // التأخير يُعلَن هنا لا في شاشةٍ أخرى: من يقرأ القائمة يجب أن يراه.
            if (order.isLate)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: scheme.errorContainer,
                  label: const Text('متأخّر', style: TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$time  •  ${order.total.toStringAsFixed(2)} ر.س'
            '  •  ${order.paymentStatus.labelAr}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}

/// رقاقة الحالة، ملوّنةً بمعناها التشغيليّ.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      OrderStatus.delivered => (scheme.primaryContainer, scheme.onPrimaryContainer),
      OrderStatus.cancelled ||
      OrderStatus.refunded ||
      OrderStatus.onHold =>
        (scheme.errorContainer, scheme.onErrorContainer),
      OrderStatus.ready => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurface),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.labelAr,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
