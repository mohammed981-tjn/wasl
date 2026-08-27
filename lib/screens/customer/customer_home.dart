import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/cart.dart';
import '../../services/customer_service.dart';
import '../../services/feedback_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import 'checkout_screen.dart';
import 'loyalty_screen.dart';
import 'my_complaints_screen.dart';
import 'notifications_screen.dart';
import 'my_orders_screen.dart';

/// شاشة العميل: الكتالوج والسلّة.
///
/// **الأسعار المعروضة هنا هي النافذة في الفرع** — لا `base_price` الخاص
/// بالمغسلة. والفرق ليس تفصيلًا: عرضُ سعرٍ ثم تحصيلُ آخر عند التسليم أسوأ من
/// عدم العرض أصلًا.
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final _service = const CustomerService();
  late Future<List<({LaundryService service, double price})>> _future;
  String? _branchId;

  /// الرصيد يُجلب مستقلًّا عن الكتالوج: تعذُّره لا يُخفي الخدمات.
  LoyaltyState? _loyalty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branch = context.watch<SessionService>().activeBranch;
    if (branch?.id != _branchId) {
      _branchId = branch?.id;
      _reload();
    }
  }

  void _reload() {
    final branch = context.read<SessionService>().activeBranch;
    setState(() {
      _future = branch == null
          ? Future.value(const [])
          : _service.catalog(laundryId: branch.laundryId, branchId: branch.id);
    });
    _loadLoyalty(branch);
  }

  Future<void> _loadLoyalty(Branch? branch) async {
    final userId = Db.currentUser?.id;
    if (branch == null || userId == null) return;
    try {
      final l = await const FeedbackService()
          .loyalty(userId: userId, laundryId: branch.laundryId);
      if (mounted) setState(() => _loyalty = l);
    } catch (_) {
      if (mounted) setState(() => _loyalty = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final cart = context.watch<Cart>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('وصل'),
        actions: [
          IconButton(
            tooltip: 'طلباتي',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
            ),
          ),
          const NotificationsBell(),
          IconButton(
            tooltip: 'شكاويّ',
            icon: const Icon(Icons.support_agent_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyComplaintsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: session.signOut,
          ),
        ],
      ),
      bottomNavigationBar: cart.isEmpty ? null : _CartBar(cart: cart),
      body: AsyncView<List<({LaundryService service, double price})>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا خدمات متاحة في هذا الفرع',
        builder: (context, items) => ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, cart.isEmpty ? 24 : 96),
          children: [
            if (session.branches.length > 1) ...[
              _BranchPicker(session: session),
              const SizedBox(height: 16),
            ],
            if ((_loyalty?.balance ?? 0) > 0) ...[
              _LoyaltyBanner(
                balance: _loyalty!.balance,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LoyaltyScreen(
                    laundryId: session.activeBranch!.laundryId,
                  ),
                )),
              ),
              const SizedBox(height: 16),
            ],
            Text('اختر خدماتك',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('الأسعار شاملة، والتوصيل يُحسب حسب موقعك في الخطوة التالية.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final it in items)
              _ServiceTile(
                service: it.service,
                price: it.price,
                quantity: cart.quantityOf(it.service.id),
                onChanged: (q) =>
                    cart.setQuantity(it.service, q, it.price),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchPicker extends StatelessWidget {
  const _BranchPicker({required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.store_outlined),
          title: const Text('الفرع'),
          subtitle: Text(session.activeBranch?.nameAr ?? '—'),
          trailing: DropdownButtonHideUnderline(
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
        ),
      );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.price,
    required this.quantity,
    required this.onChanged,
  });

  final LaundryService service;
  final double price;
  final double quantity;
  final void Function(double) onChanged;

  /// خطوةُ الزيادة بحسب الوحدة: القطعة تُعدّ صحيحةً، والكيلو ينقسم.
  double get _step => service.unit == PricingUnit.kilogram ? 0.5 : 1;

  String get _quantityLabel => service.unit == PricingUnit.kilogram
      ? quantity.toStringAsFixed(1)
      : quantity.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = quantity > 0;
    final belowMin =
        selected && service.minQuantity > 0 && quantity < service.minQuantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.nameAr,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '${price.toStringAsFixed(2)} ر.س / ${service.unit.labelAr}'
                        '  •  خلال ${service.turnaroundHours} ساعة',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // مربّع العدّ: الطرح مُعطَّل عند صفرٍ بدل أن يُخفى، كي لا يقفز
                // التخطيط عند أوّل نقرة.
                IconButton(
                  onPressed: quantity <= 0
                      ? null
                      : () => onChanged((quantity - _step).clamp(0, 999)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 34,
                  child: Text(_quantityLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: selected ? scheme.primary : scheme.outline)),
                ),
                IconButton(
                  onPressed: () => onChanged(quantity + _step),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            // الحدّ الأدنى يُقال **عند تجاوزه لا عند الإرسال**: رفضٌ بعد ملء
            // السلّة كلّها أسوأ من تنبيهٍ في مكانه.
            if (belowMin)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'الحدّ الأدنى ${service.minQuantity.toStringAsFixed(0)} '
                    '${service.unit.labelAr}',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = cart.belowMinimum;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (blocked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'لم تبلغ الحدّ الأدنى: ${blocked.map((s) => s.nameAr).join('، ')}',
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
            FilledButton(
              onPressed: blocked.isNotEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CheckoutScreen()),
                      ),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${cart.count} خدمة'),
                  const Text('متابعة الطلب'),
                  Text('${cart.subtotal.toStringAsFixed(2)} ر.س',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريطُ النقاط في أعلى الكتالوج.
///
/// **الرصيد يُعرض حيث يُنفَق لا في شاشةٍ منفصلةٍ وحدها**: من لا يعرف أن له
/// نقاطًا لا يعود ليصرفها، ونظامُ ولاءٍ لا يُرى لا يُبقي أحدًا.
class _LoyaltyBanner extends StatelessWidget {
  const _LoyaltyBanner({required this.balance, required this.onTap});

  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.stars_rounded, color: scheme.primary),
        title: Text('لديك $balance نقطة',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('تُصرف من فاتورتك عند إتمام الطلب.'),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}
