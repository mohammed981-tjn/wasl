import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/marketing_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// قوالب الإشعارات.
///
/// **تُعرض الرحلة كاملةً لا القوالب الموجودة وحدها.** الحالة التي لا قالب لها
/// تظهر رماديةً بزرّ «أضِف» — لأن السؤال الحقيقيّ ليس «ما القوالب عندي؟» بل
/// **«أين ينقطع الكلام مع العميل؟»**، وقائمةٌ تعرض الموجود فقط لا تجيبه.
class TemplatesTab extends StatefulWidget {
  const TemplatesTab({super.key});

  @override
  State<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<TemplatesTab> {
  final _templates = const TemplatesService();
  late Future<List<NotificationTemplate>> _future;
  String? _laundryId;

  /// المراحل التي يهمّ العميلَ أن يُخبَر بها. وليست كل الحالات: «جاري الفرز»
  /// تفصيلٌ داخليّ، ورسالةٌ لكل خطوةٍ إزعاجٌ يُوقِف الإشعارات كلّها.
  static const _customerFacing = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.pickupEnRoute,
    OrderStatus.pickedUp,
    OrderStatus.atLaundry,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.onHold,
    OrderStatus.cancelled,
  ];

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
      _future = _laundryId == null
          ? Future.value(const <NotificationTemplate>[])
          : _templates.ofLaundry(_laundryId!);
    });
  }

  bool get _canEdit => context
      .read<SessionService>()
      .hasRoleInActiveBranch({AppRole.branchManager});

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(humanizeDbError(e))));
  }

  Future<void> _edit(OrderStatus status, NotificationTemplate? existing) async {
    final laundryId = _laundryId;
    if (laundryId == null) return;

    final result = await showDialog<NotificationTemplate?>(
      context: context,
      builder: (_) => _TemplateDialog(
        laundryId: laundryId,
        status: status,
        existing: existing,
      ),
    );
    if (result == null) return;

    try {
      await _templates.save(result);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _remove(NotificationTemplate t) async {
    try {
      await _templates.remove(t.id);
      _reload();
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;

    return AsyncView<List<NotificationTemplate>>(
      future: _future,
      onRetry: _reload,
      builder: (context, all) {
        final byStatus = <OrderStatus, List<NotificationTemplate>>{};
        for (final t in all) {
          byStatus.putIfAbsent(t.triggerStatus, () => []).add(t);
        }

        final silent = _customerFacing
            .where((s) => (byStatus[s] ?? const []).isEmpty)
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('رسائل العميل',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              canEdit
                  ? 'النصّ يُعدَّل من هنا — بلا إصدار تطبيق جديد.'
                  : 'العرض فقط: التعديل لمدير الفرع فأعلى.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (silent > 0) ...[
              const SizedBox(height: 12),
              _SilentBanner(count: silent),
            ],
            const SizedBox(height: 16),
            for (final s in _customerFacing)
              _StatusGroup(
                status: s,
                templates: byStatus[s] ?? const [],
                canEdit: canEdit,
                onAdd: () => _edit(s, null),
                onEdit: (t) => _edit(s, t),
                onRemove: _remove,
              ),
          ],
        );
      },
    );
  }
}

class _SilentBanner extends StatelessWidget {
  const _SilentBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count مرحلة تمرّ بلا رسالة. والعميل الذي لا يُخبَر يتصل — '
              'أو يظنّ طلبه ضاع.',
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusGroup extends StatelessWidget {
  const _StatusGroup({
    required this.status,
    required this.templates,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final OrderStatus status;
  final List<NotificationTemplate> templates;
  final bool canEdit;
  final VoidCallback onAdd;
  final void Function(NotificationTemplate) onEdit;
  final void Function(NotificationTemplate) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final silent = templates.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  silent ? Icons.circle_outlined : Icons.check_circle,
                  size: 18,
                  color: silent ? scheme.outline : scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(status.labelAr,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: silent ? scheme.outline : null)),
                const Spacer(),
                if (canEdit)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('رسالة'),
                  ),
              ],
            ),
            if (silent)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 26),
                child: Text('لا رسالة — تمرّ هذه المرحلة بصمت.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            else
              for (final t in templates)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 26),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(t.channel.labelAr,
                            style: const TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (t.titleAr?.isNotEmpty == true)
                              Text(t.titleAr!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            // تُعرض المعاينة بقيمٍ نموذجية لا النصّ الخام:
                            // «{رقم_الطلب}» لا يُقرأ، و«#10042» يُقرأ.
                            Text(t.preview(),
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                            if (!t.isActive)
                              Text('موقوفة',
                                  style: TextStyle(
                                      fontSize: 11, color: scheme.error)),
                          ],
                        ),
                      ),
                      if (canEdit) ...[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => onEdit(t),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => onRemove(t),
                        ),
                      ],
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({
    required this.laundryId,
    required this.status,
    this.existing,
  });

  final String laundryId;
  final OrderStatus status;
  final NotificationTemplate? existing;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late NotificationChannel _channel;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.titleAr ?? '');
    _body = TextEditingController(text: e?.bodyAr ?? '');
    _channel = e?.channel ?? NotificationChannel.push;
    _active = e?.isActive ?? true;
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _insert(String variable) {
    final sel = _body.selection;
    final text = _body.text;
    final token = '{$variable}';
    final at = sel.isValid ? sel.start : text.length;
    _body.text = text.replaceRange(at, sel.isValid ? sel.end : at, token);
    _body.selection = TextSelection.collapsed(offset: at + token.length);
  }

  String _preview() {
    var out = _body.text;
    const sample = {
      'رقم_الطلب': '10042',
      'الفرع': 'فرع المركز',
      'الإجمالي': '115.00',
    };
    sample.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('رسالة عند «${widget.status.labelAr}»'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<NotificationChannel>(
                initialValue: _channel,
                decoration: const InputDecoration(labelText: 'القناة'),
                items: [
                  for (final c in NotificationChannel.values)
                    DropdownMenuItem(value: c, child: Text(c.labelAr)),
                ],
                onChanged: (v) => setState(() => _channel = v ?? _channel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياريّ)',
                  hintText: 'تم استلام ملابسك',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'النصّ',
                  hintText: 'استلمنا طلبك رقم {رقم_الطلب} من {الفرع}.',
                ),
              ),
              const SizedBox(height: 10),
              Text('أدرِج متغيّرًا:',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final v in NotificationTemplate.variables)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('{$v}', style: const TextStyle(fontSize: 12)),
                      onPressed: () => _insert(v),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // المعاينة حيّة: من يكتب «{رقم_الطلب}» يجب أن يرى «#10042» قبل
              // أن يراها عميل — والخطأ في اسم متغيّر يظهر نصًّا خامًّا لا فراغًا.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المعاينة',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      _body.text.trim().isEmpty
                          ? 'اكتب النصّ لترى معاينته'
                          : _preview(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _body.text.trim().isEmpty
                            ? scheme.outline
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('مفعّلة'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _body.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    NotificationTemplate(
                      id: widget.existing?.id ?? '',
                      laundryId: widget.laundryId,
                      triggerStatus: widget.status,
                      channel: _channel,
                      audience: AppRole.customer,
                      titleAr: _title.text.trim().isEmpty
                          ? null
                          : _title.text.trim(),
                      bodyAr: _body.text.trim(),
                      isActive: _active,
                    ),
                  ),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
