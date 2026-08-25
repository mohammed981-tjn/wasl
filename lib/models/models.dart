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
  });

  final String id;
  final String laundryId;
  final String nameAr;
  final String city;
  final String? phone;

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
