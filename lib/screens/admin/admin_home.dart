import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/session_service.dart';
import 'coupons_tab.dart';
import 'dashboard_tab.dart';
import 'delivery_fees_tab.dart';
import 'orders_tab.dart';
import 'payments_tab.dart';
import 'reports_tab.dart';
import 'schedule_tab.dart';
import 'services_pricing_tab.dart';
import 'staff_tab.dart';
import 'templates_tab.dart';

/// هيكل لوحة الإدارة.
///
/// **شريطٌ جانبيّ لا شريطٌ سفليّ**: هذه اللوحة تُستعمل على شاشةٍ عريضة —
/// متصفّحٍ على مكتب — لا على جوّال بيدٍ واحدة. والشريط السفليّ يضيّع عرضًا
/// ثمينًا في جدولٍ من عشرة أعمدة.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'اليوم'),
    (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'الطلبات'),
    (icon: Icons.local_offer_outlined, selected: Icons.local_offer, label: 'الخدمات والأسعار'),
    (icon: Icons.local_shipping_outlined, selected: Icons.local_shipping, label: 'رسوم التوصيل'),
    (icon: Icons.schedule_outlined, selected: Icons.schedule, label: 'المواعيد والطاقة'),
    (icon: Icons.confirmation_number_outlined, selected: Icons.confirmation_number, label: 'الكوبونات'),
    (icon: Icons.badge_outlined, selected: Icons.badge, label: 'الموظّفون'),
    (icon: Icons.payments_outlined, selected: Icons.payments, label: 'المدفوعات'),
    (icon: Icons.campaign_outlined, selected: Icons.campaign, label: 'رسائل العميل'),
    (icon: Icons.insights_outlined, selected: Icons.insights, label: 'التقارير'),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();

    if (!session.canUseAdminApp) {
      return _NoAccess(onSignOut: session.signOut);
    }
    if (session.branches.isEmpty) {
      return _NoBranch(onSignOut: session.signOut, error: session.error);
    }

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    final body = switch (_index) {
      0 => const DashboardTab(),
      1 => const OrdersTab(),
      2 => const ServicesPricingTab(),
      3 => const DeliveryFeesTab(),
      4 => const ScheduleTab(),
      5 => const CouponsTab(),
      6 => const StaffTab(),
      7 => const PaymentsTab(),
      8 => const TemplatesTab(),
      _ => const ReportsTab(),
    };

    return Scaffold(
      // ثمانية أقسامٍ لا يحتملها شريطٌ سفليّ (وMaterial يحدّها بخمسة)، فتصير
      // قائمةً جانبية على الشاشة الضيّقة. والقصُّ إلى خمسةٍ يُخفي ثلاثة أقسامٍ
      // كاملة — وهو أسوأ من نقرةٍ إضافية.
      drawer: isWide ? null : _NavDrawer(
        index: _index,
        destinations: _destinations,
        onSelect: (i) => setState(() => _index = i),
      ),
      appBar: AppBar(
        title: const Text('وصل • الإدارة'),
        actions: [
          if (session.branches.length > 1) const _BranchPicker(),
          const SizedBox(width: 8),
          _RoleChip(role: session.primaryRole),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
          if (isWide) const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _BranchPicker extends StatelessWidget {
  const _BranchPicker();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: session.activeBranchId,
        icon: const Icon(Icons.arrow_drop_down),
        items: [
          for (final b in session.branches)
            DropdownMenuItem(value: b.id, child: Text(b.nameAr)),
        ],
        onChanged: (v) {
          if (v != null) session.setActiveBranch(v);
        },
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AppRole? role;

  @override
  Widget build(BuildContext context) {
    if (role == null) return const SizedBox.shrink();
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(role!.labelAr, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// دخل بحسابٍ لا دور إداريًّا له.
///
/// وهذه شاشةٌ **صادقة**: لا تخفي التبويبات وتتركه يظنّ أنّ اللوحة فارغة، بل
/// تقول له إن حسابه ليس إداريًّا. وحتى لو تجاوزها بحزمةٍ معدَّلة لَما رأى صفًّا:
/// سياسات RLS ترفض، لا الشاشة.
class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text('هذا الحساب ليس له دور إداريّ',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('راجع مالك المنصّة لإسناد دورٍ لك.'),
              const SizedBox(height: 20),
              TextButton(
                  onPressed: onSignOut, child: const Text('تسجيل الخروج')),
            ],
          ),
        ),
      );
}

class _NoBranch extends StatelessWidget {
  const _NoBranch({required this.onSignOut, this.error});

  final Future<void> Function() onSignOut;
  final String? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.store_outlined, size: 48),
              const SizedBox(height: 12),
              Text('لا فرع مرتبطٌ بحسابك',
                  style: Theme.of(context).textTheme.titleMedium),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              TextButton(
                  onPressed: onSignOut, child: const Text('تسجيل الخروج')),
            ],
          ),
        ),
      );
}


class _NavDrawer extends StatelessWidget {
  const _NavDrawer({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });

  final int index;
  final List<({IconData icon, IconData selected, String label})> destinations;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: index,
      onDestinationSelected: (i) {
        onSelect(i);
        Navigator.pop(context);
      },
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 16, 12),
          child: Text('وصل • الإدارة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        for (final d in destinations)
          NavigationDrawerDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selected),
            label: Text(d.label),
          ),
      ],
    );
  }
}
