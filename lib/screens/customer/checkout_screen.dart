import 'package:flutter/material.dart';
// intl يصدّر `TextDirection` خاصًّا به يحجب نظيرَ Flutter، فيُخفى.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/cart.dart';
import '../../services/customer_service.dart';
import '../../services/delivery_service.dart';
import '../../services/feedback_service.dart';
import '../../services/payments_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import 'location_picker_screen.dart';
import 'order_tracking_screen.dart';

/// إتمام الطلب: العنوان، والموعد، والكوبون، والتأكيد.
///
/// **كل رقمٍ في الملخّص يأتي من القاعدة.** التطبيق لا يجمع ولا يخصم ولا يحسب
/// ضريبة — يعرض ما أعادته `quote_delivery_fee` و`quote_coupon` و`compute_vat`.
/// ولو حَسَب لصار في النظام مرجعان، وأوّل اختلافٍ بينهما شكوى.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _service = const CustomerService();
  final _delivery = const DeliveryService();
  final _couponCtl = TextEditingController();
  final _notesCtl = TextEditingController();

  List<Address> _addresses = const [];
  Address? _address;
  List<BookingSlot> _slots = const [];
  BookingSlot? _slot;
  CheckoutQuote? _quote;
  PaymentMethod _payment = PaymentMethod.cashOnDelivery;
  bool _cardAvailable = false;
  LoyaltyState? _loyalty;
  bool _useLoyalty = false;

  bool _loading = true;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _couponCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<SessionService>();
    final branch = session.activeBranch;
    final userId = Db.currentUser?.id;
    if (branch == null || userId == null) return;

    // تُقرأ السلّة **قبل** أوّل `await`: استعمال BuildContext بعد فجوةٍ غير
    // متزامنة ينهار إن أُغلقت الشاشة أثناء الجلب — وهو ما يفعله من ينتظر
    // شبكةً بطيئة ثم يرجع.
    final cart = context.read<Cart>();

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final addresses = await _service.addresses(userId);
      final slots = await _delivery.slots(
        branchId: branch.id,
        pieceLoad: cart.pieceLoad,
      );
      // تعذُّر معرفة المزوّد لا يمنع الطلب: تُخفى البطاقة ويبقى النقد.
      var cardOk = false;
      try {
        cardOk = await const PaymentsService().cardAvailable(branch.laundryId);
      } catch (_) {
        cardOk = false;
      }

      if (!mounted) return;
      setState(() {
        _cardAvailable = cardOk;
        _addresses = addresses;
        _address = addresses.isEmpty ? null : addresses.first;
        _slots = slots;
        _slot = slots.cast<BookingSlot?>().firstWhere(
            (s) => s?.isAvailable ?? false,
            orElse: () => null);
      });
      await _requote();
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requote() async {
    final session = context.read<SessionService>();
    final branch = session.activeBranch;
    final userId = Db.currentUser?.id;
    final address = _address;
    if (branch == null || userId == null || address == null) return;

    final subtotal = context.read<Cart>().subtotal;

    try {
      // النقاط تُسأل مع كل تسعير: ما يُسمح بصرفه يتبع مبلغ الفاتورة.
      final q = await _service.quote(
        laundryId: branch.laundryId,
        branchId: branch.id,
        userId: userId,
        subtotal: subtotal,
        lat: address.lat,
        lng: address.lng,
        couponCode: _couponCtl.text,
      );

      LoyaltyState? loyalty;
      try {
        loyalty = await const FeedbackService().loyalty(
          userId: userId,
          laundryId: branch.laundryId,
          subtotal: subtotal,
        );
      } catch (_) {
        loyalty = null;
      }

      if (mounted) {
        setState(() {
          _quote = q;
          _loyalty = loyalty;
          // رصيدٌ صار لا يكفي بعد تغيّر السلّة يُطفئ الخيار بدل أن يبقى
          // مؤشَّرًا على شيءٍ لا يقع.
          if (loyalty == null || !loyalty.canRedeem) _useLoyalty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    }
  }

  Future<void> _addAddress() async {
    final userId = Db.currentUser?.id;
    if (userId == null) return;
    final branch = context.read<SessionService>().activeBranch;

    final created = await showDialog<Address>(
      context: context,
      builder: (_) => _AddressDialog(
        userId: userId,
        // مركز الفرع نقطةَ بدايةٍ: أقربُ تخمينٍ صحيحٍ لمن يطلب من حيّه.
        defaultLat: branch?.lat ?? 24.4672,
        defaultLng: branch?.lng ?? 39.6142,
      ),
    );
    if (created == null) return;

    try {
      final saved = await _service.addAddress(created);
      if (!mounted) return;
      setState(() {
        _addresses = [saved, ..._addresses];
        _address = saved;
      });
      await _requote();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
      }
    }
  }

  Future<void> _place() async {
    final session = context.read<SessionService>();
    final branch = session.activeBranch;
    final userId = Db.currentUser?.id;
    final cart = context.read<Cart>();
    final address = _address;
    final slot = _slot;
    final quote = _quote;

    if (branch == null || userId == null || address == null ||
        slot == null || quote == null) {
      return;
    }

    setState(() => _placing = true);
    try {
      final order = await _service.placeOrder(
        laundryId: branch.laundryId,
        branchId: branch.id,
        customerId: userId,
        cart: cart,
        quote: quote,
        pickupAddressId: address.id,
        deliveryAddressId: address.id,
        pickupSlot: slot.start,
        paymentMethod: _payment,
        loyaltyPoints:
            _useLoyalty ? (_loyalty?.redeemablePoints ?? 0) : 0,
        notes: _notesCtl.text,
      );
      cart.clear();
      if (!mounted) return;
      // الطلب أُرسل، والدفع خطوةٌ تليه. وفصلُهما مقصود: فشلُ فتح صفحة الدفع
      // لا يجوز أن يضيّع طلبًا وُضع — يُدفع من شاشة التتبّع متى شاء.
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(
          orderId: order.id,
          justPlaced: true,
          payNow: _payment == PaymentMethod.card,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  /// الوعدُ بعد المغادرة لا يُقطَع.
  ///
  /// نزيلُ الفندق يغادر في تاريخٍ يعرفه، والطلب يجهز بعد ساعاتٍ نعرفها. فإن
  /// تجاوز الوعدُ المغادرةَ فالمشكلة تُقال **الآن** لا حين يتّصل السائق بغرفةٍ
  /// أخلاها صاحبها.
  String? get _checkoutWarning {
    final a = _address;
    final s = _slot;
    if (a == null || s == null || !a.isHotel) return null;
    // تُقرأ داخل build فلا فجوة غير متزامنة هنا.
    final cart = context.read<Cart>();
    final hours = cart.lines
        .fold<int>(0, (m, l) => l.service.turnaroundHours > m
            ? l.service.turnaroundHours : m);
    final ready = s.start.add(Duration(hours: hours));
    if (!a.leavesBefore(ready)) return null;
    return 'موعد مغادرتك قبل جاهزية الطلب '
        '(${DateFormat('MM-dd').format(ready)}). اختر موعد استلامٍ أبكر أو '
        'خدمةً أسرع.';
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final quote = _quote;
    final warning = _checkoutWarning;

    return Scaffold(
      appBar: AppBar(title: const Text('إتمام الطلب')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            onPressed: (_placing ||
                    _address == null ||
                    _slot == null ||
                    quote == null ||
                    !quote.serviceable)
                ? null
                : _place,
            child: _placing
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(quote == null
                    ? 'جارٍ الحساب…'
                    : 'أرسل الطلب • ${quote.total.toStringAsFixed(2)} ر.س'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  _Banner(text: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                _AddressSection(
                  addresses: _addresses,
                  selected: _address,
                  onSelect: (a) async {
                    setState(() => _address = a);
                    await _requote();
                  },
                  onAdd: _addAddress,
                ),
                const SizedBox(height: 16),
                _SlotSection(
                  slots: _slots,
                  selected: _slot,
                  onSelect: (s) => setState(() => _slot = s),
                ),
                if (warning != null) ...[
                  const SizedBox(height: 12),
                  _Banner(text: warning, isError: true),
                ],
                const SizedBox(height: 16),
                _CouponSection(
                  controller: _couponCtl,
                  reason: quote?.couponReason,
                  applied: (quote?.discount ?? 0) > 0,
                  onApply: _requote,
                ),
                const SizedBox(height: 16),
                if (_loyalty != null && _loyalty!.balance > 0) ...[
                  _LoyaltySection(
                    state: _loyalty!,
                    use: _useLoyalty,
                    onChanged: (v) => setState(() => _useLoyalty = v),
                  ),
                  const SizedBox(height: 16),
                ],
                _PaymentSection(
                  value: _payment,
                  cardAvailable: _cardAvailable,
                  onChanged: (v) => setState(() => _payment = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياريّ)',
                    hintText: 'بقعة على الثوب الأبيض…',
                  ),
                ),
                const SizedBox(height: 20),
                _SummaryCard(
                  cart: cart,
                  quote: quote,
                  loyaltyRiyal: _useLoyalty && (_loyalty?.canRedeem ?? false)
                      ? _loyalty!.redeemableRiyal
                      : 0,
                ),
              ],
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: isError
                  ? scheme.onErrorContainer
                  : scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: isError
                        ? scheme.onErrorContainer
                        : scheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({
    required this.addresses,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Address> addresses;
  final Address? selected;
  final void Function(Address) onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('عنوان الاستلام',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('عنوان'),
                ),
              ],
            ),
            if (addresses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('لا عنوان بعد — أضِف واحدًا للمتابعة.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else
              RadioGroup<String>(
                groupValue: selected?.id,
                onChanged: (v) {
                  final a = addresses.firstWhere((x) => x.id == v);
                  onSelect(a);
                },
                child: Column(
                  children: [
                    for (final a in addresses)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: a.id,
                        title: Row(
                          children: [
                            Text(a.kind.labelAr,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (a.isHotel)
                              Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(start: 6),
                                child: Icon(Icons.hotel_outlined,
                                    size: 16,
                                    color: Theme.of(context).hintColor),
                              ),
                          ],
                        ),
                        subtitle: Text(a.summary),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlotSection extends StatelessWidget {
  const _SlotSection({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  final List<BookingSlot> slots;
  final BookingSlot? selected;
  final void Function(BookingSlot) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = slots.where((s) => s.isAvailable).toList();

    // «لا مواعيد» شاشةٌ يائسة. وسببُ أوّل فتحةٍ مغلقة يقول للعميل **متى** يعود.
    if (available.isEmpty) {
      final reason = slots.isEmpty
          ? 'الفرع مغلق في الأيام القادمة.'
          : (slots.first.blockedReason ?? 'لا فتحات متاحة.');
      return Card(
        child: ListTile(
          leading: Icon(Icons.event_busy_outlined, color: scheme.error),
          title: const Text('لا مواعيد متاحة'),
          subtitle: Text(reason),
        ),
      );
    }

    final byDay = <String, List<BookingSlot>>{};
    for (final s in available) {
      final key = DateFormat('EEEE، d MMMM', 'ar').format(s.start);
      byDay.putIfAbsent(key, () => []).add(s);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('موعد الاستلام',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('المواعيد المعروضة متاحةٌ فعلًا — محسوبةٌ من طاقة الفرع.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final entry in byDay.entries) ...[
              Text(entry.key,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in entry.value)
                    ChoiceChip(
                      label: Text(
                        '${DateFormat('HH:mm').format(s.start)} — '
                        '${DateFormat('HH:mm').format(s.end)}',
                        textDirection: TextDirection.ltr,
                      ),
                      selected: selected?.start == s.start,
                      onSelected: (_) => onSelect(s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _CouponSection extends StatelessWidget {
  const _CouponSection({
    required this.controller,
    required this.reason,
    required this.applied,
    required this.onApply,
  });

  final TextEditingController controller;
  final String? reason;
  final bool applied;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'كوبون خصم',
                suffixIcon: TextButton(
                    onPressed: onApply, child: const Text('تطبيق')),
              ),
              onSubmitted: (_) => onApply(),
            ),
            // سببُ الرفض يُقال بعينه: «غير صالح» تجعله يعيد الكتابة ظنًّا أنه
            // أخطأ، و«انتهت صلاحيته» تُنهي المحاولة.
            if (reason != null && reason!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      applied ? Icons.check_circle_outline : Icons.info_outline,
                      size: 16,
                      color: applied ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(reason!,
                          style: TextStyle(
                              fontSize: 13,
                              color: applied ? scheme.primary : scheme.error)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.value,
    required this.onChanged,
    this.cardAvailable = false,
  });

  final PaymentMethod value;
  final void Function(PaymentMethod) onChanged;

  /// **الخيار يُعرض إن كان يعمل**: البطاقة لا تظهر إلا إذا كان في الكتالوج
  /// مزوّدٌ نشطٌ يقبلها. وعرضُ خيارٍ يفشل عند الضغط أسوأ من إخفائه.
  final bool cardAvailable;

  List<PaymentMethod> get _available => [
        PaymentMethod.cashOnDelivery,
        PaymentMethod.cashOnPickup,
        if (cardAvailable) PaymentMethod.card,
      ];

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الدفع',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<PaymentMethod>(
                groupValue: value,
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                child: Column(
                  children: [
                    for (final m in _available)
                      RadioListTile<PaymentMethod>(
                        contentPadding: EdgeInsets.zero,
                        value: m,
                        title: Text(m.labelAr),
                      ),
                  ],
                ),
              ),
              Text(
                cardAvailable
                    ? 'الدفع بالبطاقة يفتح صفحةً آمنة من مزوّد الدفع — ولا تمرّ '
                        'بيانات بطاقتك على تطبيقنا.'
                    : 'الدفع بالبطاقة يُفعَّل عند ربط بوّابة الدفع.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.cart,
    required this.quote,
    this.loyaltyRiyal = 0,
  });

  final Cart cart;
  final CheckoutQuote? quote;

  /// خصمُ النقاط. **يُطرح من الإجماليّ المعروض**: عميلٌ يرى ٢١٥ ثم يُخصم منه
  /// ١١٥ يظنّ أن شيئًا اختلّ — ولو كان لصالحه.
  final double loyaltyRiyal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget line(String label, double value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight:
                              bold ? FontWeight.w800 : FontWeight.w400))),
              Text('${value.toStringAsFixed(2)} ر.س',
                  style: TextStyle(
                      fontSize: bold ? 16 : 14,
                      fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الملخّص',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final l in cart.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.service.nameAr} × '
                        '${l.quantity.toStringAsFixed(l.service.unit == PricingUnit.kilogram ? 1 : 0)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text('${l.lineTotal.toStringAsFixed(2)} ر.س',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            const Divider(height: 24),
            line('المجموع', cart.subtotal),
            if (quote != null) ...[
              line('التوصيل', quote!.deliveryFee),
              // سببُ الرسم يُعرض دائمًا: الرقم بلا سببه يُترك، وشكواه تصل الدعم.
              if (quote!.deliveryReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(quote!.deliveryReason!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (quote!.discount > 0) line('الخصم', -quote!.discount),
              if (quote!.vatAmount > 0)
                line('ضريبة القيمة المضافة', quote!.vatAmount),
              if (loyaltyRiyal > 0) line('خصم النقاط', -loyaltyRiyal),
              const SizedBox(height: 4),
              line('الإجمالي',
                  (quote!.total - loyaltyRiyal).clamp(0, double.infinity),
                  bold: true),
              if (!quote!.serviceable)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    quote!.deliveryReason ?? 'الموقع خارج نطاق الخدمة',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('جارٍ حساب التوصيل…'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({
    required this.userId,
    required this.defaultLat,
    required this.defaultLng,
  });

  final String userId;
  final double defaultLat;
  final double defaultLng;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _label = TextEditingController();
  final _district = TextEditingController();
  final _street = TextEditingController();
  final _building = TextEditingController();
  final _hotel = TextEditingController();
  final _room = TextEditingController();
  AddressKind _kind = AddressKind.home;
  DateTime? _checkout;

  /// الموقع المختار. يبدأ من الفرع لا من الصفر: نقطةٌ في المدينة أصدقُ بدايةً
  /// من نقطةٍ في المحيط، والعميل يحرّكها خطوةً واحدة.
  late LatLng _at = LatLng(widget.defaultLat, widget.defaultLng);
  bool _picked = false;

  @override
  void dispose() {
    for (final c in [_label, _district, _street, _building, _hotel, _room]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initial: _at,
          branchAt: LatLng(widget.defaultLat, widget.defaultLng),
          title: 'موقع الاستلام',
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _at = picked;
      _picked = true;
    });
  }

  bool get _valid {
    if (_kind == AddressKind.hotel) {
      return _hotel.text.trim().isNotEmpty && _room.text.trim().isNotEmpty;
    }
    return _district.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isHotel = _kind == AddressKind.hotel;

    return AlertDialog(
      title: const Text('عنوان جديد'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<AddressKind>(
                segments: [
                  for (final k in AddressKind.values)
                    ButtonSegment(value: k, label: Text(k.labelAr)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),

              // وضع الزائر: من يزور المدينة لا يعرف حيًّا ولا شارعًا — يعرف
              // فندقه وغرفته وموعد مغادرته. فيُسأل عمّا يعرف.
              if (isHotel) ...[
                TextField(
                  controller: _hotel,
                  decoration: const InputDecoration(labelText: 'اسم الفندق'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _room,
                  decoration: const InputDecoration(labelText: 'رقم الغرفة'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاريخ المغادرة'),
                  subtitle: Text(_checkout == null
                      ? 'اختياريّ — لكنه يمنع وعدًا بعد سفرك'
                      : DateFormat('yyyy-MM-dd').format(_checkout!)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: now.add(const Duration(days: 3)),
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 120)),
                      );
                      if (picked != null) setState(() => _checkout = picked);
                    },
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                      labelText: 'اسم العنوان (اختياريّ)',
                      hintText: 'بيت أهلي'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _district,
                  decoration: const InputDecoration(labelText: 'الحيّ'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _street,
                  decoration: const InputDecoration(
                      labelText: 'الشارع (اختياريّ)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _building,
                  decoration: const InputDecoration(
                      labelText: 'المبنى/الشقّة (اختياريّ)'),
                ),
              ],

              const SizedBox(height: 16),
              // **الموقع ليس حقلًا اختياريًّا**: رسمُ التوصيل يُحسب منه، ومن
              // يقبل موقع الفرع افتراضًا يُحسب له رسمُ صفر — فيُنبَّه صراحةً.
              OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(_picked ? 'تغيير الموقع' : 'حدّد الموقع على الخريطة'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _picked
                      ? 'الموقع: ${_at.latitude.toStringAsFixed(5)}، '
                          '${_at.longitude.toStringAsFixed(5)}'
                      : 'لم يُحدَّد بعد — سيُحسب الرسم من موقع الفرع، وهو غالبًا خطأ.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _picked
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.pop(
                    context,
                    Address(
                      id: '',
                      userId: widget.userId,
                      kind: _kind,
                      lat: _at.latitude,
                      lng: _at.longitude,
                      label: _label.text.trim().isEmpty
                          ? null
                          : _label.text.trim(),
                      district: _district.text.trim().isEmpty
                          ? null
                          : _district.text.trim(),
                      street: _street.text.trim().isEmpty
                          ? null
                          : _street.text.trim(),
                      building: _building.text.trim().isEmpty
                          ? null
                          : _building.text.trim(),
                      hotelName:
                          isHotel ? _hotel.text.trim() : null,
                      roomNumber: isHotel ? _room.text.trim() : null,
                      checkoutDate: isHotel ? _checkout : null,
                    ),
                  ),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

/// نقاط الولاء عند إتمام الطلب.
///
/// **يُعرض ما يُصرف لا ما يُملَك**: رصيدٌ من ألف نقطةٍ وسقفٌ يسمح بمئةٍ منها
/// يجب أن يُقال صراحةً — وإلّا ظنّ العميل أن نقاطه ضاعت.
class _LoyaltySection extends StatelessWidget {
  const _LoyaltySection({
    required this.state,
    required this.use,
    required this.onChanged,
  });

  final LoyaltyState state;
  final bool use;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: use ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: use && state.canRedeem,
              onChanged: state.canRedeem ? onChanged : null,
              title: Text('ادفع بنقاطك (${state.balance} نقطة)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                state.canRedeem
                    ? 'تُصرف ${state.redeemablePoints} نقطة = '
                        '${state.redeemableRiyal.toStringAsFixed(2)} ر.س من هذه الفاتورة'
                    : (state.reason ?? 'لا تُصرف نقاطٌ على هذه الفاتورة'),
              ),
            ),
            if (state.canRedeem && state.redeemablePoints < state.balance)
              Text(
                'الباقي (${state.balance - state.redeemablePoints} نقطة) يبقى لك '
                'لطلبٍ قادم — للصرف سقفٌ من الفاتورة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
