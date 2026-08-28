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
    this.paymentMethod = PaymentMethod.cashOnDelivery,
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

  /// ما اختاره العميل. و`payment_status` هو ما وقع فعلًا — والفرق بينهما هو
  /// ما يجعل «اختار البطاقة ولم يدفع» حالةً مرئيّة لا لغزًا.
  final PaymentMethod paymentMethod;
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
      paymentMethod: m['payment_method'] == null
          ? PaymentMethod.cashOnDelivery
          : PaymentMethod.fromWire(m['payment_method'] as String),
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

/// حالة الدفعة عند المزوّد.
enum PaymentTxnStatus {
  pending('pending', 'بانتظار الدفع'),
  authorized('authorized', 'محجوز'),
  captured('captured', 'مقبوض'),
  failed('failed', 'فشل'),
  cancelled('cancelled', 'ملغًى');

  const PaymentTxnStatus(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static PaymentTxnStatus fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('حالة دفعة غير معروفة: $v'));
}

/// محاولةُ دفعٍ — ناجحةً كانت أو فاشلة.
///
/// **المحاولة كيانٌ لا نتيجة**: من يسجّل الناجحة وحدها لا يعرف كم عميلًا حاول
/// ولم يستطع، وهو أهمّ رقمٍ في قمع الشراء.
class Payment {
  const Payment({
    required this.id,
    required this.orderId,
    required this.method,
    required this.status,
    required this.amount,
    required this.createdAt,
    this.providerRef,
    this.cardBrand,
    this.cardLast4,
    this.failureMessage,
    this.capturedAt,
    this.refunded = 0,
  });

  final String id;
  final String orderId;
  final PaymentMethod method;
  final PaymentTxnStatus status;
  final double amount;
  final String? providerRef;
  final String? cardBrand;
  final String? cardLast4;
  final String? failureMessage;
  final DateTime? capturedAt;
  final DateTime createdAt;

  /// ما استُردّ منها فعلًا — يُملأ حين تُجلب مع استرداداتها.
  final double refunded;

  double get refundable => status == PaymentTxnStatus.captured
      ? (amount - refunded).clamp(0, amount)
      : 0;

  String get label {
    if (cardLast4 != null) {
      return '${cardBrand ?? 'بطاقة'} •••• $cardLast4';
    }
    return method.labelAr;
  }

  factory Payment.fromMap(Map<String, dynamic> m) {
    final refunds = m['refunds'];
    return Payment(
      id: m['id'] as String,
      orderId: m['order_id'] as String,
      method: PaymentMethod.fromWire(m['method'] as String),
      status: PaymentTxnStatus.fromWire(m['status'] as String),
      amount: _num(m['amount']),
      providerRef: m['provider_ref'] as String?,
      cardBrand: m['card_brand'] as String?,
      cardLast4: m['card_last4'] as String?,
      failureMessage: m['failure_message'] as String?,
      capturedAt: _date(m['captured_at']),
      createdAt: _date(m['created_at']) ?? DateTime.now(),
      refunded: refunds is List
          ? refunds
              .cast<Map<String, dynamic>>()
              .where((r) => r['status'] == 'completed')
              .fold<double>(0, (s, r) => s + _num(r['amount']))
          : 0,
    );
  }
}

/// موقعُ سائقٍ الآن.
class DriverPin {
  const DriverPin({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.isOnline,
    required this.updatedAt,
    this.name,
    this.accuracyM,
    this.activeJobs = 0,
  });

  final String driverId;
  final double lat;
  final double lng;
  final bool isOnline;
  final DateTime updatedAt;
  final String? name;
  final double? accuracyM;
  final int activeJobs;

  /// **الموقع القديم أخطرُ من غيابه**: دبّوسٌ عمرُه ساعةٌ يبدو كسائقٍ واقف،
  /// فيُرسَل إليه طلبٌ وهو في حيٍّ آخر. فالقِدَم يُعرض لا يُخفى.
  Duration get age => DateTime.now().difference(updatedAt);
  bool get isStale => age.inMinutes >= 10;

