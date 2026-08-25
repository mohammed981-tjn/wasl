import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// جلسة المستخدم وأدواره.
///
/// **ما تفعله هذه الطبقة وما لا تفعله**: تعرف من دخل وأيّ أدوارٍ له، فتعرض
/// الشاشة المناسبة وتُخفي ما لا يخصّه. **ولا تحرس شيئًا** — الحراسة في RLS.
/// فمن عدّل الحزمة ليرى شاشةً ليست له يجدها فارغة، لأن القاعدة ترفض لا الشاشة.
class SessionService extends ChangeNotifier {
  SessionService() {
    _sub = Db.auth.onAuthStateChange.listen((event) {
      if (event.session == null) {
        _reset();
      } else {
        // الحدث يصل قبل أن يكتمل تحميل الأدوار، فلا يُعلَن الجاهزية إلا بعده.
        refresh();
      }
    });
  }

  StreamSubscription<AuthState>? _sub;

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _profile;
  List<UserRoleAssignment> _roles = const [];
  List<Branch> _branches = const [];
  String? _activeBranchId;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isSignedIn => Db.isSignedIn;
  Map<String, dynamic>? get profile => _profile;
  List<UserRoleAssignment> get roles => _roles;

  /// الفروع التي يملك فيها المستخدم دورًا تشغيليًّا — أو كلُّ الفروع لمالك
  /// المنصّة.
  List<Branch> get branches => _branches;

  /// الفرع المختار في لوحة الإدارة. من له فرعٌ واحد لا يُسأل.
  String? get activeBranchId => _activeBranchId;
  Branch? get activeBranch => _branches
      .cast<Branch?>()
      .firstWhere((b) => b?.id == _activeBranchId, orElse: () => null);

  bool get isSuperAdmin => _roles.any((r) => r.role == AppRole.superAdmin);

  bool hasRole(AppRole role) => _roles.any((r) => r.role == role);

  /// «هل لي هذا الدور في الفرع المختار؟» — سؤال كل زرٍّ إداريّ.
  /// ومالك المنصّة يمرّ دائمًا: نطاقه المنصّة كلّها.
  bool hasRoleInActiveBranch(Set<AppRole> allowed) {
    if (isSuperAdmin) return true;
    return _roles.any((r) =>
        r.branchId != null &&
        r.branchId == _activeBranchId &&
        allowed.contains(r.role));
  }

  /// من يفتح حزمة الإدارة أصلًا.
  bool get canUseAdminApp => _roles.any((r) => r.role.usesAdminApp);

  /// أعلى دورٍ يُعرض في الواجهة — للترحيب لا للصلاحية.
  AppRole? get primaryRole {
    for (final r in AppRole.values) {
      if (_roles.any((a) => a.role == r)) return r;
    }
    return null;
  }

  Future<void> refresh() async {
    if (!Db.isSignedIn) {
      _reset();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // `ensure_profile` مُحايدةٌ إن تكرّرت، وتُنشئ الملفّ عند أوّل دخول —
      // فلا محفّز على `auth.users` يربط التسجيل كلّه بنجاح شيفرتنا.
      _profile = await Db.client
          .rpc('ensure_profile')
          .then((v) => (v as Map).cast<String, dynamic>());

      final roleRows = await Db.client
          .from('user_roles')
          .select('role, laundry_id, branch_id, branches(name_ar)')
          .eq('user_id', Db.currentUser!.id);

      _roles = (roleRows as List)
          .map((e) => UserRoleAssignment.fromMap(e as Map<String, dynamic>))
          .toList();

      // الفروع: سياسة `branches_read` تتكفّل بالترشيح، فلا حاجة لشرطٍ هنا —
      // ومن لا دور تشغيليّ له يرى الفروع النشطة كما يراها أيّ عميل.
      final branchRows = await Db.client
          .from('branches')
          .select('id, laundry_id, name_ar, city, phone, daily_capacity_pieces, is_active')
          .order('name_ar');

      _branches = (branchRows as List)
          .map((e) => Branch.fromMap(e as Map<String, dynamic>))
          .toList();

      final scoped =
          _roles.where((r) => r.branchId != null).map((r) => r.branchId!).toSet();
      if (!isSuperAdmin && scoped.isNotEmpty) {
        _branches = _branches.where((b) => scoped.contains(b.id)).toList();
      }

      if (_activeBranchId == null ||
          !_branches.any((b) => b.id == _activeBranchId)) {
        _activeBranchId = _branches.isEmpty ? null : _branches.first.id;
      }
    } catch (e) {
      _error = humanizeDbError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setActiveBranch(String branchId) {
    if (_activeBranchId == branchId) return;
    _activeBranchId = branchId;
    notifyListeners();
  }

  Future<void> signInWithPassword(String email, String password) async {
    await Db.auth.signInWithPassword(email: email, password: password);
  }

  /// الدخول برقم الجوال — الطريق المقصود.
  ///
  /// يتطلّب تفعيل مزوّد الرسائل في لوحة Supabase (انظر `dev-docs/setup-ar.md`).
  /// وحتى يُفعَّل يرفع `AuthException`، ولذلك يبقى الدخول بالبريد متاحًا.
  Future<void> sendPhoneOtp(String phone) async {
    await Db.auth.signInWithOtp(phone: phone);
  }

  Future<void> verifyPhoneOtp(String phone, String token) async {
    await Db.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() async {
    await Db.auth.signOut();
  }

  void _reset() {
    _profile = null;
    _roles = const [];
    _branches = const [];
    _activeBranchId = null;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
