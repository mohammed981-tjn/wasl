import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/driver_service.dart';
import '../../services/location_service.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import 'job_screen.dart';
import 'my_record_screen.dart';

/// شاشة السائق: مهامُّ الطريق.
///
/// **قائمةٌ واحدةٌ لا لسانان**: الاستلام والتسليم لا يُفصلان في تبويبين — فمن
/// يقود سيارةً لا يقارن بين قائمتين، بل يمضي إلى **أقرب موعد** أيًّا كان نوعه.
/// والترتيب بالموعد هو ما يجعل الشاشة خريطةَ يومٍ لا جدولَ بيانات.
class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final _driver = const DriverService();
  final _location = const LocationService();

  late Future<(List<DriverJob>, List<LaundryOrder>)> _future;
  Timer? _pinger;
  bool _online = false;
  String? _pingNote;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _pinger?.cancel();
    super.dispose();
  }

  String? get _uid => Db.currentUser?.id;

  void _reload() {
    final id = _uid;
    setState(() {
      _future = id == null
          ? Future.value((<DriverJob>[], <LaundryOrder>[]))
          : () async {
              final jobs = await _driver.myJobs(id);
              final done = await _driver.doneToday(id);
              return (jobs, done);
            }();
    });
  }

  /// تشغيل النبض وإطفاؤه.
  ///
  /// **بتواترٍ من القاعدة لا من الشيفرة**: نبضةٌ كل ثانية تستنزف بطاريةً
  /// وباقةً، وكلَّ عشر دقائق تجعل الخريطة كذبًا — والفرق بينهما قرارُ إدارةٍ
  /// تعرف مدينتها.
  Future<void> _toggleOnline(bool on, String? branchId) async {
    _pinger?.cancel();
    setState(() {
      _online = on;
      _pingNote = null;
    });
    if (!on) {
      final fix = await _location.current();
      if (fix != null) {
        try {
          await _driver.ping(
              lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM, online: false);
        } catch (_) {
          // إطفاءٌ لم يصل: لا يُزعج به السائق، والصفّ سيقادم بنبضةٍ لاحقة.
        }
      }
      return;
    }

    var seconds = 60;
    if (branchId != null) {
      try {
        final s = await _driver.settings(branchId);
        if (s != null && s.locationPingSeconds > 0) seconds = s.locationPingSeconds;
      } catch (_) {
        // تعذّرت الإعدادات: يُنبض بالافتراض بدل ألّا يُنبض.
      }
    }

    await _ping();
    _pinger = Timer.periodic(Duration(seconds: seconds), (_) => _ping());
  }

  Future<void> _ping() async {
    final fix = await _location.current();
    if (fix == null) {
      if (mounted) {
        setState(() => _pingNote = 'تعذّر تحديد موقعك — تأكّد من إذن الموقع.');
      }
      return;
    }
    try {
      await _driver.ping(lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM);
      if (mounted) setState(() => _pingNote = null);
    } catch (e) {
      if (mounted) setState(() => _pingNote = humanizeDbError(e));
    }
  }

  Future<void> _open(DriverJob job) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => JobScreen(orderId: job.order.id)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final branchId = session.activeBranchId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('وصل • السائق'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'سجلّي',
            icon: const Icon(Icons.assignment_ind_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyRecordScreen()),
            ),
          ),
          IconButton(
              onPressed: session.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: AsyncView<(List<DriverJob>, List<LaundryOrder>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (jobs, done) = data;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _OnlineCard(
                  online: _online,
                  note: _pingNote,
                  onChanged: (v) => _toggleOnline(v, branchId),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('مهامّ مفتوحة',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${jobs.length}',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                if (jobs.isEmpty)
                  const _Empty()
                else
                  for (final j in jobs)
                    _JobCard(job: j, onTap: () => _open(j)),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('أنجزتَ اليوم (${done.length})',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final o in done)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text('#${o.orderNumber} — ${o.status.labelAr}'),
                      subtitle: Text(o.customerName ?? 'عميل'),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OnlineCard extends StatelessWidget {
  const _OnlineCard({
    required this.online,
    required this.onChanged,
    this.note,
  });

  final bool online;
  final ValueChanged<bool> onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: online ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: online,
              onChanged: onChanged,
              title: Text(online ? 'متاح — موقعك يُرسَل' : 'غير متاح',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(online
                  ? 'الإدارة ترى موقعك لتوجّه أقرب مهمّة إليك.'
                  : 'شغّله عند بدء الدوام.'),
            ),
            if (note != null)
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(note!,
                        style: TextStyle(fontSize: 12, color: scheme.error)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onTap});

  final DriverJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slot = job.slotStart;
    final time = slot == null
        ? 'بلا موعد'
        : DateFormat('EEEE d MMM • h:mm a', 'ar').format(slot.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: job.isPickup
                          ? scheme.tertiaryContainer
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            job.isPickup
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(job.kind.labelAr,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('#${job.order.orderNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const Spacer(),
                  if (job.order.isExpress)
                    const Icon(Icons.bolt, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(job.order.customerName ?? 'عميل',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (job.address != null)
                Text(job.address!.summary,
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14),
                  const SizedBox(width: 4),
                  Text(time, style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Text(job.order.status.labelAr,
                      style: TextStyle(fontSize: 12, color: scheme.primary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          const Text('لا مهامّ مفتوحة الآن.'),
          const SizedBox(height: 4),
          Text('ستظهر هنا فور إسنادها إليك من الإدارة.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