  String get ageLabel {
    final m = age.inMinutes;
    if (m < 1) return 'الآن';
    if (m < 60) return 'قبل $m د';
    final h = age.inHours;
    if (h < 24) return 'قبل $h س';
    return 'قبل ${age.inDays} ي';
  }

  DriverPin withMeta({String? name, int? activeJobs}) => DriverPin(
        driverId: driverId,
        lat: lat,
        lng: lng,
        isOnline: isOnline,
        updatedAt: updatedAt,
        name: name ?? this.name,
        accuracyM: accuracyM,
        activeJobs: activeJobs ?? this.activeJobs,
      );

  factory DriverPin.fromMap(Map<String, dynamic> m) => DriverPin(
        driverId: m['driver_id'] as String,
        lat: _num(m['lat']),
        lng: _num(m['lng']),
        isOnline: m['is_online'] as bool? ?? false,
        updatedAt: _date(m['updated_at']) ?? DateTime.now(),
        accuracyM: m['accuracy_m'] == null ? null : _num(m['accuracy_m']),
      );
}

/// منطقةُ توصيلٍ كما تُرسم.
class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.branchId,
    required this.nameAr,
    required this.ring,
    required this.pickupFee,
    required this.deliveryFee,
    this.combinedFee,
    this.priority = 0,
    this.isActive = true,
    this.areaKm2 = 0,
    this.centerLat = 0,
    this.centerLng = 0,
  });

  final String id;
  final String branchId;
  final String nameAr;

  /// حلقةُ المضلَّع الخارجية — (lat, lng) بترتيب الرسم.
  final List<(double, double)> ring;

  final double pickupFee;
  final double deliveryFee;
  final double? combinedFee;
  final int priority;
  final bool isActive;
  final double areaKm2;
  final double centerLat;
  final double centerLng;

  factory DeliveryZone.fromMap(Map<String, dynamic> m) {
    // GeoJSON يعطي [lng, lat] لا [lat, lng] — وقلبُهما يضع المدينة المنوّرة
    // في الصومال، ويبدو الخطأ «خريطةً فارغة» لا رسالةَ عطل.
    final geo = m['area_geojson'];
    final coords = geo is Map ? geo['coordinates'] : null;
    final outer = coords is List && coords.isNotEmpty ? coords.first : const [];
    return DeliveryZone(
      id: m['id'] as String,
      branchId: m['branch_id'] as String,
      nameAr: m['name_ar'] as String,
      ring: [
        for (final p in (outer as List))
          if (p is List && p.length >= 2) (_num(p[1]), _num(p[0])),
      ],
      pickupFee: _num(m['pickup_fee']),
      deliveryFee: _num(m['delivery_fee']),
      combinedFee: m['combined_fee'] == null ? null : _num(m['combined_fee']),
      priority: _int(m['priority']),
      isActive: m['is_active'] as bool? ?? true,
      areaKm2: _num(m['area_km2']),
      centerLat: _num(m['center_lat']),
      centerLng: _num(m['center_lng']),
    );
  }
}

/// تقييمُ طلبٍ بعد تسليمه.
class OrderRating {
  const OrderRating({
    required this.orderId,
    required this.stars,
    this.deliveryStars,
    this.tags = const [],
    this.comment,
    this.createdAt,
  });

  final String orderId;
  final int stars;
  final int? deliveryStars;
  final List<String> tags;
  final String? comment;
  final DateTime? createdAt;

  factory OrderRating.fromMap(Map<String, dynamic> m) => OrderRating(
        orderId: m['order_id'] as String,
        stars: _int(m['stars']),
        deliveryStars:
            m['delivery_stars'] == null ? null : _int(m['delivery_stars']),
        tags: (m['tags'] as List?)?.cast<String>() ?? const [],
        comment: m['comment'] as String?,
        createdAt: _date(m['created_at']),
      );
}

/// رصيدُ نقاط الولاء وما تساويه.
class LoyaltyState {
  const LoyaltyState({
    required this.balance,
    this.redeemablePoints = 0,
    this.redeemableRiyal = 0,
    this.reason,
  });

  final int balance;

  /// ما يُسمح بصرفه على هذه الفاتورة — لا كلُّ الرصيد: للسقف كلمة.
  final int redeemablePoints;
  final double redeemableRiyal;
  final String? reason;

