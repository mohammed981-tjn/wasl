import '../models/models.dart';
import 'supabase_service.dart';

/// الشكاوى — طرفُ الشاكي وطرفُ خدمة العملاء في مكانٍ واحد.
///
/// **ولا قاعدةَ عملٍ هنا.** لا مهلةٌ تُحسب، ولا نسبةُ استردادٍ تُضرب، ولا
/// حالةٌ تُكتب. الشاشةُ تعرض والقاعدةُ تحكم — وأيُّ حسابٍ يُكرَّر هنا يصير
/// مرجعًا ثانيًا يختلف عن الأوّل يومًا، وأوّلُ اختلافٍ بينهما نزاعٌ مع عميل.
class ComplaintsService {
  const ComplaintsService();

  // ── الأنواع والإعدادات ────────────────────────────────────────────────

  /// أنواعُ الشكاوى المتاحة **لهذا الدور** في هذه المغسلة.
  ///
  /// والترشيحُ على الدور يقع هنا وفي القاعدة معًا: هنا كي لا يرى العميل ما
  /// لا يخصّه، وهناك كي لا يفتحه من تجاوز الشاشة.
  Future<List<ComplaintType>> types({
    required String laundryId,
    required String role,
    bool generalOnly = false,
  }) async {
    var q = Db.client
        .from('complaint_types')
        .select()
        .eq('laundry_id', laundryId)
        .eq('is_active', true);
    if (generalOnly) q = q.eq('allows_general', true);

    final rows = await q.order('sort_order') as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(ComplaintType.fromMap)
        // `for_role == null` نوعٌ لكل الأدوار (تذكرةٌ عامّة غالبًا).
        .where((t) => t.forRole == null || t.forRole == role)
        .toList();
  }

  /// كلُّ الأنواع بلا ترشيحٍ بدور — للوحة الإدارة، ومنها المعطَّل.
  ///
  /// **والمعطَّلُ يُعرض ولا يُخفى**: الإدارةُ تحتاج أن ترى ما عطّلته كي
  /// تعيده، وقائمةٌ تعرض النشط وحده تجعل التعطيل حذفًا لا رجعة فيه من
  /// وجهة نظر من يستعمل الشاشة.
  Future<List<ComplaintType>> allTypes(String laundryId) async {
    final rows = await Db.client
        .from('complaint_types')
        .select()
        .eq('laundry_id', laundryId)
        .order('sort_order') as List;
    return rows.cast<Map<String, dynamic>>().map(ComplaintType.fromMap).toList();
  }

  Future<void> saveType(ComplaintType t, {required String laundryId}) =>
      t.id.isEmpty
          ? Db.client.from('complaint_types').insert({
              'laundry_id': laundryId,
              'code': t.code,
              'label_ar': t.labelAr,
              'for_role': t.forRole,
              'suggested_against': t.suggestedAgainst,
              'allows_general': t.allowsGeneral,
              'is_active': t.isActive,
              'sort_order': t.sortOrder,
            })
          // **الرمزُ لا يُرسَل في التحديث**: القاعدة تمنع تبديلَه على نوعٍ
          // استُعمل، وإرسالُه بقيمته نفسها يمرّ — لكنّ إرساله أصلًا يغري
          // بجعله حقلًا يُحرَّر في الشاشة، وهو ليس كذلك.
          : Db.client.from('complaint_types').update({
              'label_ar': t.labelAr,
              'for_role': t.forRole,
              'suggested_against': t.suggestedAgainst,
              'allows_general': t.allowsGeneral,
              'is_active': t.isActive,
              'sort_order': t.sortOrder,
            }).eq('id', t.id);

  Future<void> deleteType(String id) =>
      Db.client.from('complaint_types').delete().eq('id', id);

  /// قوالبُ رسائل الشكاوى.
  Future<List<ComplaintTemplate>> templates(String laundryId) async {
    final rows = await Db.client
        .from('complaint_templates')
        .select()
        .eq('laundry_id', laundryId) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(ComplaintTemplate.fromMap)
        .toList();
  }

  Future<void> saveTemplate(ComplaintTemplate t, {required String laundryId}) =>
      t.id.isEmpty
          ? Db.client.from('complaint_templates').insert({
              'laundry_id': laundryId,
              'event': t.event.code,
              'channel': t.channel,
              'audience': t.audience,
              'title_ar': t.titleAr,
              'body_ar': t.bodyAr,
              'is_active': t.isActive,
            })
          : Db.client.from('complaint_templates').update({
              'title_ar': t.titleAr,
              'body_ar': t.bodyAr,
              'is_active': t.isActive,
            }).eq('id', t.id);

