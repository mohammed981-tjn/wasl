import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// بوّابة الدفع.
///
/// **ما يُضبط هنا وما لا يُضبط**: يُضبط اسمُ المزوّد والوسائل والمفتاح
/// **المنشور**. ولا يُضبط مفتاحُ السرّ — لا هنا ولا في أيّ شاشة: مكانُه أسرارُ
/// دوالّ Edge، لأن ما يُكتب في القاعدة يُقرأ من القاعدة، وما يُرسل إلى حزمةٍ
/// يُستخرج منها.
class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _laundryId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = context.watch<SessionService>().activeBranch?.laundryId;
    if (id != _laundryId) {
      _laundryId = id;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      final id = _laundryId;
      _future = id == null
          ? Future.value(const <Map<String, dynamic>>[])
          : Db.client
              .from('payment_providers')
              .select()
              .eq('laundry_id', id)
              .order('created_at')
              .then((r) => (r as List).cast<Map<String, dynamic>>());
    });
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
  }

  Future<void> _save({
    String? id,
    required String code,
    required String name,
    required List<String> methods,
    required String publishableKey,
    required bool active,
  }) async {
    final laundryId = _laundryId;
    if (laundryId == null) return;
    try {
      final row = {
        'laundry_id': laundryId,
        'code': code,
        'display_name_ar': name,
        'methods': methods,
        'publishable_key': publishableKey.trim().isEmpty ? null : publishableKey.trim(),
        'is_active': active,
        'is_default': true,
      };
      if (id == null) {
        await Db.client.from('payment_providers').insert(row);
      } else {
        await Db.client.from('payment_providers').update(row).eq('id', id);
      }
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('حُفظ المزوّد.')));
      }
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    // سياسة `payment_providers_write` تشترط مالك المنصّة — والشاشة تقول ذلك
    // بدل أن تدع مدير الفرع يضغط «حفظ» فيُرفض بلا تفسير.
    final canEdit = session.isSuperAdmin;

    return AsyncView<List<Map<String, dynamic>>>(
      future: _future,
      onRetry: _reload,
      builder: (context, providers) {
        final moyasar = providers
            .cast<Map<String, dynamic>?>()
            .firstWhere((p) => p?['code'] == 'moyasar', orElse: () => null);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('بوّابة الدفع',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'تفعيلُ البطاقة يُظهر خيارها للعميل عند إتمام الطلب.'
                  : 'العرض فقط: ربط بوّابة الدفع لمالك المنصّة.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _ProviderCard(
              existing: moyasar,
              canEdit: canEdit,
              onSave: _save,
            ),
            const SizedBox(height: 20),
            const _ServerSecretsCard(),
          ],
        );
      },
    );
  }
}

class _ProviderCard extends StatefulWidget {
  const _ProviderCard({
    required this.existing,
    required this.canEdit,
    required this.onSave,
  });

  final Map<String, dynamic>? existing;
  final bool canEdit;
  final void Function({
    String? id,
    required String code,
    required String name,
    required List<String> methods,
    required String publishableKey,
    required bool active,
  }) onSave;

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  late final _name = TextEditingController(
      text: widget.existing?['display_name_ar'] as String? ?? 'ميسر');
  late final _key = TextEditingController(
      text: widget.existing?['publishable_key'] as String? ?? '');
  late bool _active = widget.existing?['is_active'] as bool? ?? false;
  late final Set<String> _methods = {
    ...((widget.existing?['methods'] as List?)?.cast<String>() ??
        const ['card']),
  };

  static const _selectable = [
    PaymentMethod.card,
    PaymentMethod.applePay,
  ];

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.canEdit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ميسر (Moyasar)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('mada وVisa وMastercard وApple Pay.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: enabled ? (v) => setState(() => _active = v) : null,
              title: const Text('مفعَّل'),
              subtitle: const Text(
                  'لا تُفعّله قبل ضبط مفتاح السرّ في أسرار دوالّ Edge — '
                  'وإلّا رأى العميل خيارًا يفشل عند الضغط.'),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _name,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'الاسم المعروض',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'المفتاح المنشور (pk_…)',
                helperText: 'المنشور فقط. مفتاح السرّ لا يُكتب هنا أبدًا.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              children: [
                for (final m in _selectable)
                  FilterChip(
                    label: Text(m.labelAr),
                    selected: _methods.contains(m.wireName),
                    onSelected: enabled
                        ? (v) => setState(() {
                              if (v) {
                                _methods.add(m.wireName);
                              } else {
                                _methods.remove(m.wireName);
                              }
                            })
                        : null,
                  ),
              ],
            ),

            if (enabled) ...[
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  onPressed: () => widget.onSave(
                    id: widget.existing?['id'] as String?,
                    code: 'moyasar',
                    name: _name.text.trim().isEmpty ? 'ميسر' : _name.text.trim(),
                    methods: _methods.toList(),
                    publishableKey: _key.text,
                    active: _active,
                  ),
                  child: const Text('حفظ'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ما يُضبط خارج هذه الشاشة — يُقال صراحةً كي لا يُبحث عنه.
class _ServerSecretsCard extends StatelessWidget {
  const _ServerSecretsCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.vpn_key_outlined, size: 18),
                SizedBox(width: 8),
                Text('ما يُضبط في الخادم لا هنا',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 10),
            const _Secret(
              name: 'MOYASAR_SECRET_KEY',
              what: 'مفتاح السرّ من لوحة ميسر. بلا هذا لا تُفتح صفحة دفع.',
            ),
            const _Secret(
              name: 'MOYASAR_WEBHOOK_SECRET',
              what: 'رمزٌ تختاره وتضعه في إعداد الإشعارات عند ميسر — '
                  'وبه يُعرف الإشعار الصادق من الملفَّق.',
            ),
            const _Secret(
              name: 'PAYMENT_CALLBACK_URL',
              what: 'إلى أين يعود العميل بعد الدفع (اختياريّ).',
            ),
            const SizedBox(height: 10),
            Text(
              'تُضبط في: Supabase ← Edge Functions ← Secrets. '
              'والدوالّ الثلاث المنشورة: payments-start و payments-webhook '
              'و payments-refund.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Secret extends StatelessWidget {
  const _Secret({required this.name, required this.what});

  final String name;
  final String what;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            Text(what, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
