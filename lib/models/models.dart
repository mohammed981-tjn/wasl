/// نماذج المجال.
///
/// **قاعدةٌ تحكم هذا الملفّ**: لا حساب مالٍ هنا. السعر النافذ ورسم التوصيل
/// وخصم الكوبون تحسبها **القاعدة** عبر دوالّها (`effective_service_price`،
/// `quote_delivery_fee`، `quote_coupon`)، ويعرض التطبيق ما تعيده. ولو حَسَب
/// التطبيق لصار في النظام مرجعان للسعر، وأوّل اختلافٍ بينهما شكوى عميل.
library;

import 'enums.dart';

/// قراءة رقمٍ من JSON قد يعود `int` أو `double` أو نصًّا.
///
/// وهذا ليس تزيُّدًا: أعمدة `numeric` في Postgres تصل عبر PostgREST **نصًّا**
/// حفاظًا على الدقّة، بينما `int` تصل عددًا. فالقراءة المباشرة `as double`
/// تنفجر على أوّل مبلغ.
double _num(dynamic v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

int _int(dynamic v) => switch (v) {
      null => 0,
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v as String)?.toLocal();

class Laundry {
  const Laundry({
    required this.id,
    required this.nameAr,
    required this.slug,
    this.logoUrl,
    this.vatNumber,
    this.isActive = true,
  });

  final String id;
  final String nameAr;
  final String slug;
  final String? logoUrl;
  final String? vatNumber;
  final bool isActive;

  factory Laundry.fromMap(Map<String, dynamic> m) => Laundry(
        id: m['id'] as String,
        nameAr: m['name_ar'] as String,
        slug: m['slug'] as String,
        logoUrl: m['logo_url'] as String?,
        vatNumber: m['vat_number'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );
}

class Branch {
  const Branch({
    required this.id,
    required this.laundryId,
    required this.nameAr,
    required this.city,
    this.phone,
    this.dailyCapacityPieces = 0,
    this.isActive = true,
    this.lat,
    this.lng,
  });

  final String id;
  final String laundryId;
  final String nameAr;
  final String city;
  final String? phone;

  /// من العمودين المشتقّين `lat`/`lng` — لا من `location`، فهي تصل نصًّا
  /// سداسيًّا لا رقمًا.
  final double? lat;
  final double? lng;

  /// صفر يعني «بلا سقف» — لا «لا طاقة».
  final int dailyCapacityPieces;
  final bool isActive;

  bool get hasCapacityLimit => dailyCapacityPieces > 0;

  factory Branch.fromMap(Map<String, dynamic> m) => Branch(
        id: m['id'] as String,
        laundryId: m['laundry_id'] as String,
        nameAr: m['name_ar'] as String,
        city: m['city'] as String? ?? 'المدينة المنورة',
        phone: m['phone'] as String?,
        dailyCapacityPieces: _int(m['daily_capacity_pieces']),
        isActive: m['is_active'] as bool? ?? true,
        lat: m['lat'] == null ? null : _num(m['lat']),
        lng: m['lng'] == null ? null : _num(m['lng']),
      );
}

class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.laundryId,
    required this.nameAr,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String laundryId;
  final String nameAr;
  final int sortOrder;
  final bool isActive;

  factory ServiceCategory.fromMap(Map<String, dynamic> m) => ServiceCategory(
        id: m['id'] as String,
        laundryId: m['laundry_id'] as String,
        nameAr: m['name_ar'] as String,
        sortOrder: _int(m['sort_order']),
        isActive: m['is_active'] as bool? ?? true,
      );
}

/// خدمةٌ في الكتالوج.
///
/// [basePrice] سعر المغسلة. وسعرُ الفرع قد يخالفه عبر `branch_services` —
/// ولذلك **لا تُعرض هذه القيمة على عميل**: تُسأل القاعدة عن السعر النافذ.
class LaundryService {
  const LaundryService({
    required this.id,
    required this.laundryId,
    required this.nameAr,
    required this.unit,
    required this.basePrice,
    required this.turnaroundHours,
    this.categoryId,
    this.descriptionAr,
    this.minQuantity = 0,
    this.expressMultiplier = 1.0,
    this.expressTurnaroundHours,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String laundryId;
  final String? categoryId;
  final String nameAr;
  final String? descriptionAr;
  final PricingUnit unit;
  final double basePrice;
  final int turnaroundHours;
  final double minQuantity;

  /// 1.0 يعني «هذه الخدمة لا تقبل الاستعجال».
  final double expressMultiplier;
  final int? expressTurnaroundHours;
  final bool isActive;
  final int sortOrder;

  bool get acceptsExpress => expressMultiplier > 1.0;

  factory LaundryService.fromMap(Map<String, dynamic> m) => LaundryService(
        id: m['id'] as String,
        laundryId: m['laundry_id'] as String,
        categoryId: m['category_id'] as String?,
        nameAr: m['name_ar'] as String,
        descriptionAr: m['description_ar'] as String?,
        unit: PricingUnit.fromWire(m['unit'] as String),
        basePrice: _num(m['base_price']),
        turnaroundHours: _int(m['turnaround_hours']),
        minQuantity: _num(m['min_quantity']),
        expressMultiplier: _num(m['express_multiplier']),
        expressTurnaroundHours: m['express_turnaround_hours'] == null
            ? null
            : _int(m['express_turnaround_hours']),
        isActive: m['is_active'] as bool? ?? true,
        sortOrder: _int(m['sort_order']),
      );

  Map<String, dynamic> toInsert() => {
        'laundry_id': laundryId,
        if (categoryId != null) 'category_id': categoryId,
        'name_ar': nameAr,
        if (descriptionAr != null) 'description_ar': descriptionAr,
        'unit': unit.wireName,
        'base_price': basePrice,
        'turnaround_hours': turnaroundHours,
        'min_quantity': minQuantity,
        'express_multiplier': expressMultiplier,
        if (expressTurnaroundHours != null)
          'express_turnaround_hours': expressTurnaroundHours,
        'is_active': isActive,
        'sort_order': sortOrder,
      };

  LaundryService copyWith({
    String? nameAr,
    String? descriptionAr,
    PricingUnit? unit,
    double? basePrice,
    int? turnaroundHours,
    double? minQuantity,
    double? expressMultiplier,
    int? expressTurnaroundHours,
    bool? isActive,
    String? categoryId,
  }) =>
      LaundryService(
        id: id,
        laundryId: laundryId,
        categoryId: categoryId ?? this.categoryId,
        nameAr: nameAr ?? this.nameAr,
        descriptionAr: descriptionAr ?? this.descriptionAr,
        unit: unit ?? this.unit,
        basePrice: basePrice ?? this.basePrice,
        turnaroundHours: turnaroundHours ?? this.turnaroundHours,
        minQuantity: minQuantity ?? this.minQuantity,
        expressMultiplier: expressMultiplier ?? this.expressMultiplier,
        expressTurnaroundHours:
            expressTurnaroundHours ?? this.expressTurnaroundHours,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder,
      );
}

/// إعدادات التوصيل لفرع. القيم كلّها تعدّلها الإدارة.
class DeliverySettings {
  const DeliverySettings({
    required this.branchId,
    required this.strategy,
    this.flatPickupFee = 0,
    this.flatDeliveryFee = 0,
    this.combinedFee,
    this.freeAboveSubtotal,
    this.maxRadiusKm = 15,
    this.minOrderSubtotal = 0,
  });

  final String branchId;
  final DeliveryStrategy strategy;
  final double flatPickupFee;
  final double flatDeliveryFee;

  /// رسم الرحلتين معًا. `null` = اجمع الرسمين. هنا يسكن «الاثنان بـ١٥ لا ١٦».
  final double? combinedFee;

  /// `null` = لا إعفاء مهما بلغ الطلب.
  final double? freeAboveSubtotal;
  final double maxRadiusKm;
  final double minOrderSubtotal;

  factory DeliverySettings.fromMap(Map<String, dynamic> m) => DeliverySettings(
        branchId: m['branch_id'] as String,
        strategy: DeliveryStrategy.fromWire(m['strategy'] as String),
        flatPickupFee: _num(m['flat_pickup_fee']),
        flatDeliveryFee: _num(m['flat_delivery_fee']),
        combinedFee:
            m['combined_fee'] == null ? null : _num(m['combined_fee']),
        freeAboveSubtotal: m['free_above_subtotal'] == null
            ? null
            : _num(m['free_above_subtotal']),
        maxRadiusKm: _num(m['max_radius_km']),
        minOrderSubtotal: _num(m['min_order_subtotal']),
      );

  Map<String, dynamic> toUpsert() => {
        'branch_id': branchId,
        'strategy': strategy.wireName,
        'flat_pickup_fee': flatPickupFee,
        'flat_delivery_fee': flatDeliveryFee,
        'combined_fee': combinedFee,
        'free_above_subtotal': freeAboveSubtotal,
        'max_radius_km': maxRadiusKm,
        'min_order_subtotal': minOrderSubtotal,
      };
}

class DistanceTier {
  const DistanceTier({
    required this.id,
    required this.branchId,
    required this.fromKm,
    required this.toKm,
    required this.pickupFee,
    required this.deliveryFee,
  });

  final String id;
  final String branchId;
  final double fromKm;
  final double toKm;
  final double pickupFee;
  final double deliveryFee;

  factory DistanceTier.fromMap(Map<String, dynamic> m) => DistanceTier(
        id: m['id'] as String,
        branchId: m['branch_id'] as String,
        fromKm: _num(m['from_km']),
        toKm: _num(m['to_km']),
        pickupFee: _num(m['pickup_fee']),
        deliveryFee: _num(m['delivery_fee']),
      );
}

/// بند في طلب. الاسم والسعر **منسوخان** لا مرجعان: الفاتورة وثيقة، وحذفُ خدمة
/// من الكتالوج غدًا يجب ألّا يُفرغ فاتورةَ أمس.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.serviceNameAr,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.serviceId,
    this.notes,
  });

  final String id;
  final String orderId;
  final String? serviceId;
  final String serviceNameAr;
  final PricingUnit unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? notes;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        serviceId: m['service_id'] as String?,
        serviceNameAr: m['service_name_ar'] as String,
        unit: PricingUnit.fromWire(m['unit'] as String),
        quantity: _num(m['quantity']),
        unitPrice: _num(m['unit_price']),
        lineTotal: _num(m['line_total']),
        notes: m['notes'] as String?,
      );
}

