import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/complaints_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// ضبطُ الشكاوى: المُهَل، والأنواع، والرسائل.
///
/// **قاعدةُ عملٍ لا تُضبط إلا بـSQL ليست مضبوطةً من الإدارة.** بنينا المُهَل
/// والأنواع والقوالب صفوفًا لا ثوابتَ في الشيفرة — وبقيت بلا شاشة، فكانت
/// «قابلةً للضبط» على الورق وحده.
class ComplaintSettingsScreen extends StatefulWidget {
  const ComplaintSettingsScreen({
    super.key,
    required this.laundryId,
    this.canEdit = true,
  });

  final String laundryId;

  /// مديرُ المغسلة والمالك. **وخدمةُ العملاء تعالج ولا تُشرّع**: من يملك
  /// تمديد مهلة التأكيد يملك إغلاق ما يشاء بالصمت.
  final bool canEdit;

  @override
  State<ComplaintSettingsScreen> createState() =>
      _ComplaintSettingsScreenState();
}

class _ComplaintSettingsScreenState extends State<ComplaintSettingsScreen> {
  final _service = const ComplaintsService();
  late Future<_Config> _load = _fetch();

  Future<_Config> _fetch() async {
    final r = await Future.wait([
      _service.settings(widget.laundryId),
      _service.allTypes(widget.laundryId),
      _service.templates(widget.laundryId),
    ]);
    return _Config(
      settings: r[0] as ComplaintSettings,
      types: r[1] as List<ComplaintType>,
      templates: r[2] as List<ComplaintTemplate>,
    );
  }

