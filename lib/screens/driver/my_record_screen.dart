import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/models.dart';
import '../../services/complaints_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../customer/my_complaints_screen.dart' show ComplaintCard;

/// «سجلّي» — إنذاراتُ السائق وشكاواه هو.
///
/// **العقوبةُ السرّيّة ليست تقويمًا.** سائقٌ يُمنع من قبول الجديد ولا يعرف
/// لماذا يظنّ العطلَ في التطبيق أو ظلمًا في الإدارة، ولا يصحّح شيئًا. فيُعرض
/// له ما عليه: متى، وعلامَ، وهل سقط أم لا يزال ساريًا.
///
/// **ولا يُعرض له اسمُ من اشتكى.** هو يقرأ سببَ الإنذار لا هويّةَ الشاكي —
/// وذلك يحرسه سياسةُ القاعدة لا هذه الشاشة.
class MyRecordScreen extends StatefulWidget {
  const MyRecordScreen({super.key});

  @override
  State<MyRecordScreen> createState() => _MyRecordScreenState();
}

class _MyRecordScreenState extends State<MyRecordScreen> {
  final _service = const ComplaintsService();
  late Future<_Record> _load = _fetch();

  Future<_Record> _fetch() async {
    final uid = Db.currentUser?.id;
    if (uid == null) return const _Record(warnings: [], complaints: []);
    final results = await Future.wait([
      _service.warnings(uid),
      _service.mine(),
    ]);
    return _Record(
      warnings: results[0] as List<DriverWarning>,
      complaints: results[1] as List<Complaint>,
    );
  }

  void _reload() => setState(() => _load = _fetch());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجلّي')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<_Record>(
          future: _load,
          onRetry: _reload,
          builder: (context, r) {
            final active = r.warnings.where((w) => w.isActive).length;
            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _WarningsHeader(active: active, total: r.warnings.length),
                const SizedBox(height: 10),
                if (r.warnings.isEmpty)
                  const _Empty(text: 'لا إنذارات على سجلّك.')
                else
                  for (final w in r.warnings) ...[
                    _WarningTile(warning: w),
                    const SizedBox(height: 8),
                  ],

                const SizedBox(height: 20),
                const Text('شكاويّ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text(
                  'ما فتحتَه أنت: عميلٌ لا يردّ، أو عنوانٌ خاطئ، أو طلبٌ لم '
                  'يكن جاهزًا في الفرع.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                if (r.complaints.isEmpty)
                  const _Empty(text: 'لم تفتح شكوى بعد.')
                else
                  for (final c in r.complaints) ...[
                    ComplaintCard(
                        complaint: c, role: 'driver', onChanged: _reload),
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Record {
  const _Record({required this.warnings, required this.complaints});
  final List<DriverWarning> warnings;
  final List<Complaint> complaints;
}

class _WarningsHeader extends StatelessWidget {
  const _WarningsHeader({required this.active, required this.total});
  final int active;
  final int total;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('الإنذارات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            if (active > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$active سارٍ',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            total == 0
                ? 'الإنذارُ يُسجَّل على شكوى، ويسقط بمرور مدّته، ويُلغى إن '
                    'راجعتْه الإدارة فبرّأتك.'
                : 'الساري وحده يُعدّ. وببلوغ حدّ الفرع تُمنع من قبول الجديد — '
                    'ولا تُقطع جولةٌ في يدك.',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
        ],
      );
}

class _WarningTile extends StatelessWidget {
  const _WarningTile({required this.warning});
  final DriverWarning warning;

  @override
  Widget build(BuildContext context) {
    final w = warning;
    final fmt = DateFormat('d MMMM yyyy', 'ar');
    final (color, label) = w.revokedAt != null
        ? (Colors.green, 'أُلغي')
        : w.isActive
            ? (Colors.orange, 'سارٍ')
            : (Colors.grey, 'سقط');

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.gavel, color: color),
        title: Text(w.reason),
        subtitle: Text([
          fmt.format(w.createdAt),
          if (w.revokedReason != null) w.revokedReason!,
          if (w.revokedAt == null && w.expiresAt != null && w.isActive)
            'يسقط في ${fmt.format(w.expiresAt!)}',
        ].join(' • ')),
        trailing: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text,
            style: const TextStyle(color: Colors.black45),
            textAlign: TextAlign.center),
      );
}
