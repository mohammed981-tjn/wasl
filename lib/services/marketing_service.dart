import '../models/models.dart';
import 'supabase_service.dart';

/// الكوبونات.
///
/// **لا حساب خصمٍ هنا.** `quote_coupon` في القاعدة هي المرجع، وهي نفسها التي
/// ينادينها تطبيق العميل — فما تراه الإدارة في المعاينة هو ما يُخصَم فعلًا.
class MarketingService {
  const MarketingService();

  Future<List<Coupon>> coupons(String laundryId) async {
    final rows = await Db.client
        .from('coupons')
        .select('*, coupon_redemptions(count)')
        .eq('laundry_id', laundryId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Coupon.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(Coupon c) async {
    if (c.id.isEmpty) {
      await Db.client.from('coupons').insert(c.toUpsert());
    } else {
      await Db.client.from('coupons').update(c.toUpsert()).eq('id', c.id);
    }
  }

  /// الإيقاف لا الحذف: حذفُ كوبونٍ يمحو استخداماته معه (`on delete cascade`)،
  /// فتختفي من التقارير خصوماتٌ صُرفت فعلًا.
  Future<void> setActive(String id, bool active) async {
    await Db.client.from('coupons').update({'is_active': active}).eq('id', id);
  }

  /// معاينة: ماذا يخصم هذا الكوبون على فاتورةٍ بهذه القيمة؟
  Future<({double discount, bool valid, String reason})> preview({
    required String code,
    required String laundryId,
    required String branchId,
    required String userId,
    required double subtotal,
    double deliveryFee = 0,
  }) async {
    final rows = await Db.client.rpc('quote_coupon', params: {
      'p_code': code,
      'p_laundry': laundryId,
      'p_branch': branchId,
      'p_user': userId,
      'p_subtotal': subtotal,
      'p_delivery_fee': deliveryFee,
    });
    final list = rows as List;
    if (list.isEmpty) {
      return (discount: 0.0, valid: false, reason: 'لا نتيجة');
    }
    final m = list.first as Map<String, dynamic>;
    final d = m['discount'];
    return (
      discount: d is num ? d.toDouble() : double.tryParse('$d') ?? 0,
      valid: m['valid'] as bool? ?? false,
      reason: (m['reason'] ?? '') as String,
    );
  }
}

/// ساعات العمل وإعدادات الحجز — مدخلا محرّك المواعيد.
class ScheduleService {
  const ScheduleService();

  Future<List<BranchHours>> hours(String branchId) async {
    final rows = await Db.client
        .from('branch_hours')
        .select()
        .eq('branch_id', branchId)
        .order('weekday');
    final found = (rows as List)
        .map((e) => BranchHours.fromMap(e as Map<String, dynamic>))
        .toList();

    // الأيام السبعة تُعرض دائمًا. ويومٌ بلا صفٍّ في القاعدة **لا فتحات فيه**
    // إطلاقًا — فعرضُ ستة أيام وإخفاء السابع يجعل «لماذا لا مواعيد السبت؟»
    // سؤالًا بلا جواب على الشاشة.
    return [
      for (var d = 0; d < 7; d++)
        found.cast<BranchHours?>().firstWhere((h) => h?.weekday == d,
                orElse: () => null) ??
            BranchHours(
                weekday: d, opensAt: '08:00', closesAt: '22:00', isClosed: true),
    ];
  }

  Future<void> saveHours(String branchId, List<BranchHours> hours) async {
    await Db.client.from('branch_hours').upsert(
          hours.map((h) => h.toUpsert(branchId)).toList(),
          onConflict: 'branch_id,weekday',
        );
  }

  Future<BookingSettings> bookingSettings(String branchId) async {
    final row = await Db.client
        .from('booking_settings')
        .select()
        .eq('branch_id', branchId)
        .maybeSingle();
    return row == null
        ? BookingSettings(branchId: branchId)
        : BookingSettings.fromMap(row);
  }

  Future<void> saveBookingSettings(BookingSettings s) async {
    await Db.client.from('booking_settings').upsert(s.toUpsert());
  }

  Future<void> updateCapacity(String branchId, int dailyPieces) async {
    await Db.client
        .from('branches')
        .update({'daily_capacity_pieces': dailyPieces})
        .eq('id', branchId);
  }
}

/// قوالب الإشعارات.
class TemplatesService {
  const TemplatesService();

  Future<List<NotificationTemplate>> ofLaundry(String laundryId) async {
    final rows = await Db.client
        .from('notification_templates')
        .select()
        .eq('laundry_id', laundryId);
    return (rows as List)
        .map((e) => NotificationTemplate.fromMap(e as Map<String, dynamic>))
        .toList()
      // بترتيب مسار الطلب لا بترتيب الإدراج: المحرّر يقرأ الرحلة كما يعيشها
      // العميل، فيرى أين تنقطع الرسائل.
      ..sort((a, b) =>
          a.triggerStatus.index.compareTo(b.triggerStatus.index));
  }

  Future<void> save(NotificationTemplate t) async {
    if (t.id.isEmpty) {
      await Db.client.from('notification_templates').insert(t.toUpsert());
    } else {
      await Db.client
          .from('notification_templates')
          .update(t.toUpsert())
          .eq('id', t.id);
    }
  }

  Future<void> remove(String id) async {
    await Db.client.from('notification_templates').delete().eq('id', id);
  }
}