class LaundryOrder {
  const LaundryOrder({
    required this.id,
    required this.orderNumber,
    required this.laundryId,
    required this.branchId,
    required this.customerId,
    required this.status,
    required this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    required this.discountAmount,
    required this.vatAmount,
    required this.total,
    required this.createdAt,
    this.isExpress = false,
    this.barcode,
    this.customerNotes,
    this.pickupSlotStart,
    this.deliverySlotStart,
    this.promisedReadyAt,
    this.placedAt,
    this.deliveredAt,
    this.pickupDriverId,
    this.deliveryDriverId,
    this.customerName,
    this.branchName,
    this.items = const [],
  });

  final String id;
  final int orderNumber;
  final String laundryId;
  final String branchId;
  final String customerId;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final double subtotal;
  final double deliveryFee;
  final double discountAmount;
  final double vatAmount;
  final double total;
  final bool isExpress;
  final String? barcode;
  final String? customerNotes;
  final DateTime? pickupSlotStart;
  final DateTime? deliverySlotStart;
  final DateTime? promisedReadyAt;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final String? pickupDriverId;
  final String? deliveryDriverId;

  /// يُملأ حين يُجلب الطلب بضمّ الملفّ الشخصي — وقد يبقى فارغًا لمن لا تسمح له
  /// سياسة `profiles_read` برؤية العميل.
  final String? customerName;
  final String? branchName;
  final List<OrderItem> items;