  Future<void> deleteTemplate(String id) =>
      Db.client.from('complaint_templates').delete().eq('id', id);

  /// حفظُ الإعدادات.
  ///
  /// **`upsert` لا `update`**: مغسلةٌ أُنشئت قبل مهاجرة الشكاوى قد تكون بلا
  /// صفّ إعدادات، و`update` عليها يمسّ صفرَ صفوفٍ **وينجح** — فتظهر الشاشة
  /// وكأنّها حفظت، ويعود الرقمُ القديم عند أوّل تحديث.
  Future<void> saveSettings({
    required String laundryId,
    required ComplaintSettings settings,
  }) =>
      Db.client.from('complaint_settings').upsert({
        'laundry_id': laundryId,
        'is_enabled': settings.isEnabled,
        'window_hours': settings.windowHours,
        'response_sla_hours': settings.responseSlaHours,
        'auto_close_days': settings.autoCloseDays,
        'driver_warning_threshold': settings.driverWarningThreshold,
        'allow_general_tickets': settings.allowGeneralTickets,
      }, onConflict: 'laundry_id');

  Future<ComplaintSettings> settings(String laundryId) async {
    final rows = await Db.client
        .from('complaint_settings')
        .select()
        .eq('laundry_id', laundryId)
        .limit(1) as List;
    return rows.isEmpty
        ? const ComplaintSettings()
        : ComplaintSettings.fromMap(rows.first as Map<String, dynamic>);
  }

  // ── طرفُ الشاكي ───────────────────────────────────────────────────────

