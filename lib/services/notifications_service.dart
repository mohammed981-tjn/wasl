import '../models/models.dart';
import 'supabase_service.dart';

/// صندوقُ الرسائل داخل التطبيق.
///
/// **قناةُ `in_app` هي الوحيدة التي تعمل بلا مزوّدٍ خارجيّ.** والدفعُ والرسائل
/// معلَّقان على مفاتيح المالك، فما دامت كذلك تبقى هذه القناةُ حاملةَ ما يجب
/// أن يصل — ومنه **سؤالُ تأكيد الشكوى** الذي يقوم عليه إغلاقُها.
///
/// وقد كان الطابور يمتلئ منذ المرحلة الثامنة ولا شيء يقرؤه.
class NotificationsService {
  const NotificationsService();

  /// رسائلي — بأحدثها أوّلًا.
  ///
  /// **و`skipped` تُعرض كما تُعرض `queued`**: هي رسالةٌ لم تُرسَل على قناةٍ
  /// أوقفها صاحبُها، لا رسالةٌ لا تخصّه. وإخفاؤها يعني أنّ من أوقف الدفع لا
  /// يرى المحتوى أصلًا — وهو لم يطلب ذلك، بل طلب ألّا يُزعَج بصوت.
  Future<List<AppNotification>> inbox({int limit = 50}) async {
    final uid = Db.currentUser?.id;
    if (uid == null) return const [];
    final rows = await Db.client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .eq('channel', 'in_app')
        .order('created_at', ascending: false)
        .limit(limit) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(AppNotification.fromMap)
        .toList();
  }

  Future<int> unreadCount() async {
    final uid = Db.currentUser?.id;
    if (uid == null) return 0;
    final rows = await Db.client
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('channel', 'in_app')
        .isFilter('read_at', null) as List;
    return rows.length;
  }

  /// **يُعلَّم المقروءُ ولا يُحذف.** الحذفُ يفقد أثرَ «سُئل صاحبُها» الذي
  /// يفحصه كنسُ الشكاوى قبل أن يُغلق على أحد.
  Future<void> markRead(String id) => Db.client
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);

  Future<void> markAllRead() async {
    final uid = Db.currentUser?.id;
    if (uid == null) return;
    await Db.client
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('user_id', uid)
        .eq('channel', 'in_app')
        .isFilter('read_at', null);
  }
}