  /// الطلب متأخّر: وُعِد بالجاهزية ولم يجهز.
  bool get isLate =>
      promisedReadyAt != null &&
      !status.isTerminal &&
      status.index < OrderStatus.ready.index &&
      DateTime.now().isAfter(promisedReadyAt!);

  factory LaundryOrder.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    final branch = m['branches'];
    return LaundryOrder(
      id: m['id'] as String,
      orderNumber: _int(m['order_number']),
      laundryId: m['laundry_id'] as String,
      branchId: m['branch_id'] as String,
      customerId: m['customer_id'] as String,
      status: OrderStatus.fromWire(m['status'] as String),
      paymentStatus: PaymentStatus.fromWire(m['payment_status'] as String),
      subtotal: _num(m['subtotal']),
      deliveryFee: _num(m['delivery_fee']),
      discountAmount: _num(m['discount_amount']),
      vatAmount: _num(m['vat_amount']),
      total: _num(m['total']),
      isExpress: m['is_express'] as bool? ?? false,
      barcode: m['barcode'] as String?,
      customerNotes: m['customer_notes'] as String?,
      pickupSlotStart: _date(m['pickup_slot_start']),
      deliverySlotStart: _date(m['delivery_slot_start']),
      promisedReadyAt: _date(m['promised_ready_at']),
      placedAt: _date(m['placed_at']),
      deliveredAt: _date(m['delivered_at']),
      createdAt: _date(m['created_at']) ?? DateTime.now(),
      pickupDriverId: m['pickup_driver_id'] as String?,
      deliveryDriverId: m['delivery_driver_id'] as String?,
      customerName: profile is Map ? profile['full_name'] as String? : null,
      branchName: branch is Map ? branch['name_ar'] as String? : null,
      items: (m['order_items'] as List?)
              ?.map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// دورُ مستخدمٍ في نطاقه. `branchId` فارغٌ لـ`super_admin` و`customer` وحدهما.
class UserRoleAssignment {
  const UserRoleAssignment({
    required this.role,
    this.laundryId,
    this.branchId,
    this.branchName,
  });

  final AppRole role;
  final String? laundryId;
  final String? branchId;
  final String? branchName;

  factory UserRoleAssignment.fromMap(Map<String, dynamic> m) {
    final branch = m['branches'];
    return UserRoleAssignment(
      role: AppRole.fromWire(m['role'] as String),
      laundryId: m['laundry_id'] as String?,
      branchId: m['branch_id'] as String?,
      branchName: branch is Map ? branch['name_ar'] as String? : null,
    );
  }
}

/// فتحة موعدٍ كما تعيدها `available_slots`.
class BookingSlot {
  const BookingSlot({
    required this.start,
    required this.end,
    required this.isAvailable,
    required this.ordersBooked,
    required this.piecesBooked,
    this.blockedReason,
  });

  final DateTime start;
  final DateTime end;
  final bool isAvailable;
  final int ordersBooked;
  final double piecesBooked;

  /// سببُ الإغلاق. **يُعرض للعميل**: «ممتلئ اليوم — جرّب الغد» تبيع، و«لا
  /// مواعيد» لا.
  final String? blockedReason;

  factory BookingSlot.fromMap(Map<String, dynamic> m) => BookingSlot(
        start: _date(m['slot_start'])!,
        end: _date(m['slot_end'])!,
        isAvailable: m['is_available'] as bool? ?? false,
        ordersBooked: _int(m['orders_booked']),
        piecesBooked: _num(m['pieces_booked']),
        blockedReason: m['blocked_reason'] as String?,
      );
}

/// نتيجة تسعير التوصيل كما تعيدها `quote_delivery_fee`.
class DeliveryQuote {
  const DeliveryQuote({
    required this.fee,
    required this.serviceable,
    this.distanceKm,
    this.zoneId,
    this.reason,
  });

  final double fee;
  final bool serviceable;
  final double? distanceKm;
  final String? zoneId;

  /// سببُ الرسم. العميل الذي يرى رقمًا لا يفهمه يترك السلّة.
  final String? reason;

  factory DeliveryQuote.fromMap(Map<String, dynamic> m) => DeliveryQuote(
        fee: _num(m['fee']),
        serviceable: m['serviceable'] as bool? ?? false,
        distanceKm:
            m['distance_km'] == null ? null : _num(m['distance_km']),
        zoneId: m['zone_id'] as String?,
        reason: m['reason'] as String?,
      );
}

/// حدثٌ في سجلّ الطلب.
///
/// السجلّ يكتبه محفّز القاعدة في المعاملة نفسها، لا التطبيق — فأوّل استثناء لا
/// يترك طلبًا انتقل بلا أثر. وهذا ما يجعل الخلاف مع العميل يُحسم بسجلّ لا
/// بذاكرة.
class OrderEvent {
  const OrderEvent({
    required this.id,
    required this.orderId,
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
    this.actorName,
    this.actorRole,
    this.note,
  });

  final String id;
  final String orderId;
  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final DateTime createdAt;

  /// فارغٌ حين ينفّذ الحدثَ الخادمُ نفسه — أي «النظام»، لا انتحالًا لشخص.
  final String? actorName;
  final AppRole? actorRole;
  final String? note;

  factory OrderEvent.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return OrderEvent(
      id: m['id'] as String,
      orderId: m['order_id'] as String,
      fromStatus: m['from_status'] == null
          ? null
          : OrderStatus.fromWire(m['from_status'] as String),
      toStatus: OrderStatus.fromWire(m['to_status'] as String),
      createdAt: _date(m['created_at']) ?? DateTime.now(),
      actorName: profile is Map ? profile['full_name'] as String? : null,
      actorRole: m['actor_role'] == null
          ? null
          : AppRole.fromWire(m['actor_role'] as String),
      note: m['note'] as String?,
    );
  }
}

/// كوبون خصم.
///
/// **الحدود هي جوهره لا قيمته**: كوبونٌ بلا سقف يُنشر في مجموعة واتساب
/// فيُستهلك آلافًا في ساعة، وكوبونُ نسبةٍ بلا `maxDiscount` يبتلع فاتورة
/// سجّادٍ بألف ريال.
class Coupon {
  const Coupon({
    required this.id,
    required this.laundryId,
    required this.code,
    required this.kind,
    required this.value,
    required this.isActive,
    this.maxDiscount,
    this.minSubtotal = 0,
    this.startsAt,
    this.endsAt,
    this.maxUsesTotal = 0,
    this.maxUsesPerUser = 1,
    this.branchId,
    this.firstOrderOnly = false,
    this.redemptions = 0,
  });

