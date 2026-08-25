import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/laundry_service.dart';
import '../../services/session_service.dart';
import '../../widgets/async_view.dart';
import 'scan_screen.dart';
import 'stage_orders_screen.dart';

/// شاشة موظّف المغسلة: خطّ التشغيل.
///
/// **مرتَّبٌ بترتيب العمل لا أبجديًّا**: الموظّف يقف عند آلةٍ ويسأل «ما الذي
/// أمامي؟»، فالمراحل تُعرض كما تجري — من الوصول إلى الجاهزية. وعددٌ كبير في
/// مرحلةٍ متأخّرة يعني اختناقًا يُرى بالنظر.
class LaundryHome extends StatefulWidget {
  const LaundryHome({super.key});

  @override
  State<LaundryHome> createState() => _LaundryHomeState();
}

class _LaundryHomeState extends State<LaundryHome> {
  final _ops = const LaundryOpsService();
  late Future<Map<OrderStatus, int>> _future;
  String? _branchId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranchId;
    if (id != _branchId) {
      _branchId = id;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = _branchId == null
          ? Future.value(<OrderStatus, int>{})
          : _ops.stageCounts(_branchId!);
    });
  }

  Future<void> _openStage(OrderStatus stage) async {
    if (_branchId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StageOrdersScreen(branchId: _branchId!, stage: stage),
    ));
    _reload();
  }

  Future<void> _scan() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanScreen()));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('وصل • المغسلة'),
        actions: [
          if (session.branches.length > 1)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: session.activeBranchId,
                items: [
                  for (final b in session.branches)
                    DropdownMenuItem(value: b.id, child: Text(b.nameAr)),
                ],
                onChanged: (v) {
                  if (v != null) session.setActiveBranch(v);
                },
              ),
            ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: session.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      // زرُّ المسح كبيرٌ وثابت: هو الفعل الأكثر تكرارًا في المغسلة، ويُضغط
      // بيدٍ مبلولة.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('امسح'),
      ),
      body: AsyncView<Map<OrderStatus, int>>(
        future: _future,
        onRetry: _reload,
        builder: (context, counts) {
          final total = counts.values.fold(0, (a, b) => a + b);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text('خطّ التشغيل',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(total == 0
                    ? 'لا طلبات في المغسلة الآن.'
                    : '$total طلبًا داخل المغسلة.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                for (final stage in LaundryOpsService.stages)
                  _StageCard(
                    stage: stage,
                    count: counts[stage] ?? 0,
                    onTap: () => _openStage(stage),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.count,
    required this.onTap,
  });

  final OrderStatus stage;
  final int count;
  final VoidCallback onTap;

  IconData get _icon => switch (stage) {
        OrderStatus.atLaundry => Icons.inventory_2_outlined,
        OrderStatus.sorting => Icons.checklist_rtl,
        OrderStatus.washing => Icons.local_laundry_service_outlined,
        OrderStatus.drying => Icons.dry_cleaning_outlined,
        OrderStatus.ironing => Icons.iron_outlined,
        OrderStatus.packaging => Icons.inventory_outlined,
        _ => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = count == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: empty ? null : onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: empty
              ? scheme.surfaceContainerHighest
              : scheme.primaryContainer,
          child: Icon(_icon,
              color: empty ? scheme.outline : scheme.primary),
        ),
        title: Text(stage.labelAr,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: empty ? scheme.outline : null)),
        trailing: Text(
          '$count',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: empty ? scheme.outline : scheme.primary,
          ),
        ),
      ),
    );
  }
}
