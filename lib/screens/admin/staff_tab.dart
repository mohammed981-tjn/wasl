import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/session_service.dart';
import '../../services/staff_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// الموظّفون والصلاحيات.
///
/// **الدور يُسنَد ولا يُنشأ حساب.** الموظّف يسجّل بنفسه في التطبيق أوّلًا، ثم
/// يُبحث عنه برقمه ويُسنَد له دور. وهذا يمنع إنشاء حساباتٍ وهمية من اللوحة،
/// ويجعل صاحب الحساب هو من يملك بيانات دخوله لا مديرَه.
class StaffTab extends StatefulWidget {
  const StaffTab({super.key});

  @override
  State<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<StaffTab> {
  final _staff = const StaffService();
  late Future<List<StaffMember>> _future;
  String? _branchId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranchId;
    if (id != _branchId) {
      _branchId = id;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      _future = _branchId == null
          ? Future.value(const <StaffMember>[])
          : _staff.ofBranch(_branchId!);
    });
  }

  bool get _canManage => context
      .read<SessionService>()
      .hasRoleInActiveBranch({AppRole.branchManager});

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
  }

  Future<void> _add() async {
    final session = context.read<SessionService>();
    final branch = session.activeBranch;
    if (branch == null) return;

    final picked = await showDialog<({String userId, AppRole role})>(
      context: context,
      builder: (_) => _AssignDialog(staff: _staff),
    );
    if (picked == null) return;

    try {
      await _staff.assign(
        userId: picked.userId,
        role: picked.role,
        laundryId: branch.laundryId,
        branchId: branch.id,
      );
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _revoke(StaffMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('سحب الدور'),
        content: Text('سحب دور «${m.role.labelAr}» من ${m.displayName}؟\n\n'
            'لا يُحذف الحساب — يفقد صلاحيته في هذا الفرع فقط.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('سحب')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _staff.revoke(m.roleRowId);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _canManage;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('إسناد دور'),
            )
          : null,
      body: AsyncView<List<StaffMember>>(
        future: _future,
        onRetry: _reload,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'لا موظّفين في هذا الفرع بعد',
        builder: (context, members) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            Text('الموظّفون',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canManage
                  ? 'يسجّل الموظّف بنفسه أوّلًا، ثم تُسنِد له دورًا برقم جواله.'
                  : 'العرض فقط: إسناد الأدوار لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final m in members)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(m.displayName.characters.first),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(m.displayName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(m.role.labelAr,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      if (m.isBlocked)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 6),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                Theme.of(context).colorScheme.errorContainer,
                            label: const Text('محظور',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(m.phone ?? m.email ?? '—',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: canManage
                      ? IconButton(
                          tooltip: 'سحب الدور',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _revoke(m),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.staff});

  final StaffService staff;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _term = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  String? _selectedId;
  String? _selectedName;

  // موظّف المغسلة أوّلًا: هو أكثر ما يُسنَد.
  AppRole _role = AppRole.laundryStaff;
  bool _searching = false;
  String? _note;

  /// **`super_admin` ليس في القائمة عمدًا.** القاعدة ترفضه من غير مالك
  /// المنصّة، وعرضُه هنا يَعِد بما سيُرفض.
  static const _assignable = [
    AppRole.laundryStaff,
    AppRole.driver,
    AppRole.customerService,
    AppRole.accountant,
    AppRole.branchManager,
  ];

  @override
  void dispose() {
    _term.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _note = null;
    });
    try {
      final r = await widget.staff.findUser(_term.text);
      setState(() {
        _results = r;
        if (r.isEmpty) {
          _note = 'لا حساب بهذا الرقم أو البريد. اطلب منه التسجيل في التطبيق '
              'أوّلًا، ثم أعد المحاولة.';
        }
      });
    } catch (e) {
      setState(() => _note = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إسناد دور'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _term,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الجوال أو البريد',
                hintText: '+9665XXXXXXXX',
                suffixIcon: IconButton(
                  icon: _searching
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  onPressed: _searching ? null : _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_note != null) ...[
              const SizedBox(height: 10),
              Text(_note!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13)),
            ],
            // `RadioGroup` لا `groupValue` على كل عنصر: الأخيرة مهجورة بعد
            // Flutter 3.32، والمجموعة تملك القيمة بدل تكرارها في كل صفّ.
            if (_results.isNotEmpty)
              RadioGroup<String>(
                groupValue: _selectedId,
                onChanged: (v) => setState(() {
                  _selectedId = v;
                  _selectedName = (_results.firstWhere(
                          (r) => r['id'] == v)['full_name'] as String?)
                      ?.trim();
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in _results)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: r['id'] as String,
                        title: Text(
                          (r['full_name'] as String?)?.trim().isNotEmpty == true
                              ? r['full_name'] as String
                              : (r['phone'] ?? r['email'] ?? '—').toString(),
                        ),
                        subtitle: Text(
                            (r['phone'] ?? r['email'] ?? '').toString(),
                            textDirection: TextDirection.ltr),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AppRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'الدور'),
              items: [
                for (final r in _assignable)
                  DropdownMenuItem(value: r, child: Text(r.labelAr)),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.pop(context, (userId: _selectedId!, role: _role)),
          child: Text(_selectedName == null ? 'إسناد' : 'إسناد إلى $_selectedName'),
        ),
      ],
    );
  }
}