  final String id;
  final String laundryId;
  final String code;
  final CouponKind kind;
  final double value;
  final double? maxDiscount;
  final double minSubtotal;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// صفر = بلا حدّ.
  final int maxUsesTotal;
  final int maxUsesPerUser;

  /// فارغٌ = يشمل كل الفروع.
  final String? branchId;
  final bool firstOrderOnly;
  final bool isActive;

  /// عدد مرّات الاستهلاك الفعليّ — محسوبٌ من `coupon_redemptions` لا من عدّاد.
  final int redemptions;

  bool get isExpired => endsAt != null && DateTime.now().isAfter(endsAt!);
  bool get isExhausted => maxUsesTotal > 0 && redemptions >= maxUsesTotal;

  /// «هل يعمل الآن؟» — سؤالٌ واحدٌ يجمع كل الأسباب.
  bool get isLive => isActive && !isExpired && !isExhausted &&
      (startsAt == null || DateTime.now().isAfter(startsAt!));

  String get valueLabel => switch (kind) {
        CouponKind.percentage => '${value.toStringAsFixed(0)}٪',
        CouponKind.fixed => '${value.toStringAsFixed(2)} ر.س',
        CouponKind.freeDelivery => 'توصيل مجاني',
      };

  factory Coupon.fromMap(Map<String, dynamic> m) {
    // PostgREST يعيد العدّ المضموم قائمةً فيها كائنٌ واحد.
    final counts = m['coupon_redemptions'];
    final used = counts is List && counts.isNotEmpty
        ? _int((counts.first as Map)['count'])
        : 0;
    return Coupon(
      id: m['id'] as String,
      laundryId: m['laundry_id'] as String,
      code: m['code'] as String,
      kind: CouponKind.fromWire(m['kind'] as String),
      value: _num(m['value']),
      maxDiscount:
          m['max_discount'] == null ? null : _num(m['max_discount']),
      minSubtotal: _num(m['min_subtotal']),
      startsAt: _date(m['starts_at']),
      endsAt: _date(m['ends_at']),
      maxUsesTotal: _int(m['max_uses_total']),
      maxUsesPerUser: _int(m['max_uses_per_user']),
      branchId: m['branch_id'] as String?,
      firstOrderOnly: m['first_order_only'] as bool? ?? false,
      isActive: m['is_active'] as bool? ?? true,
      redemptions: used,
    );
  }

