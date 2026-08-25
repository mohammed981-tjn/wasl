import '../models/enums.dart';
import 'supabase_service.dart';

/// موظّفٌ في فرع، بدوره.
class StaffMember {
  const StaffMember({
    required this.roleRowId,
    required this.userId,
    required this.role,
    required this.branchId,
    this.fullName,
    this.phone,
    this.email,
    this.blockedAt,
  });

  final String roleRowId;
  final String userId;
  final AppRole role;
  final String branchId;
  final String? fullName;
  final String? phone;
  final String? email;
  final DateTime? blockedAt;

  bool get isBlocked => blockedAt != null;

  String get displayName {
    final n = fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return phone ?? email ?? 'مستخدم';
  }

  factory StaffMember.fromMap(Map<String, dynamic> m) {
    final p = m['profiles'] as Map<String, dynamic>?;
    return StaffMember(
      roleRowId: m['id'] as String,
      userId: m['user_id'] as String,
      role: AppRole.fromWire(m['role'] as String),
      branchId: m['branch_id'] as String,
      fullName: p?['full_name'] as String?,
      phone: p?['phone'] as String?,
      email: p?['email'] as String?,
      blockedAt: p?['blocked_at'] == null
          ? null
          : DateTime.tryParse(p!['blocked_at'] as String)?.toLocal(),
    );
  }
}

/// الموظّفون والأدوار.
///
/// **حدودٌ تفرضها القاعدة لا هذه الطبقة**: مدير الفرع يوظّف في فرعه، ولا يصنع
/// `super_admin`، ولا يوظّف في فرعٍ ليس فرعه — يحرس ذلك محفّز
/// `guard_role_grants`. فما هنا واجهةٌ للفعل، والرفض يأتي من هناك مترجَمًا.
class StaffService {
  const StaffService();

  Future<List<StaffMember>> ofBranch(String branchId) async {
    final rows = await Db.client
        .from('user_roles')
        .select('id, user_id, role, branch_id, '
            'profiles!user_roles_user_id_fkey(full_name, phone, email, blocked_at)')
        .eq('branch_id', branchId);
    return (rows as List)
        .map((e) => StaffMember.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.role.index.compareTo(b.role.index));
  }

  /// البحث عن مستخدمٍ قائم برقمه أو بريده.
  ///
  /// **ولا يُنشئ حسابًا**: إنشاء الحسابات يقع في `auth` عبر تسجيل المستخدم
  /// نفسه — فالموظّف يسجّل أوّلًا، ثم يُسنَد له دور. وهذا يمنع إنشاء حساباتٍ
  /// وهمية من لوحة الإدارة.
  Future<List<Map<String, dynamic>>> findUser(String term) async {
    final t = term.trim();
    if (t.isEmpty) return const [];
    final rows = await Db.client
        .from('profiles')
        .select('id, full_name, phone, email')
        .or('phone.eq.$t,email.eq.$t')
        .limit(5);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> assign({
    required String userId,
    required AppRole role,
    required String laundryId,
    required String branchId,
  }) async {
    await Db.client.from('user_roles').insert({
      'user_id': userId,
      'role': role.wireName,
      'laundry_id': laundryId,
      'branch_id': branchId,
    });
  }

  Future<void> revoke(String roleRowId) async {
    await Db.client.from('user_roles').delete().eq('id', roleRowId);
  }
}
