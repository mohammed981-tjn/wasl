/// أنواع القاعدة المُعدَّدة، منقولةً إلى Dart.
///
/// **لماذا تُكتب يدويًّا ولا تُترك نصوصًا**: النصّ الحرّ يقبل `'washing'` و
/// `'Washing'` و`'washng'`، وثالثها عطلٌ صامت — الطلب يبدو في حالةٍ لا تطابقها
/// أيّ شاشة، ولا يُكتشف إلا حين يشتكي عميل. والمُعدَّد يجعل الخطأ خطأَ ترجمة.
///
/// وكل `wireName` هنا يجب أن يطابق قيمة enum في SQL حرفًا بحرف.
library;

/// حالات الطلب — الترتيب هنا هو نفسه الخطّ الزمني الذي يراه العميل.
enum OrderStatus {
  draft('draft', 'مسوّدة'),
  placed('placed', 'تم الطلب'),
  accepted('accepted', 'تم قبول الطلب'),
  pickupAssigned('pickup_assigned', 'أُسند لسائق'),
  pickupEnRoute('pickup_en_route', 'السائق في الطريق'),
  pickedUp('picked_up', 'تم الاستلام'),
  atLaundry('at_laundry', 'وصلت للمغسلة'),
  sorting('sorting', 'جاري الفرز'),
  washing('washing', 'جاري الغسيل'),
  drying('drying', 'جاري التجفيف'),
  ironing('ironing', 'جاري الكوي'),
  packaging('packaging', 'جاري التغليف'),
  ready('ready', 'جاهز'),
  deliveryAssigned('delivery_assigned', 'أُسند للتوصيل'),
  outForDelivery('out_for_delivery', 'خرج للتوصيل'),
  delivered('delivered', 'تم التسليم'),
  onHold('on_hold', 'موقوف'),
  cancelled('cancelled', 'ملغى'),
  refunded('refunded', 'مسترَدّ');

  const OrderStatus(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static OrderStatus fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('حالة طلب غير معروفة: $v'));

  /// المراحل التي تقع **داخل** المغسلة — يعرضها تطبيق الموظّف، ويقيس عليها
  /// التقرير «كم طلبًا في الغسيل الآن؟».
  bool get isInsideLaundry => const {
        OrderStatus.atLaundry, OrderStatus.sorting, OrderStatus.washing,
        OrderStatus.drying, OrderStatus.ironing, OrderStatus.packaging,
      }.contains(this);

  /// حالةٌ انتهى عندها الطلب فلا يتحرّك بعدها إلا باسترداد.
  bool get isTerminal => const {
        OrderStatus.delivered, OrderStatus.cancelled, OrderStatus.refunded,
      }.contains(this);

  /// الطلب حيٌّ في التشغيل: يُحتسب في لوحة اليوم وفي طاقة الفرع.
  bool get isActive => this != OrderStatus.draft && !isTerminal;
}

/// أدوار القاعدة السبعة. تُقرأ من `user_roles` ولا تُكتب من التطبيق.
enum AppRole {
  superAdmin('super_admin', 'مالك المنصّة'),
  branchManager('branch_manager', 'مدير فرع'),
  laundryStaff('laundry_staff', 'موظّف مغسلة'),
  driver('driver', 'سائق'),
  customerService('customer_service', 'خدمة العملاء'),
  accountant('accountant', 'محاسب'),
  customer('customer', 'عميل');

  const AppRole(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static AppRole fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('دور غير معروف: $v'));

  /// من يفتح حزمة الإدارة. والشاشة تُخفي ما لا يخصّه، **والقاعدة تمنعه** —
  /// فالإخفاء راحةٌ للعين لا أمن.
  bool get usesAdminApp => const {
        AppRole.superAdmin, AppRole.branchManager,
        AppRole.customerService, AppRole.accountant,
      }.contains(this);
}

/// وحدة تسعير الخدمة — تحدّد شكل شاشة الإدخال نفسها.
enum PricingUnit {
  piece('piece', 'قطعة'),
  kilogram('kilogram', 'كيلوغرام'),
  basket('basket', 'سلّة');

  const PricingUnit(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static PricingUnit fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('وحدة تسعير غير معروفة: $v'));

  /// السؤال الذي يُطرح على العميل بحسب الوحدة.
  String get promptAr => switch (this) {
        PricingUnit.piece => 'كم قطعة؟',
        PricingUnit.kilogram => 'كم كيلو؟',
        PricingUnit.basket => 'كم سلّة؟',
      };
}

/// استراتيجية احتساب رسم التوصيل.
enum DeliveryStrategy {
  flat('flat', 'رسم ثابت'),
  distance('distance', 'شرائح مسافة'),
  zone('zone', 'حسب المنطقة');

  const DeliveryStrategy(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static DeliveryStrategy fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('استراتيجية توصيل غير معروفة: $v'));
}

/// حالة الدفع على الطلب. **مشتقّة في القاعدة لا مكتوبة**، فالتطبيق يقرؤها ولا
/// يضبطها.
enum PaymentStatus {
  unpaid('unpaid', 'غير مدفوع'),
  authorized('authorized', 'محجوز'),
  paid('paid', 'مدفوع'),
  partiallyRefunded('partially_refunded', 'مسترَدّ جزئيًّا'),
  refunded('refunded', 'مسترَدّ'),
  failed('failed', 'فشل الدفع');

  const PaymentStatus(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static PaymentStatus fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('حالة دفع غير معروفة: $v'));
}

enum CouponKind {
  percentage('percentage', 'نسبة مئوية'),
  fixed('fixed', 'مبلغ ثابت'),
  freeDelivery('free_delivery', 'توصيل مجاني');

  const CouponKind(this.wireName, this.labelAr);
  final String wireName;
  final String labelAr;

  static CouponKind fromWire(String v) =>
      values.firstWhere((e) => e.wireName == v,
          orElse: () => throw ArgumentError('نوع كوبون غير معروف: $v'));
}