  Map<String, dynamic> toUpsert() => {
        'laundry_id': laundryId,
        'code': code.trim().toUpperCase(),
        'kind': kind.wireName,
        'value': value,
        'max_discount': maxDiscount,
        'min_subtotal': minSubtotal,
        if (startsAt != null) 'starts_at': startsAt!.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'max_uses_total': maxUsesTotal,
        'max_uses_per_user': maxUsesPerUser,
        'branch_id': branchId,
        'first_order_only': firstOrderOnly,
        'is_active': isActive,
      };
}

/// ساعات عمل يومٍ واحد.
class BranchHours {
  const BranchHours({
    required this.weekday,
    required this.opensAt,
    required this.closesAt,
    required this.isClosed,
    this.id,
  });

  final String? id;

  /// ٠ = الأحد، موافقًا لـ`extract(dow)` في Postgres.
  final int weekday;
  final String opensAt;
  final String closesAt;
  final bool isClosed;

  static const weekdayNames = [
    'الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء',
    'الخميس', 'الجمعة', 'السبت',
  ];

  String get dayNameAr => weekdayNames[weekday];

  factory BranchHours.fromMap(Map<String, dynamic> m) => BranchHours(
        id: m['id'] as String?,
        weekday: _int(m['weekday']),
        // `time` يصل «08:00:00» — والدقائق وحدها هي ما يُعرض.
        opensAt: (m['opens_at'] as String).substring(0, 5),
        closesAt: (m['closes_at'] as String).substring(0, 5),
        isClosed: m['is_closed'] as bool? ?? false,
      );

  Map<String, dynamic> toUpsert(String branchId) => {
        'branch_id': branchId,
        'weekday': weekday,
        'opens_at': '$opensAt:00',
        'closes_at': '$closesAt:00',
        'is_closed': isClosed,
      };

  BranchHours copyWith({String? opensAt, String? closesAt, bool? isClosed}) =>
      BranchHours(
        id: id,
        weekday: weekday,
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
        isClosed: isClosed ?? this.isClosed,
      );
}

/// إعدادات الحجز — تغذّي محرّك «أقرب موعد متاح».
class BookingSettings {
  const BookingSettings({
    required this.branchId,
    this.slotMinutes = 60,
    this.leadTimeMinutes = 120,
    this.horizonDays = 7,
    this.maxOrdersPerSlot = 0,
    this.maxPiecesPerSlot = 0,
    this.cutoffBeforeCloseMinutes = 30,
  });

  final String branchId;
  final int slotMinutes;

  /// صفرٌ يعني فتحةً بدأت قبل دقيقة — وهو عطلٌ لا إعداد.
  final int leadTimeMinutes;
  final int horizonDays;

  /// صفر = بلا سقف.
  final int maxOrdersPerSlot;
  final int maxPiecesPerSlot;
  final int cutoffBeforeCloseMinutes;