  /// فتحُ شكوى.
  ///
  /// **ما لا يُرسَل هنا مقصود**: المغسلةُ والفرعُ والدورُ تُشتقّ في القاعدة من
  /// الطلب. وإرسالُها من التطبيق يعني قبولَ ما يقوله جهازٌ عن نفسه.
  Future<String> submit({
    required String typeId,
    required String description,
    String? orderId,
    String? laundryId,
    String? againstId,
    String? againstRole,
    List<String> photoUrls = const [],
  }) async {
    final row = await Db.client
        .from('complaints')
        .insert({
          'type_id': typeId,
          'description': description.trim(),
          if (orderId != null) 'order_id': orderId,
          // تُرسل لأن العمود `not null`، ويستبدلها الحارس بمغسلة الطلب.
          'laundry_id': laundryId ?? '00000000-0000-0000-0000-000000000000',
          'submitted_by': Db.currentUser?.id,
          // الحارسُ يعيد كتابته من واقع الطلب؛ ويُرسل لأن العمود `not null`.
          'submitted_by_role': 'customer',
          if (againstId != null) 'against_id': againstId,
          if (againstRole != null) 'against_role': againstRole,
          if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// شكاواي — بأحدثها أوّلًا.
  Future<List<Complaint>> mine() async {
    final uid = Db.currentUser?.id;
    if (uid == null) return const [];
    final rows = await Db.client
        .from('complaints_queue')
        .select()
        .eq('submitted_by', uid) as List;
    return rows.cast<Map<String, dynamic>>().map(Complaint.fromMap).toList();
  }

  /// شكاوى طلبٍ بعينه — تُعرض في شاشة تتبّعه.
  Future<List<Complaint>> forOrder(String orderId) async {
    final rows = await Db.client
        .from('complaints_queue')
        .select()
        .eq('order_id', orderId) as List;
    return rows.cast<Map<String, dynamic>>().map(Complaint.fromMap).toList();
  }

  /// جوابُ الشاكي — وهو الذي يُغلق.
  ///
  /// «نعم» تُغلق، و«لا» تعيدها للطابور بأولوية ولا تمحو ما صُرف.
  Future<void> confirm({
    required String complaintId,
    required bool solved,
    String? note,
  }) =>
      Db.client.rpc('confirm_complaint_resolution', params: {
        'p_complaint': complaintId,
        'p_solved': solved,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
      });

  // ── المحادثة ──────────────────────────────────────────────────────────

  /// **الرسائلُ الداخليّة لا تُرشَّح هنا بل في السياسة.** ترشيحٌ في التطبيق
  /// يعني أنّ من ينادي الواجهة مباشرةً يقرؤها.
  Future<List<ComplaintMessage>> messages(String complaintId) async {
    final rows = await Db.client
        .from('complaint_messages')
        .select()
        .eq('complaint_id', complaintId)
        .order('created_at') as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(ComplaintMessage.fromMap)
        .toList();
  }

  Future<void> send({
    required String complaintId,
    required String body,
    required String role,
    bool internal = false,
  }) =>
      Db.client.from('complaint_messages').insert({
        'complaint_id': complaintId,
        'sender_id': Db.currentUser?.id,
        'sender_role': role,
        'body': body.trim(),
        'is_internal': internal,
      });

  // ── طرفُ خدمة العملاء ─────────────────────────────────────────────────

  /// الطابور — **مرتَّبٌ في القاعدة**: المرتدَّةُ أوّلًا، فالمتجاوزةُ مهلتَها،
  /// فالأقدم. ولا يُعاد ترتيبُه هنا: ترتيبٌ في الجهاز يحتاج الصفوف كلَّها.
  Future<List<Complaint>> queue({
    String? branchId,
    ComplaintStatus? status,
    int limit = 100,
  }) async {
    var q = Db.client.from('complaints_queue').select();
    if (branchId != null) q = q.eq('branch_id', branchId);
    if (status != null) q = q.eq('status', status.code);
    final rows = await q.limit(limit) as List;
    return rows.cast<Map<String, dynamic>>().map(Complaint.fromMap).toList();
  }

  Future<Complaint?> byId(String id) async {
    final rows = await Db.client
        .from('complaints_queue')
        .select()
        .eq('id', id)
        .limit(1) as List;
    return rows.isEmpty
        ? null
        : Complaint.fromMap(rows.first as Map<String, dynamic>);
  }

  /// التقاطُها: تخرج من الطابور ويُختم أوّلُ لمسة — وبها تُقاس مهلة الردّ.
  Future<void> claim(String complaintId) =>
      Db.client.rpc('claim_complaint', params: {'p_complaint': complaintId});

  /// قرارُ الحلّ.
  ///
  /// **تُرسَل نسبةٌ لا مبلغ.** المبلغُ يُقرأ من الطلب في القاعدة ويُسقَّف بما
  /// تبقّى من المقبوض؛ ومبلغٌ من التطبيق مبلغٌ يُملى.
  Future<ComplaintResolution> resolve({
    required String complaintId,
    required String resolution,
    double? refundPercent,
    int? loyaltyPoints,
    bool warnAgainst = false,
    String? internalNote,
  }) async {
    final res = await Db.client.rpc('resolve_complaint', params: {
      'p_complaint': complaintId,
      'p_resolution': resolution.trim(),
      if (refundPercent != null && refundPercent > 0)
        'p_refund_percent': refundPercent,
      if (loyaltyPoints != null && loyaltyPoints > 0)
        'p_loyalty_points': loyaltyPoints,
      'p_warn_against': warnAgainst,
      if (internalNote != null && internalNote.trim().isNotEmpty)
        'p_internal_note': internalNote.trim(),
    });
    return ComplaintResolution.fromMap(
        (res as Map).cast<String, dynamic>());
  }

  /// ملخّصٌ للوحة — وفيه سطرا الإغلاق: بإقرارٍ وبصمت.
  Future<ComplaintSummary> summary({
    required String laundryId,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await Db.client.rpc('complaint_summary', params: {
      'p_laundry': laundryId,
      if (from != null) 'p_from': _day(from),
      if (to != null) 'p_to': _day(to),
    }) as List;
    return rows.isEmpty
        ? const ComplaintSummary()
        : ComplaintSummary.fromMap(rows.first as Map<String, dynamic>);
  }

  /// شكاوى حُلّت ولم يبلغ أصحابَها ردُّها.
  ///
  /// **رقمٌ يجب أن يُرى.** هذه لن تُغلق تلقائيًّا أبدًا — بحكم الحارس في
  /// القاعدة — وستقعد في الطابور بلا سببٍ ظاهر. فيُعرض السبب صريحًا بدل أن
  /// يُكتشف بعد شهر.
  Future<int> unnotifiedCount(String laundryId) async {
    final rows = await Db.client
        .rpc('complaints_unnotified', params: {'p_laundry': laundryId}) as List;
    return rows.length;
  }

  /// إنذاراتُ سائق — يقرؤها هو والإدارة.
  ///
  /// **العدُّ هنا لا في القاعدة**: دالّةُ العدّ مقفلةٌ على الخادم عمدًا كي لا
  /// يصير عدُّ إنذارات أيِّ سائقٍ مسبارًا يُنادى. والسياسةُ ترشّح الصفوف.
  Future<List<DriverWarning>> warnings(String driverId) async {
    final rows = await Db.client
        .from('driver_warnings')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>().map(DriverWarning.fromMap).toList();
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
