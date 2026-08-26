import '../models/enums.dart';
import '../models/models.dart';
import 'cart.dart';
import 'supabase_service.dart';

/// نتيجة تسعير السلّة كاملةً — كلّها من القاعدة.
class CheckoutQuote {
  const CheckoutQuote({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.vatAmount,
    required this.total,
    required this.serviceable,
    this.deliveryReason,
    this.couponReason,
    this.couponId,
    this.distanceKm,
  });

  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double vatAmount;
  final double total;
  final bool serviceable;
  final String? deliveryReason;
  final String? couponReason;
  final String? couponId;
  final double? distanceKm;
}

/// عمليات العميل: التصفّح، والتسعير، وإنشاء الطلب.
class CustomerService {
  const CustomerService();

  Future<List<Branch>> branches() async {
    final rows = await Db.client
        .from('branches')
        .select()
        .eq('is_active', true)
        .order('name_ar');
    return (rows as List)
        .map((e) => Branch.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// كتالوج الفرع بالأسعار النافذة فيه.
  ///
  /// **يُسأل عن السعر النافذ لكل خدمة** لا يُعرض `base_price`: الفرع قد يتجاوز
  /// سعر المغسلة، وعرضُ سعرٍ ثم تحصيلُ آخر أسوأ من عدم العرض.
  Future<List<({LaundryService service, double price})>> catalog({
    required String laundryId,
    required String branchId,
  }) async {
    final rows = await Db.client
        .from('services')
        .select('*, branch_services!left(price_override, is_offered, branch_id)')
        .eq('laundry_id', laundryId)
        .eq('is_active', true)
        .order('sort_order');

    final out = <({LaundryService service, double price})>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final service = LaundryService.fromMap(r);

      // التجاوز يُقرأ من الضمّ مباشرةً بدل نداءٍ لكل خدمة: ثمانية نداءات
      // لثماني خدمات تُبطئ الشاشة الأولى — وهي أوّل ما يراه العميل.
      final overrides = (r['branch_services'] as List?)
              ?.cast<Map<String, dynamic>>()
              .where((b) => b['branch_id'] == branchId)
              .toList() ??
          const [];

      if (overrides.isNotEmpty && overrides.first['is_offered'] == false) {
        continue; // الفرع لا يقدّم هذه الخدمة
      }

      final override = overrides.isEmpty ? null : overrides.first['price_override'];
      final price = override == null
          ? service.basePrice
          : (override is num
              ? override.toDouble()
              : double.tryParse('$override') ?? service.basePrice);

      out.add((service: service, price: price));
    }
    return out;
  }

  Future<List<Address>> addresses(String userId) async {
    final rows = await Db.client
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false);
    return (rows as List)
        .map((e) => Address.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Address> addAddress(Address a) async {
    final row = await Db.client
        .from('addresses')
        .insert(a.toInsert())
        .select()
        .single();
    return Address.fromMap(row);
  }

  /// تسعيرة السلّة كاملةً.
  ///
  /// **ثلاثة نداءاتٍ للقاعدة لا حسابٌ واحدٌ هنا**: رسم التوصيل، وخصم الكوبون،
  /// والضريبة. كلٌّ منها له مرجعٌ واحد في القاعدة، والتطبيق يجمع النتائج فقط.
  Future<CheckoutQuote> quote({
    required String laundryId,
    required String branchId,
    required String userId,
    required double subtotal,
    required double lat,
    required double lng,
    String? couponCode,
    bool wantsPickup = true,
    bool wantsDelivery = true,
  }) async {
    final deliveryRows = await Db.client.rpc('quote_delivery_fee', params: {
      'p_branch': branchId,
      'p_point': 'SRID=4326;POINT($lng $lat)',
      'p_subtotal': subtotal,
      'p_wants_pickup': wantsPickup,
      'p_wants_delivery': wantsDelivery,
    });
    final d = (deliveryRows as List).isEmpty
        ? const DeliveryQuote(fee: 0, serviceable: false, reason: 'لا نتيجة')
        : DeliveryQuote.fromMap(
            (deliveryRows).first as Map<String, dynamic>);

    var discount = 0.0;
    String? couponReason;
    String? couponId;

    if (couponCode != null && couponCode.trim().isNotEmpty) {
      final rows = await Db.client.rpc('quote_coupon', params: {
        'p_code': couponCode,
        'p_laundry': laundryId,
        'p_branch': branchId,
        'p_user': userId,
        'p_subtotal': subtotal,
        'p_delivery_fee': d.fee,
      });
      final list = rows as List;
      if (list.isNotEmpty) {
        final m = list.first as Map<String, dynamic>;
        couponReason = m['reason'] as String?;
        if (m['valid'] == true) {
          final v = m['discount'];
          discount = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
          couponId = m['coupon_id'] as String?;
        }
      }
    }

    final taxable = (subtotal + d.fee - discount).clamp(0, double.infinity);
    final vatRows = await Db.client.rpc('compute_vat',
        params: {'p_laundry': laundryId, 'p_taxable': taxable});
    final vatList = vatRows as List;
    final vat = vatList.isEmpty ? null : vatList.first as Map<String, dynamic>;

    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

    return CheckoutQuote(
      subtotal: subtotal,
      deliveryFee: d.fee,
      discount: discount,
      vatAmount: vat == null ? 0 : n(vat['vat_amount']),
      total: vat == null ? taxable.toDouble() : n(vat['total']),
      serviceable: d.serviceable,
      deliveryReason: d.reason,
      couponReason: couponReason,
      couponId: couponId,
      distanceKm: d.distanceKm,
    );
  }

  /// إنشاء الطلب.
  ///
  /// **بأربع خطواتٍ لا واحدة، والترتيب مقصود**:
  ///   ١) الطلب `draft` — وهو ما تسمح سياسة `orders_insert` للعميل بإنشائه.
  ///   ٢) البنود — قبل الموعد، لأن حارس الفتحة يقيس حِملها من البنود.
  ///   ٣) المبالغ والموعد — والمبالغ تُقبل ما دام `draft` (حارس `guard_order_amounts`).
  ///   ٤) `placed` — ومن هنا فصاعدًا لا يعدّل العميل مبلغًا.
  Future<LaundryOrder> placeOrder({
    required String laundryId,
    required String branchId,
    required String customerId,
    required Cart cart,
    required CheckoutQuote quote,
    required String pickupAddressId,
    required String deliveryAddressId,
    required DateTime pickupSlot,
    DateTime? deliverySlot,
    String? couponCode,
    PaymentMethod paymentMethod = PaymentMethod.cashOnDelivery,
    int loyaltyPoints = 0,
    String? notes,
  }) async {
    final orderRow = await Db.client
        .from('orders')
        .insert({
          'laundry_id': laundryId,
          'branch_id': branchId,
          'customer_id': customerId,
          'status': 'draft',
          'payment_method': paymentMethod.wireName,
        })
        .select()
        .single();
    final orderId = orderRow['id'] as String;

    await Db.client.from('order_items').insert([
      for (final l in cart.lines)
        {
          'order_id': orderId,
          'service_id': l.service.id,
          'service_name_ar': l.service.nameAr,
          'unit': l.service.unit.wireName,
          'quantity': l.quantity,
          'unit_price': l.unitPrice,
          'line_total': l.lineTotal,
        }
    ]);

    // وعدُ الجاهزية من أطول مدّة تنفيذٍ في السلّة: الطلب لا يجهز قبل أبطأ
    // خدمةٍ فيه.
    final maxHours = cart.lines.fold<int>(
        0, (m, l) => l.service.turnaroundHours > m ? l.service.turnaroundHours : m);

    await Db.client.from('orders').update({
      'subtotal': quote.subtotal,
      'delivery_fee': quote.deliveryFee,
      'discount_amount': quote.discount,
      'vat_amount': quote.vatAmount,
      'total': quote.total,
      'delivery_fee_reason': quote.deliveryReason,
      'coupon_id': quote.couponId,
      'pickup_address_id': pickupAddressId,
      'delivery_address_id': deliveryAddressId,
      'pickup_slot_start': pickupSlot.toUtc().toIso8601String(),
      if (deliverySlot != null)
        'delivery_slot_start': deliverySlot.toUtc().toIso8601String(),
      'promised_ready_at': pickupSlot
          .add(Duration(hours: maxHours))
          .toUtc()
          .toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty) 'customer_notes': notes.trim(),
    }).eq('id', orderId);

    // صرفُ النقاط قبل الإرسال: بعده تُجمَّد المبالغ فلا يُخصم منها شيء.
    // وقيمتُها تُحسب في القاعدة — ما يُرسل هنا عددُ نقاطٍ لا مبلغ.
    if (loyaltyPoints > 0) {
      await Db.client.rpc('redeem_loyalty_on_order', params: {
        'p_order': orderId,
        'p_points': loyaltyPoints,
      });
    }

    // استهلاك الكوبون يُسجَّل بعد ثبوت الطلب لا قبله: القيد الفريد يحسم
    // السباق، وتسجيلُه على طلبٍ لم يُرسل يستهلكه بلا مقابل.
    if (quote.couponId != null && quote.discount > 0) {
      await Db.client.from('coupon_redemptions').insert({
        'coupon_id': quote.couponId,
        'user_id': customerId,
        'order_id': orderId,
        'amount': quote.discount,
      });
    }

    await Db.client
        .from('orders')
        .update({'status': 'placed'}).eq('id', orderId);

    final finalRow = await Db.client
        .from('orders')
        .select('*, branches!orders_branch_id_fkey(name_ar), order_items(*)')
        .eq('id', orderId)
        .single();
    return LaundryOrder.fromMap(finalRow);
  }

  Future<List<LaundryOrder>> myOrders(String customerId) async {
    final rows = await Db.client
        .from('orders')
        .select('*, branches!orders_branch_id_fkey(name_ar), order_items(*)')
        .eq('customer_id', customerId)
        .neq('status', 'draft')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => LaundryOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