  factory BookingSettings.fromMap(Map<String, dynamic> m) => BookingSettings(
        branchId: m['branch_id'] as String,
        slotMinutes: _int(m['slot_minutes']),
        leadTimeMinutes: _int(m['lead_time_minutes']),
        horizonDays: _int(m['horizon_days']),
        maxOrdersPerSlot: _int(m['max_orders_per_slot']),
        maxPiecesPerSlot: _int(m['max_pieces_per_slot']),
        cutoffBeforeCloseMinutes: _int(m['cutoff_before_close_minutes']),
      );

  Map<String, dynamic> toUpsert() => {
        'branch_id': branchId,
        'slot_minutes': slotMinutes,
        'lead_time_minutes': leadTimeMinutes,
        'horizon_days': horizonDays,
        'max_orders_per_slot': maxOrdersPerSlot,
        'max_pieces_per_slot': maxPiecesPerSlot,
        'cutoff_before_close_minutes': cutoffBeforeCloseMinutes,
      };
}

/// قالب رسالة.
///
/// **النصّ صفٌّ لا سلسلةٌ في Dart**: تغييرُ «تم استلام ملابسك» إلى صيغة صاحب
/// المغسلة لا يحتاج إصدارًا على المتجر. والقالب مربوطٌ بحالة الطلب لا باسمٍ
/// حرّ، فحالةٌ تُضاف غدًا يكشف الجدول فراغَ قالبها.
class NotificationTemplate {
  const NotificationTemplate({
    required this.id,
    required this.laundryId,
    required this.triggerStatus,
    required this.channel,
    required this.audience,
    required this.bodyAr,
    this.titleAr,
    this.isActive = true,
  });

  final String id;
  final String laundryId;
  final OrderStatus triggerStatus;
  final NotificationChannel channel;
  final AppRole audience;
  final String? titleAr;
  final String bodyAr;
  final bool isActive;

  /// المتغيّرات المتاحة — تُعرض للمحرّر كي لا يخمّن أسماءها.
  static const variables = ['رقم_الطلب', 'الفرع', 'الإجمالي'];