  void _reload() => setState(() => _load = _fetch());

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _say(done);
      _reload();
    } catch (e) {
      _say(humanizeDbError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ضبطُ الشكاوى'),
          bottom: const TabBar(tabs: [
            Tab(text: 'المُهَل'),
            Tab(text: 'الأنواع'),
            Tab(text: 'الرسائل'),
          ]),
        ),
        body: AsyncView<_Config>(
          future: _load,
          onRetry: _reload,
          builder: (context, cfg) => TabBarView(children: [
            _LimitsTab(
              settings: cfg.settings,
              canEdit: widget.canEdit,
              onSave: (s) => _run(
                () => _service.saveSettings(
                    laundryId: widget.laundryId, settings: s),
                'حُفظت المُهَل',
              ),
            ),
            _TypesTab(
              types: cfg.types,
              canEdit: widget.canEdit,
              onSave: (t) => _run(
                () => _service.saveType(t, laundryId: widget.laundryId),
                'حُفظ النوع',
              ),
              onDelete: (t) => _run(
                () => _service.deleteType(t.id),
                'حُذف النوع',
              ),
            ),
            _TemplatesTab(
              templates: cfg.templates,
              autoCloseDays: cfg.settings.autoCloseDays,
              canEdit: widget.canEdit,
              onSave: (t) => _run(
                () => _service.saveTemplate(t, laundryId: widget.laundryId),
                'حُفظت الرسالة',
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Config {
  const _Config({
    required this.settings,
    required this.types,
    required this.templates,
  });
  final ComplaintSettings settings;
  final List<ComplaintType> types;
  final List<ComplaintTemplate> templates;
}

// ═══════════════════════════════════════════════════════════════════════════
// المُهَل
// ═══════════════════════════════════════════════════════════════════════════

class _LimitsTab extends StatefulWidget {
  const _LimitsTab({
    required this.settings,
    required this.canEdit,
    required this.onSave,
  });
  final ComplaintSettings settings;
  final bool canEdit;
  final ValueChanged<ComplaintSettings> onSave;

  @override
  State<_LimitsTab> createState() => _LimitsTabState();
}

class _LimitsTabState extends State<_LimitsTab> {
  late bool _enabled = widget.settings.isEnabled;
  late bool _general = widget.settings.allowGeneralTickets;
  late double _window = widget.settings.windowHours.toDouble();
  late double _sla = widget.settings.responseSlaHours.toDouble();
  late double _autoClose = widget.settings.autoCloseDays.toDouble();
  late double _warn = widget.settings.driverWarningThreshold.toDouble();

  @override
  Widget build(BuildContext context) {
    final on = widget.canEdit;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          onChanged: on ? (v) => setState(() => _enabled = v) : null,
          title: const Text('استقبالُ الشكاوى'),
          subtitle: const Text(
            'إيقافُه يخفي بابَ الشكوى من التطبيقات. ولا يمنع الشكوى — '
            'يحوّلها إلى مكالمة.',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
        const Divider(),

        _Dial(
          label: 'مهلةُ فتح الشكوى بعد التسليم',
          value: _window,
          min: 1,
          max: 720,
          divisions: 60,
          unit: 'ساعة',
          hint: 'بعدها يُقفل بابُ الشكوى على الطلب. والطلبُ الجاري مفتوحٌ '
              'دائمًا — لا معنى لمهلةٍ على شيءٍ لم ينتهِ بعد.',
          enabled: on,
          onChanged: (v) => setState(() => _window = v),
        ),

        _Dial(
          label: 'وعدُ الردّ',
          value: _sla,
          min: 1,
          max: 168,
          divisions: 167,
          unit: 'ساعة',
          hint: 'لا يُنفَّذ آليًّا — يُقاس ويُعرض تجاوزُه في الطابور. '
              'ووعدٌ لا يُقاس ليس وعدًا.',
          enabled: on,
          onChanged: (v) => setState(() => _sla = v),
        ),

        _Dial(
          label: 'مهلةُ تأكيد الشاكي',
          value: _autoClose,
          min: 1,
          max: 30,
          divisions: 29,
          unit: 'يوم',
          hint: 'بعد الحلّ يُسأل الشاكي: هل حُلّت فعلًا؟ فإن سكت هذه المدّة '
              'أُغلق ملفُّه — ويُختم أنّه إغلاقٌ بالصمت لا بالرضا. '
              'ولا يُغلق على من لم تبلغه رسالةُ الحلّ.',
          enabled: on,
          onChanged: (v) => setState(() => _autoClose = v),
        ),

        _Dial(
          label: 'حدُّ إنذارات السائق',
          value: _warn,
          min: 1,
          max: 20,
          divisions: 19,
          unit: 'إنذار',
          hint: 'ببلوغه يُمنع السائق من قبول الجديد — ولا تُقطع جولتُه '
              'الجارية. والإنذارُ الساري وحده يُعدّ.',
          enabled: on,
          onChanged: (v) => setState(() => _warn = v),
        ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _general,
          onChanged: on ? (v) => setState(() => _general = v) : null,
          title: const Text('قبولُ تذكرةٍ بلا طلب'),
          subtitle: const Text(
            'استفسارٌ ماليّ أو تحديثُ بيانات — لا كلُّ سؤالٍ يخصّ طلبًا.',
            style: TextStyle(fontSize: 12.5),
          ),
        ),

        const SizedBox(height: 20),
        if (on)
          FilledButton.icon(
            onPressed: () => widget.onSave(ComplaintSettings(
              isEnabled: _enabled,
              windowHours: _window.round(),
              responseSlaHours: _sla.round(),
              autoCloseDays: _autoClose.round(),
              driverWarningThreshold: _warn.round(),
              allowGeneralTickets: _general,
            )),
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        else
          const Text('العرضُ فقط — التعديلُ لمدير المغسلة فأعلى.',
              style: TextStyle(color: Colors.black54)),
      ],
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.hint,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final String hint;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text('${value.round()} $unit',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
            ]),
            Text(hint,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// الأنواع
// ═══════════════════════════════════════════════════════════════════════════

/// **الأنواعُ قائمةٌ مغلقة — وهذه هي الشاشة التي تجعلها قائمةَ الإدارة لا
/// قائمتي.** مغسلةٌ تعطّر الملابس تحتاج «العطر المطلوب لم يُستخدم»، وأخرى لا
/// تعرف العطر أصلًا.
class _TypesTab extends StatelessWidget {
  const _TypesTab({
    required this.types,
    required this.canEdit,
    required this.onSave,
    required this.onDelete,
  });

  final List<ComplaintType> types;
  final bool canEdit;
  final ValueChanged<ComplaintType> onSave;
  final ValueChanged<ComplaintType> onDelete;

  static const _roles = <String?, String>{
    null: 'كلُّ الأدوار',
    'customer': 'العميل',
    'driver': 'السائق',
    'laundry_staff': 'المغسلة',
  };

  Future<void> _edit(BuildContext context, ComplaintType? existing) async {
    final result = await showDialog<ComplaintType>(
      context: context,
      builder: (_) => _TypeDialog(existing: existing),
    );
    if (result != null) onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    final byRole = <String?, List<ComplaintType>>{};
    for (final t in types) {
      byRole.putIfAbsent(t.forRole, () => []).add(t);
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          const Text(
            'الأنواعُ قائمةٌ مغلقة، وهي التي يُجمَّع عليها التقرير. ونصٌّ '
            'حرٌّ لا يُجمَّع — فلا يُعرف أبدًا أنّ سبعَ شكاوى هذا الأسبوع عن '
            'فرعٍ بعينه.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          for (final role in [null, 'customer', 'driver', 'laundry_staff'])
            if ((byRole[role] ?? const []).isNotEmpty) ...[
              Text('يفتحها: ${_roles[role]}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final t in byRole[role]!)
                _TypeTile(
                  type: t,
                  canEdit: canEdit,
                  onTap: () => _edit(context, t),
                  onToggle: () => onSave(t.copyWith(isActive: !t.isActive)),
                  onDelete: () => onDelete(t),
                ),
              const SizedBox(height: 14),
            ],
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('نوعٌ جديد'),
            )
          : null,
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.canEdit,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final ComplaintType type;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = type;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: canEdit ? onTap : null,
        title: Text(
          t.labelAr,
          style: TextStyle(
            // المعطَّلُ يُعرض مشطوبًا لا مخفيًّا: الإدارةُ تحتاج أن ترى ما
            // عطّلته كي تعيده.
            decoration: t.isActive ? null : TextDecoration.lineThrough,
            color: t.isActive ? null : Colors.black45,
          ),
        ),
        subtitle: Text(
          [
            t.code,
            if (t.allowsGeneral) 'يُقبل بلا طلب',
          ].join(' • '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: canEdit
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: t.isActive ? 'تعطيل' : 'تفعيل',
                  icon: Icon(t.isActive
                      ? Icons.toggle_on
                      : Icons.toggle_off_outlined),
                  onPressed: onToggle,
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ])
            : null,
      ),
    );
  }
}

class _TypeDialog extends StatefulWidget {
  const _TypeDialog({this.existing});
  final ComplaintType? existing;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final _label =
      TextEditingController(text: widget.existing?.labelAr ?? '');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late String? _forRole = widget.existing?.forRole;
  late String? _against = widget.existing?.suggestedAgainst;
  late bool _general = widget.existing?.allowsGeneral ?? false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _label.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_isNew ? 'نوعٌ جديد' : 'تعديلُ النوع'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _label,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'الاسمُ المعروض',
                helperText: 'ما يقرؤه الشاكي في القائمة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: _isNew,
              decoration: InputDecoration(
                labelText: 'الرمز',
                // **ولا يُبدَّل بعد الاستعمال**: التقريرُ يُجمَّع عليه،
                // وتبديلُه يجعل تقريرَ الشهر الماضي يقول غيرَ ما وقع.
                helperText: _isNew
                    ? 'حروفٌ لاتينيّة — يُجمَّع عليه التقرير ولا يتغيّر بعدها'
                    : 'ثابتٌ بعد الإنشاء — التقريرُ يُجمَّع عليه',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _forRole,
              decoration: const InputDecoration(
                labelText: 'من يفتحه؟',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('كلُّ الأدوار')),
                DropdownMenuItem(value: 'customer', child: Text('العميل')),
                DropdownMenuItem(value: 'driver', child: Text('السائق')),
                DropdownMenuItem(
                    value: 'laundry_staff', child: Text('المغسلة')),
              ],
              onChanged: (v) => setState(() => _forRole = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _against,
              decoration: const InputDecoration(
                labelText: 'الطرفُ المقترَح',
                helperText: 'يُملأ به الحقل، ويبقى للشاكي تغييرُه',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('لا أحد')),
                DropdownMenuItem(value: 'customer', child: Text('العميل')),
                DropdownMenuItem(value: 'driver', child: Text('السائق')),
                DropdownMenuItem(
                    value: 'laundry_staff', child: Text('المغسلة')),
              ],
              onChanged: (v) => setState(() => _against = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _general,
              onChanged: (v) => setState(() => _general = v ?? false),
              title: const Text('يُقبل بلا طلب', style: TextStyle(fontSize: 14)),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجُع'),
          ),
          FilledButton(
            onPressed: _label.text.trim().isEmpty ||
                    (_isNew && _code.text.trim().isEmpty)
                ? null
                : () => Navigator.pop(
                      context,
                      ComplaintType(
                        id: widget.existing?.id ?? '',
                        code: _code.text.trim(),
                        labelAr: _label.text.trim(),
                        forRole: _forRole,
                        suggestedAgainst: _against,
                        allowsGeneral: _general,
                        isActive: widget.existing?.isActive ?? true,
                        sortOrder: widget.existing?.sortOrder ?? 100,
                      ),
                    ),
            child: const Text('حفظ'),
          ),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// الرسائل
// ═══════════════════════════════════════════════════════════════════════════

/// **وتُعرض الأحداثُ كلُّها لا الموجودَ منها وحده.** السؤالُ الحقيقيّ ليس
/// «ما القوالب عندي؟» بل **«أين ينقطع الكلام مع الشاكي؟»** — وقائمةٌ تعرض
/// الموجود فقط لا تجيبه.
///
/// وحدثُ «حُلّت» يُعلَّم صراحةً: بلا رسالته **لا يُغلق ملفٌّ بالصمت أبدًا**،
/// لأنّ الكنس يشترط أن يكون صاحبُها قد سُئل. فغيابُه ليس نقصَ لطفٍ بل تعطيلُ
/// دورة الحياة كلِّها.
class _TemplatesTab extends StatelessWidget {
  const _TemplatesTab({
    required this.templates,
    required this.autoCloseDays,
    required this.canEdit,
    required this.onSave,
  });

  final List<ComplaintTemplate> templates;
  final int autoCloseDays;
  final bool canEdit;
  final ValueChanged<ComplaintTemplate> onSave;

  Future<void> _edit(
    BuildContext context,
    ComplaintEvent event,
    ComplaintTemplate? existing,
  ) async {
    final result = await showDialog<ComplaintTemplate>(
      context: context,
      builder: (_) => _TemplateDialog(
        event: event,
        existing: existing,
        autoCloseDays: autoCloseDays,
      ),
    );
    if (result != null) onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    final byEvent = <ComplaintEvent, List<ComplaintTemplate>>{};
    for (final t in templates) {
      byEvent.putIfAbsent(t.event, () => []).add(t);
    }

    final resolvedMissing =
        (byEvent[ComplaintEvent.resolved] ?? const []).where((t) => t.isActive).isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (resolvedMissing) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'لا رسالةَ لحدث «حُلّت» — ولن يُغلق ملفٌّ بالصمت أبدًا. '
                  'الكنسُ لا يُغلق على من لم يبلغه ردٌّ، والشكاوى المحلولة '
                  'ستتراكم في الطابور.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        for (final e in ComplaintEvent.values) ...[
          Row(children: [
            Expanded(
              child: Text(e.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (e.isLoadBearing)
              const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('يقوم عليها الإغلاق',
                    style: TextStyle(fontSize: 11)),
              ),
          ]),
          Text(e.hint,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          if ((byEvent[e] ?? const []).isEmpty)
            Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: ListTile(
                leading: const Icon(Icons.notifications_off_outlined,
                    color: Colors.black38),
                title: const Text('لا رسالة',
                    style: TextStyle(color: Colors.black45)),
                trailing: canEdit
                    ? TextButton(
                        onPressed: () => _edit(context, e, null),
                        child: const Text('أضِف'),
                      )
                    : null,
              ),
            )
          else
            for (final t in byEvent[e]!)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: canEdit ? () => _edit(context, e, t) : null,
                  title: Text(t.titleAr?.isNotEmpty == true
                      ? t.titleAr!
                      : t.bodyAr.split('\n').first),
                  subtitle: Text(
                    '${_channelLabel(t.channel)} • ${_audienceLabel(t.audience)}'
                    '${t.isActive ? '' : ' • معطَّلة'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
                ),
              ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  static String _channelLabel(String c) => switch (c) {
        'in_app' => 'داخل التطبيق',
        'push' => 'إشعارُ دفع',
        'sms' => 'رسالةٌ نصّيّة',
        'whatsapp' => 'واتساب',
        'email' => 'بريد',
        _ => c,
      };

  static String _audienceLabel(String a) => switch (a) {
        'customer' => 'الشاكي',
        'driver' => 'الشاكي',
        'laundry_staff' => 'الشاكي',
        'customer_service' => 'خدمةُ العملاء',
        'branch_manager' => 'مديرُ الفرع',
        _ => a,
      };
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({
    required this.event,
    required this.autoCloseDays,
    this.existing,
  });

  final ComplaintEvent event;
  final int autoCloseDays;
  final ComplaintTemplate? existing;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _title =
      TextEditingController(text: widget.existing?.titleAr ?? '');
  late final _body = TextEditingController(text: widget.existing?.bodyAr ?? '');
  late String _channel = widget.existing?.channel ?? 'in_app';
  late String _audience = widget.existing?.audience ??
      (widget.event == ComplaintEvent.opened ||
              widget.event == ComplaintEvent.reopened
          ? 'customer_service'
          : 'customer');
  late bool _active = widget.existing?.isActive ?? true;

  bool get _isNew => widget.existing == null;

  /// المتغيّراتُ المتاحة — تُنقر فتُدرَج في موضع المؤشّر.
  static const _vars = [
    '{رقم_الشكوى}',
    '{نوع_الشكوى}',
    '{رقم_الطلب}',
    '{الفرع}',
    '{مهلة_التأكيد}',
    '{ردّ_الإدارة}',
  ];

  void _insert(String v) {
    final sel = _body.selection;
    final text = _body.text;
    // موضعُ المؤشّر قد يكون غير صالحٍ قبل أوّل لمسةٍ للحقل — فيُلحق بالآخر.
    final at = sel.isValid ? sel.start : text.length;
    _body.text = text.replaceRange(at, sel.isValid ? sel.end : at, v);
    _body.selection = TextSelection.collapsed(offset: at + v.length);
    setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loadBearing = widget.event.isLoadBearing;
    return AlertDialog(
      title: Text('رسالةُ «${widget.event.label}»'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (loadBearing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'هذه الرسالةُ تحمل السؤال الذي يُغلق الملفّ. اجعلها تقول '
                  'ثلاثةً: ردَّ الإدارة، وأنّ جوابَه مطلوب، وأنّ للمهلة '
                  'نهاية (${widget.autoCloseDays} أيّام). وبلا واحدةٍ منها '
                  'يصير الإغلاقُ بالصمت إغلاقًا بالجهل.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            if (_isNew) ...[
              DropdownButtonFormField<String>(
                initialValue: _channel,
                decoration: const InputDecoration(
                  labelText: 'القناة',
                  helperText: 'داخلُ التطبيق تعمل بلا مزوّدٍ خارجيّ',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'in_app', child: Text('داخل التطبيق')),
                  DropdownMenuItem(value: 'push', child: Text('إشعارُ دفع')),
                  DropdownMenuItem(value: 'sms', child: Text('رسالةٌ نصّيّة')),
                  DropdownMenuItem(value: 'whatsapp', child: Text('واتساب')),
                ],
                onChanged: (v) => setState(() => _channel = v ?? 'in_app'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _audience,
                decoration: const InputDecoration(
                  labelText: 'إلى مَن',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('الشاكي')),
                  DropdownMenuItem(
                      value: 'customer_service', child: Text('خدمةُ العملاء')),
                ],
                onChanged: (v) => setState(() => _audience = v ?? 'customer'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _title,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'العنوان (اختياريّ)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 6,
              textDirection: TextDirection.rtl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'المتن',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in _vars)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(v, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _insert(v),
                    ),
                ],
              ),
            ),
            if (!_isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('مفعَّلة', style: TextStyle(fontSize: 14)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تراجُع'),
        ),
        FilledButton(
          onPressed: _body.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    ComplaintTemplate(
                      id: widget.existing?.id ?? '',
                      event: widget.event,
                      channel: _channel,
                      audience: _audience,
                      titleAr: _title.text.trim(),
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
