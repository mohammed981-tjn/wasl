import 'package:flutter/material.dart';
import '../entry_point.dart';
import 'driver_entry_point.dart';
import 'merchant_entry_point.dart';

enum UserRole { client, driver, merchant }

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wasl'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اختر نوع حسابك',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Client • Driver • Restaurant/Store',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _RoleCard(
                title: 'عميل',
                subtitle: 'اطلب أي شيء (مطاعم، بقالة، صيدلية، طرود...)',
                icon: Icons.shopping_bag_outlined,
                onTap: () => _go(context, const EntryPoint()),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'سائق',
                subtitle: 'استلام الطلبات وتتبع الأرباح والاشتراك الشهري',
                icon: Icons.local_shipping_outlined,
                onTap: () => _go(context, const DriverEntryPoint()),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'متجر / مطعم',
                subtitle: 'إدارة الطلبات والقائمة والاشتراك الشهري',
                icon: Icons.storefront_outlined,
                onTap: () => _go(context, const MerchantEntryPoint()),
              ),
              const Spacer(),
              Text(
                'ملاحظة: هذا اختيار مبدئي — تقدر تربطه لاحقًا بتسجيل دخول حقيقي.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
          color: theme.cardColor,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