  /// معاينةٌ بقيمٍ نموذجية. **تُحسب هنا لا في القاعدة** لأنها معاينةُ نصٍّ لا
  /// حسابُ مال: لا مرجع ينحرف.
  String preview() {
    var out = bodyAr;
    const sample = {
      'رقم_الطلب': '10042',
      'الفرع': 'فرع المركز',
      'الإجمالي': '115.00',
    };
    sample.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  factory NotificationTemplate.fromMap(Map<String, dynamic> m) =>
      NotificationTemplate(
        id: m['id'] as String,
        laundryId: m['laundry_id'] as String,
        triggerStatus: OrderStatus.fromWire(m['trigger_status'] as String),
        channel: NotificationChannel.fromWire(m['channel'] as String),
        audience: AppRole.fromWire(m['audience'] as String),
        titleAr: m['title_ar'] as String?,
        bodyAr: m['body_ar'] as String,
        isActive: m['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toUpsert() => {
        'laundry_id': laundryId,
        'trigger_status': triggerStatus.wireName,
        'channel': channel.wireName,
        'audience': audience.wireName,
        'title_ar': titleAr,
        'body_ar': bodyAr,
        'is_active': isActive,
      };
}

/// عنوان.
///
/// **وضع الزائر ليس حقلًا إضافيًّا بل حالةً كاملة**: المدينة المنورة ليست مدينة
/// سكّان فحسب، والحاجّ ونزيل الفندق لا يعرف عنوانًا ولا اسم شارع — يعرف اسم
/// فندقه ورقم غرفته وموعد مغادرته. والأخير قيدٌ على وعد التسليم: لا يجوز أن
/// يَعِد النظام بتسليمٍ بعد أن يغادر صاحبه المدينة.
class Address {
  const Address({
    required this.id,
    required this.userId,
    required this.kind,
    required this.lat,
    required this.lng,
    this.label,
    this.street,
    this.district,
    this.city = 'المدينة المنورة',
    this.building,
    this.notes,
    this.hotelName,
    this.roomNumber,
    this.checkoutDate,
    this.isDefault = false,
  });

  final String id;
  final String userId;
  final AddressKind kind;
  final double lat;
  final double lng;
  final String? label;
  final String? street;
  final String? district;
  final String city;
  final String? building;
  final String? notes;
  final String? hotelName;
  final String? roomNumber;
  final DateTime? checkoutDate;
  final bool isDefault;

  bool get isHotel => kind == AddressKind.hotel;

  /// سطرٌ واحد يُقرأ في قائمة — لا حقولٌ مبعثرة.
  String get summary {
    if (isHotel) {
      return [hotelName, if (roomNumber != null) 'غرفة $roomNumber']
          .whereType<String>()
          .join(' — ');
    }
    return [label, district, street, building]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join('، ');
  }

  /// «هل يغادر قبل أن يجهز الطلب؟» — سؤالٌ يجب أن يُطرح قبل الوعد لا بعده.
  bool leavesBefore(DateTime when) =>
      checkoutDate != null && when.isAfter(checkoutDate!);

  factory Address.fromMap(Map<String, dynamic> m) {
    // PostGIS يعيد النقطة نصًّا سداسيًّا (EWKB) عبر PostgREST، وفكُّه في
    // التطبيق عبثٌ. فالإحداثيات تُقرأ من الأعمدة المشتقّة إن وُجدت، وإلا صفر —
    // والخريطة تعرض الفرع بدل أن تنهار.
    return Address(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      kind: AddressKind.fromWire(m['kind'] as String),
      lat: _num(m['lat']),
      lng: _num(m['lng']),
      label: m['label'] as String?,
      street: m['street'] as String?,
      district: m['district'] as String?,
      city: m['city'] as String? ?? 'المدينة المنورة',
      building: m['building'] as String?,
      notes: m['notes'] as String?,
      hotelName: m['hotel_name'] as String?,
      roomNumber: m['room_number'] as String?,
      checkoutDate: _date(m['checkout_date']),
      isDefault: m['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toInsert() => {
        'user_id': userId,
        'kind': kind.wireName,
        'location': 'SRID=4326;POINT($lng $lat)',
        if (label != null) 'label': label,
        if (street != null) 'street': street,
        if (district != null) 'district': district,
        'city': city,
        if (building != null) 'building': building,
        if (notes != null) 'notes': notes,
        if (hotelName != null) 'hotel_name': hotelName,
        if (roomNumber != null) 'room_number': roomNumber,
        if (checkoutDate != null)
          'checkout_date': checkoutDate!.toIso8601String().split('T').first,
        'is_default': isDefault,
      };
}

/// قطعةٌ في طلب — الجرد الفعليّ بعد الفرز.
///
/// **ما يطلبه العميل تقديرٌ، وما يجده الفارز هو الحقيقة.** والفصل بينهما يجعل
/// الفرق مرئيًّا («طلب ٣ ثياب ووصل ٤») بدل أن يُطمس بتعديل البند.
class OrderGarment {
  const OrderGarment({
    required this.id,
    required this.orderId,
    required this.barcode,
    required this.labelAr,
    required this.currentStage,
    this.color,
    this.brand,
    this.defectNotes,
    this.photoUrls = const [],
  });

  final String id;
  final String orderId;
  final String barcode;
  final String labelAr;
  final OrderStatus currentStage;
  final String? color;
  final String? brand;

  /// بقعة، تمزّق، لونٌ يسيل. **تُوثَّق قبل الغسيل لا بعده** — بعده تصير كلمتَه
  /// ضدّ كلمتنا.
  final String? defectNotes;
  final List<String> photoUrls;

  bool get hasDefect => defectNotes != null && defectNotes!.trim().isNotEmpty;

  factory OrderGarment.fromMap(Map<String, dynamic> m) => OrderGarment(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        barcode: m['barcode'] as String,
        labelAr: m['label_ar'] as String,
        currentStage: OrderStatus.fromWire(m['current_stage'] as String),
        color: m['color'] as String?,
        brand: m['brand'] as String?,
        defectNotes: m['defect_notes'] as String?,
        photoUrls: (m['photo_urls'] as List?)?.cast<String>() ?? const [],
      );
}

/// نتيجة مسح باركود.
class BarcodeHit {
  const BarcodeHit({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.isGarment,
    this.garmentId,
    this.garmentLabel,
  });

  final String orderId;
  final int orderNumber;
  final OrderStatus status;

  /// مُسح ملصقُ قطعةٍ لا ملصقَ الكيس — والنتيجة الطلب نفسه في الحالتين.
  final bool isGarment;
  final String? garmentId;
  final String? garmentLabel;

  factory BarcodeHit.fromMap(Map<String, dynamic> m) => BarcodeHit(
        orderId: m['order_id'] as String,
        orderNumber: _int(m['order_number']),
        status: OrderStatus.fromWire(m['status'] as String),
        isGarment: m['kind'] == 'garment',
        garmentId: m['garment_id'] as String?,
        garmentLabel: m['garment_label'] as String?,
      );
}

/// إعدادات التوصيل والسائقين لفرع — كلُّها صفٌّ تعدّله الإدارة لا ثابتٌ في
/// الشيفرة.
class DriverSettings {
  const DriverSettings({
    required this.branchId,
    this.requireDeliveryCode = true,
    this.deliveryCodeLength = 4,
    this.ttlMinutes = 180,
    this.maxAttempts = 5,
    this.maxActiveJobs = 0,
    this.locationPingSeconds = 60,
  });

  final String branchId;
  final bool requireDeliveryCode;
  final int deliveryCodeLength;
  final int ttlMinutes;
  final int maxAttempts;

  /// صفر = بلا سقف.
  final int maxActiveJobs;
  final int locationPingSeconds;

  DriverSettings copyWith({
    bool? requireDeliveryCode,
    int? deliveryCodeLength,
    int? ttlMinutes,
    int? maxAttempts,
    int? maxActiveJobs,
    int? locationPingSeconds,
  }) =>
      DriverSettings(
        branchId: branchId,
        requireDeliveryCode: requireDeliveryCode ?? this.requireDeliveryCode,
        deliveryCodeLength: deliveryCodeLength ?? this.deliveryCodeLength,
        ttlMinutes: ttlMinutes ?? this.ttlMinutes,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        maxActiveJobs: maxActiveJobs ?? this.maxActiveJobs,
        locationPingSeconds: locationPingSeconds ?? this.locationPingSeconds,
      );

  Map<String, dynamic> toMap() => {
        'branch_id': branchId,
        'require_delivery_code': requireDeliveryCode,
        'delivery_code_length': deliveryCodeLength,
        'delivery_code_ttl_minutes': ttlMinutes,
        'delivery_code_max_attempts': maxAttempts,
        'max_active_jobs': maxActiveJobs,
        'location_ping_seconds': locationPingSeconds,
      };

  factory DriverSettings.fromMap(Map<String, dynamic> m) => DriverSettings(
        branchId: m['branch_id'] as String,
        requireDeliveryCode: m['require_delivery_code'] as bool? ?? true,
        deliveryCodeLength: _int(m['delivery_code_length']),
        ttlMinutes: _int(m['delivery_code_ttl_minutes']),
        maxAttempts: _int(m['delivery_code_max_attempts']),
        maxActiveJobs: _int(m['max_active_jobs']),
        locationPingSeconds: _int(m['location_ping_seconds']),
      );
}

/// نوع المهمّة في يد السائق.
enum JobKind {
  pickup('استلام'),
  delivery('تسليم');

  const JobKind(this.labelAr);
  final String labelAr;
}

/// مهمّةُ سائق: الطلبُ منظورًا إليه من الطريق لا من المغسلة.
///
/// **الطلب الواحد مهمّتان لا واحدة**: يُستلم من بيت العميل، ويُسلَّم إليه بعد
/// أيام — وقد يحملهما سائقان. فالمهمّة هي ما يُعرض في القائمة، لا الطلب.
class DriverJob {
  const DriverJob({
    required this.order,
    required this.kind,
    this.address,
    this.customerPhone,
  });

  final LaundryOrder order;
  final JobKind kind;
  final Address? address;
  final String? customerPhone;

  bool get isPickup => kind == JobKind.pickup;

  /// موعدُ المهمّة — فتحةُ الاستلام أو فتحةُ التسليم بحسب نوعها.
  DateTime? get slotStart =>
      isPickup ? order.pickupSlotStart : order.deliverySlotStart;

  /// الخطوة التالية من حالة الطلب الآن.
  OrderStatus? get nextStatus => switch (order.status) {
        OrderStatus.pickupAssigned => OrderStatus.pickupEnRoute,
        OrderStatus.pickupEnRoute => OrderStatus.pickedUp,
        OrderStatus.deliveryAssigned => OrderStatus.outForDelivery,
        OrderStatus.outForDelivery => OrderStatus.delivered,
        _ => null,
      };

  /// الفعلُ الأخير في المهمّة: هو وحده الذي يحتاج إثباتًا (ورمزًا في التسليم).
  bool get isFinalStep =>
      order.status == OrderStatus.pickupEnRoute ||
      order.status == OrderStatus.outForDelivery;

  factory DriverJob.fromMap(Map<String, dynamic> m, String driverId) {
    final order = LaundryOrder.fromMap(m);
    // الحالة تحدّد النوع لا معرّفُ السائق: قد يكون هو نفسه سائقَ الطرفين،
    // فالسؤال «أين الطلب الآن» لا «من المسنَد إليه».
    final kind = switch (order.status) {
      OrderStatus.pickupAssigned || OrderStatus.pickupEnRoute => JobKind.pickup,
      _ => JobKind.delivery,
    };
    final addrKey = kind == JobKind.pickup ? 'pickup_address' : 'delivery_address';
    final addr = m[addrKey];
    final profile = m['profiles'];
    return DriverJob(
      order: order,
      kind: kind,
      address: addr is Map
          ? Address.fromMap(Map<String, dynamic>.from(addr))
          : null,
      customerPhone: profile is Map ? profile['phone'] as String? : null,
    );
  }
}