  bool get canRedeem => redeemablePoints > 0 && redeemableRiyal > 0;
}

/// حركةُ نقاط.
class LoyaltyTxn {
  const LoyaltyTxn({
    required this.points,
    required this.kind,
    required this.createdAt,
    this.note,
  });

  final int points;
  final String kind;
  final DateTime createdAt;
  final String? note;

  bool get isEarn => points > 0;

  factory LoyaltyTxn.fromMap(Map<String, dynamic> m) => LoyaltyTxn(
        points: _int(m['points']),
        kind: m['kind'] as String? ?? 'earn',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        note: m['note'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// الشكاوى
// ═══════════════════════════════════════════════════════════════════════════

/// حالةُ الشكوى.
///
/// **`resolved` ليست نهايةً بل سؤالًا**: المدير قرّر، وبقي أن يقول صاحبُها
/// إن كان القرار حلًّا. و`closed` وحدها النهاية.
enum ComplaintStatus {
  open('open', 'جديدة'),
  inProgress('in_progress', 'قيد المعالجة'),
  resolved('resolved', 'بانتظار تأكيدك'),
  closed('closed', 'مغلقة');

  const ComplaintStatus(this.code, this.label);
  final String code;
  final String label;

  static ComplaintStatus parse(String? v) => values.firstWhere(
        (s) => s.code == v,
        orElse: () => ComplaintStatus.open,
      );

  /// هل تنتظر عملًا من الإدارة؟
  bool get needsStaff => this == open || this == inProgress;
}

/// نوعُ الشكوى — صفٌّ في `complaint_types` لا قيمةٌ في الشيفرة.
///
/// **ولذلك لا enum هنا**: النوعُ قاعدةُ عملٍ تُضيفها الإدارة وتعطّلها، وenum
/// في التطبيق يعني إصدارًا جديدًا لكل نوعٍ جديد.
class ComplaintType {
  const ComplaintType({
    required this.id,
    required this.code,
    required this.labelAr,
    this.forRole,
    this.suggestedAgainst,
    this.allowsGeneral = false,
    this.isActive = true,
    this.sortOrder = 100,
  });

  final String id;
  final String code;
  final String labelAr;

  /// الدورُ الذي يملك فتحَ هذا النوع؛ `null` = كلُّ الأدوار.
  final String? forRole;

  /// الطرفُ المشكوّ منه المقترَح — تُملأ به الشاشة ويبقى للشاكي تغييرُه.
  final String? suggestedAgainst;

  /// هل يُقبل بلا طلب (تذكرةٌ عامّة)؟
  final bool allowsGeneral;

  /// **المعطَّل يبقى صفًّا ولا يُحذف**: حذفُه يُفرغ كلَّ شكوى قديمةٍ تشير
  /// إليه من معناها. فيختفي من قائمة الاختيار ويبقى في التاريخ.
  final bool isActive;
  final int sortOrder;

  ComplaintType copyWith({
    String? labelAr,
    String? forRole,
    String? suggestedAgainst,
    bool? allowsGeneral,
    bool? isActive,
    int? sortOrder,
    bool clearForRole = false,
    bool clearSuggested = false,
  }) =>
      ComplaintType(
        id: id,
        code: code,
        labelAr: labelAr ?? this.labelAr,
        forRole: clearForRole ? null : (forRole ?? this.forRole),
        suggestedAgainst:
            clearSuggested ? null : (suggestedAgainst ?? this.suggestedAgainst),
        allowsGeneral: allowsGeneral ?? this.allowsGeneral,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  factory ComplaintType.fromMap(Map<String, dynamic> m) => ComplaintType(
        id: m['id'] as String,
        code: m['code'] as String? ?? '',
        labelAr: m['label_ar'] as String? ?? '',
        forRole: m['for_role'] as String?,
        suggestedAgainst: m['suggested_against'] as String?,
        allowsGeneral: m['allows_general'] as bool? ?? false,
        isActive: m['is_active'] as bool? ?? true,
        sortOrder: _int(m['sort_order']),
      );
}

/// حدثُ الشكوى الذي يستحقّ رسالة.
enum ComplaintEvent {
  opened('opened', 'فُتحت شكوى', 'إلى خدمة العملاء: شكوى جديدة في الطابور'),
  acknowledged('acknowledged', 'التُقطت', 'إلى الشاكي: قرأها إنسان'),
  resolved('resolved', 'حُلّت', 'إلى الشاكي — وهي التي تطلب جوابًا'),
  reopened('reopened', 'ارتدّت', 'إلى خدمة العملاء: الحلّ لم يُقنع صاحبَها'),
  closedByTimeout(
      'closed_by_timeout', 'أُغلقت بالصمت', 'إلى الشاكي: إعلامًا لا مفاجأة');

  const ComplaintEvent(this.code, this.label, this.hint);
  final String code;
  final String label;
  final String hint;

  static ComplaintEvent parse(String? v) =>
      values.firstWhere((e) => e.code == v, orElse: () => ComplaintEvent.opened);

  /// **الحدث الذي يقوم عليه النظام**: بلا رسالته لا يُغلق ملفٌّ بالصمت.
  bool get isLoadBearing => this == resolved;
}

/// قالبُ رسالةِ شكوى.
class ComplaintTemplate {
  const ComplaintTemplate({
    required this.id,
    required this.event,
    required this.channel,
    required this.audience,
    required this.bodyAr,
    this.titleAr,
    this.isActive = true,
  });

  final String id;
  final ComplaintEvent event;
  final String channel;
  final String audience;
  final String? titleAr;
  final String bodyAr;
  final bool isActive;

  ComplaintTemplate copyWith({String? titleAr, String? bodyAr, bool? isActive}) =>
      ComplaintTemplate(
        id: id,
        event: event,
        channel: channel,
        audience: audience,
        titleAr: titleAr ?? this.titleAr,
        bodyAr: bodyAr ?? this.bodyAr,
        isActive: isActive ?? this.isActive,
      );

  factory ComplaintTemplate.fromMap(Map<String, dynamic> m) => ComplaintTemplate(
        id: m['id'] as String,
        event: ComplaintEvent.parse(m['event'] as String?),
        channel: m['channel'] as String? ?? 'in_app',
        audience: m['audience'] as String? ?? 'customer',
        titleAr: m['title_ar'] as String?,
        bodyAr: m['body_ar'] as String? ?? '',
        isActive: m['is_active'] as bool? ?? true,
      );
}

/// إعداداتُ الشكاوى لمغسلة — أربعةُ أرقامٍ ليس واحدٌ منها في الشيفرة.
class ComplaintSettings {
  const ComplaintSettings({
    this.isEnabled = true,
    this.windowHours = 48,
    this.responseSlaHours = 24,
    this.autoCloseDays = 3,
    this.driverWarningThreshold = 3,
    this.allowGeneralTickets = true,
  });

  final bool isEnabled;
  final int windowHours;
  final int responseSlaHours;
  final int autoCloseDays;
  final int driverWarningThreshold;
  final bool allowGeneralTickets;

  factory ComplaintSettings.fromMap(Map<String, dynamic> m) =>
      ComplaintSettings(
        isEnabled: m['is_enabled'] as bool? ?? true,
        windowHours: _int(m['window_hours']),
        responseSlaHours: _int(m['response_sla_hours']),
        autoCloseDays: _int(m['auto_close_days']),
        driverWarningThreshold: _int(m['driver_warning_threshold']),
        allowGeneralTickets: m['allow_general_tickets'] as bool? ?? true,
      );
}

/// شكوى — كما تُقرأ من `complaints_queue` أو من الجدول.
class Complaint {
  const Complaint({
    required this.id,
    required this.number,
    required this.status,
    required this.description,
    required this.createdAt,
    this.typeLabel = '',
    this.orderId,
    this.orderNumber,
    this.branchId,
    this.submittedBy,
    this.submittedByName,
    this.submittedByRole,
    this.againstId,
    this.againstName,
    this.againstRole,
    this.resolution,
    this.internalNote,
    this.firstResponseAt,
    this.resolvedAt,
    this.responseDueAt,
    this.autoCloseAt,
    this.slaBreached = false,
    this.reopenCount = 0,
    this.closedByTimeout = false,
    this.photoUrls = const [],
  });

  final String id;
  final int number;
  final ComplaintStatus status;
  final String description;
  final DateTime createdAt;
  final String typeLabel;

  final String? orderId;
  final int? orderNumber;
  final String? branchId;

  final String? submittedBy;
  final String? submittedByName;
  final String? submittedByRole;

  final String? againstId;
  final String? againstName;
  final String? againstRole;

  /// ما كُتب للشاكي — يُقرأ في تطبيقه.
  final String? resolution;

  /// وما كُتب للإدارة — لا يصل شاشتَه.
  final String? internalNote;

  final DateTime? firstResponseAt;
  final DateTime? resolvedAt;

  /// متى وعدنا بالردّ، وهل تجاوزناه؟ يحسبهما المنظر في القاعدة.
  final DateTime? responseDueAt;
  final bool slaBreached;

  /// ومتى تُغلق تلقائيًّا إن سكت صاحبُها.
  final DateTime? autoCloseAt;

  final int reopenCount;
  final bool closedByTimeout;
  final List<String> photoUrls;

  /// رقمٌ يُقال في الهاتف.
  String get displayNumber => '#$number';

  /// هل يُنتظر جوابُ صاحبها الآن؟
  bool get awaitingConfirmation => status == ComplaintStatus.resolved;

  /// كم بقي من مهلة تأكيدها قبل أن تُغلق بالصمت؟
  Duration? get confirmTimeLeft {
    if (!awaitingConfirmation || autoCloseAt == null) return null;
    final left = autoCloseAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// ارتدّت من قبل: قال صاحبُها «لم تُحل».
  bool get wasReopened => reopenCount > 0;

  factory Complaint.fromMap(Map<String, dynamic> m) => Complaint(
        id: m['id'] as String,
        number: _int(m['complaint_number']),
        status: ComplaintStatus.parse(m['status'] as String?),
        description: m['description'] as String? ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        typeLabel: m['type_label'] as String? ??
            (m['complaint_types'] as Map<String, dynamic>?)?['label_ar']
                as String? ??
            '',
        orderId: m['order_id'] as String?,
        orderNumber: m['order_number'] == null ? null : _int(m['order_number']),
        branchId: m['branch_id'] as String?,
        submittedBy: m['submitted_by'] as String?,
        submittedByName: m['submitted_by_name'] as String?,
        submittedByRole: m['submitted_by_role'] as String?,
        againstId: m['against_id'] as String?,
        againstName: m['against_name'] as String?,
        againstRole: m['against_role'] as String?,
        resolution: m['resolution'] as String?,
        internalNote: m['internal_note'] as String?,
        firstResponseAt: _date(m['first_response_at']),
        resolvedAt: _date(m['resolved_at']),
        responseDueAt: _date(m['response_due_at']),
        autoCloseAt: _date(m['auto_close_at']),
        slaBreached: m['sla_breached'] as bool? ?? false,
        reopenCount: _int(m['reopen_count']),
        closedByTimeout: m['closed_by_timeout'] as bool? ?? false,
        photoUrls: (m['photo_urls'] as List?)?.cast<String>() ?? const [],
      );
}

/// رسالةٌ في محادثة الشكوى.
class ComplaintMessage {
  const ComplaintMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.isInternal = false,
  });

  final String id;
  final String senderId;
  final String senderRole;
  final String body;
  final DateTime createdAt;

  /// ملاحظةٌ بين الموظّفين لا تصل شاشةَ الشاكي — تحرسها السياسة لا الشاشة.
  final bool isInternal;

  factory ComplaintMessage.fromMap(Map<String, dynamic> m) => ComplaintMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String? ?? '',
        senderRole: m['sender_role'] as String? ?? 'customer',
        body: m['body'] as String? ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        isInternal: m['is_internal'] as bool? ?? false,
      );
}

/// نتيجةُ قرارِ الحلّ كما تعيدها `resolve_complaint`.
class ComplaintResolution {
  const ComplaintResolution({
    this.refundAmount = 0,
    this.loyaltyPoints = 0,
    this.warned = false,
    this.activeWarnings = 0,
    this.actions = const [],
    this.confirmBy,
  });

  final double refundAmount;
  final int loyaltyPoints;
  final bool warned;
  final int activeWarnings;
  final List<String> actions;
  final DateTime? confirmBy;

  factory ComplaintResolution.fromMap(Map<String, dynamic> m) =>
      ComplaintResolution(
        refundAmount: (m['refund_amount'] as num?)?.toDouble() ?? 0,
        loyaltyPoints: _int(m['loyalty_points']),
        warned: m['warned'] as bool? ?? false,
        activeWarnings: _int(m['active_warnings']),
        actions: (m['actions'] as List?)?.cast<String>() ?? const [],
        confirmBy: _date(m['confirm_by']),
      );
}

/// ملخّصُ الشكاوى للوحة.
class ComplaintSummary {
  const ComplaintSummary({
    this.total = 0,
    this.openNow = 0,
    this.inProgressNow = 0,
    this.slaBreached = 0,
    this.closedConfirmed = 0,
    this.closedBySilence = 0,
    this.reopened = 0,
    this.medianResponseHours,
    this.byType = const {},
  });

  final int total;
  final int openNow;
  final int inProgressNow;
  final int slaBreached;

  /// **سطران يُقرآن معًا**: ما أُغلق بإقرار صاحبه، وما أُغلق بصمته. والثاني
  /// ليس نجاحًا مهما بدا في العدّ الإجماليّ.
  final int closedConfirmed;
  final int closedBySilence;

  final int reopened;
  final double? medianResponseHours;
  final Map<String, int> byType;

  int get needsWork => openNow + inProgressNow;

  factory ComplaintSummary.fromMap(Map<String, dynamic> m) => ComplaintSummary(
        total: _int(m['total']),
        openNow: _int(m['open_now']),
        inProgressNow: _int(m['in_progress_now']),
        slaBreached: _int(m['sla_breached']),
        closedConfirmed: _int(m['closed_confirmed']),
        closedBySilence: _int(m['closed_by_silence']),
        reopened: _int(m['reopened']),
        medianResponseHours:
            (m['median_response_hours'] as num?)?.toDouble(),
        byType: ((m['by_type'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, _int(v)),
        ),
      );
}

/// إنذارٌ على سائق — صفٌّ يُراجَع لا عدّادٌ يُزاد.
class DriverWarning {
  const DriverWarning({
    required this.id,
    required this.reason,
    required this.createdAt,
    this.expiresAt,
    this.revokedAt,
    this.revokedReason,
  });

  final String id;
  final String reason;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final String? revokedReason;

  bool get isActive =>
      revokedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory DriverWarning.fromMap(Map<String, dynamic> m) => DriverWarning(
        id: m['id'] as String,
        reason: m['reason'] as String? ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        expiresAt: _date(m['expires_at']),
        revokedAt: _date(m['revoked_at']),
        revokedReason: m['revoked_reason'] as String?,
      );
}

/// رسالةٌ في صندوق المستخدم.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.body,
    required this.createdAt,
    this.title,
    this.orderId,
    this.complaintId,
    this.readAt,
    this.status = 'queued',
  });

  final String id;
  final String? title;
  final String body;
  final DateTime createdAt;

  /// إلى أين تفتح الرسالة؟ **الشكوى تسبق الطلب**: رسالةٌ عن شكوى على طلبٍ
  /// تحمل المعرّفين معًا، والمقصودُ منها الشكوى.
  final String? orderId;
  final String? complaintId;

  final DateTime? readAt;
  final String status;

  bool get isUnread => readAt == null;

  /// رسالةٌ لم تُرسَل لأنّ صاحبَها أوقف قناتها. تُعرض ولا تُخفى.
  bool get wasSkipped => status == 'skipped';

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        title: m['title'] as String?,
        body: m['body'] as String? ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
        orderId: m['order_id'] as String?,
        complaintId: m['complaint_id'] as String?,
        readAt: _date(m['read_at']),
        status: m['status'] as String? ?? 'queued',
      );
}
