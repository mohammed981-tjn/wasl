import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';

import '../../models/enums.dart';
import '../../models/models.dart';
import '../../services/driver_service.dart';
import '../../services/location_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';
import '../customer/submit_complaint_screen.dart';

/// المهمّة الواحدة: ما يحتاجه السائق وهو واقفٌ عند الباب.
///
/// **ترتيبُ الشاشة ترتيبُ الحاجة**: العنوان أوّلًا (إليه يقود)، ثم الاتصال
/// (إن لم يجد)، ثم زرُّ الخطوة — كبيرًا في الأسفل حيث يصله الإبهام.
class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  final _driver = const DriverService();
  final _location = const LocationService();

  late Future<DriverJob?> _future;

  /// آخرُ مهمّةٍ جُلبت — يحتاجها شريطُ العنوان.
  ///
  /// **ويُضبط عند اكتمال الجلب لا في `build`.** الشريطُ العلويّ يُبنى قبل
  /// الجسد في المرور نفسه، فإسنادُه هناك يجعله يقرأ `null` أوّلَ مرّة —
  /// فلا يظهر الزرّ حتى يقع بناءٌ آخرُ لسببٍ لا علاقة له به.
  DriverJob? _job;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final uid = Db.currentUser?.id ?? '';
    final future = _driver.job(widget.orderId, uid);
    setState(() => _future = future);
    // الخطأ يعرضه `AsyncView`؛ وكلُّ ما يعنينا هنا ألّا يبقى زرُّ الشكوى
    // معروضًا على مهمّةٍ لم تُجلب.
    future.then(
      (job) {
        if (mounted) setState(() => _job = job);
      },
      onError: (Object _) {
        if (mounted) setState(() => _job = null);
      },
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _launch(Uri uri, String failure) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _say(failure);
    } catch (_) {
      _say(failure);
    }
  }

  /// الانتقال بلا إثبات: «انطلقت» و«خرجت للتوصيل».
  Future<void> _advance(OrderStatus to) async {
    setState(() => _busy = true);
    try {
      await _driver.advance(widget.orderId, to);
      _reload();
    } catch (e) {
      _say(humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishPickup() async {
    final answer = await _askNote('ملاحظة على الاستلام (اختياريّة)');
    if (answer == null) return;

    setState(() => _busy = true);
    try {
      final fix = await _location.current();
      await _driver.completePickup(widget.orderId,
          lat: fix?.lat, lng: fix?.lng, note: answer.note);
      if (fix == null) _say('سُجّل الاستلام بلا إحداثيّة — تعذّر تحديد الموقع.');
      _reload();
    } catch (e) {
      _say(humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishDelivery(DriverJob job) async {
    final result = await showDialog<({String code, String note})>(
      context: context,
      builder: (_) => const _DeliveryDialog(),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      final fix = await _location.current();
      final failure = await _driver.completeDelivery(
        widget.orderId,
        code: result.code,
        lat: fix?.lat,
        lng: fix?.lng,
        note: result.note,
      );
      if (failure != null) {
        _say(failure);
      } else {
        _say('سُلّم الطلب #${job.order.orderNumber}.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _reload();
    } catch (e) {
      _say(humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// يعيد `null` عند الإلغاء، وسجلًّا عند التأكيد.
  ///
  /// **والفرق بينهما ليس نصًّا فارغًا**: ملاحظةٌ فارغة تأكيدٌ صحيح، ولو مُيِّز
  /// الإلغاء بها لَصار إغلاقُ الحوار بلمسةٍ خارجه **استلامًا تامًّا**.
  Future<({String note})?> _askNote(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<({String note})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'سُلّم للحارس، الباب مغلق…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop((note: controller.text.trim())),
              child: const Text('تأكيد')),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المهمّة'),
        actions: [
          // **بابُ الشكوى في يد السائق أيضًا.** «العميل لا يردّ» و«العنوان
          // خاطئ» و«الطلب لم يكن جاهزًا» وقائعُ تقع في هذه الشاشة بالذات،
          // وتسجيلُها لحظتَها أدقُّ من روايتها آخرَ اليوم في مكالمة.
          if (_job != null)
            IconButton(
              tooltip: 'مشكلةٌ في هذه المهمّة',
              icon: const Icon(Icons.report_problem_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubmitComplaintScreen(
                    order: _job!.order,
                    role: 'driver',
                    parties: [
                      (
                        id: _job!.order.customerId,
                        name: _job!.order.customerName ?? 'العميل',
                        role: 'customer'
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<DriverJob?>(
        future: _future,
        onRetry: _reload,
        isEmpty: (j) => j == null,
        emptyMessage: 'المهمّة لم تعد مسنَدةً إليك.',
        builder: (context, job) {
          final j = job!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Header(job: j),
              const SizedBox(height: 16),
              _AddressCard(
                job: j,
                onNavigate: () {
                  final a = j.address;
                  if (a == null || (a.lat == 0 && a.lng == 0)) {
                    _say('لا إحداثيّة لهذا العنوان.');
                    return;
                  }
                  _launch(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${a.lat},${a.lng}'),
                    'تعذّر فتح تطبيق الخرائط.',
                  );
                },
                onCall: j.customerPhone == null
                    ? null
                    : () => _launch(Uri.parse('tel:${j.customerPhone}'),
                        'تعذّر بدء الاتصال.'),
              ),
              const SizedBox(height: 16),
              _ItemsCard(order: j.order),
              const SizedBox(height: 24),
              _ActionButton(
                job: j,
                busy: _busy,
                onAdvance: _advance,
                onFinishPickup: _finishPickup,
                onFinishDelivery: () => _finishDelivery(j),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.job});

  final DriverJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slot = job.slotStart;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${job.kind.labelAr} • #${job.order.orderNumber}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                if (job.order.isExpress)
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.bolt, size: 16),
                    label: Text('مستعجل'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(job.order.status.labelAr,
                style: TextStyle(color: scheme.primary)),
            if (slot != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16),
                  const SizedBox(width: 6),
                  Text(DateFormat('EEEE d MMMM • h:mm a', 'ar')
                      .format(slot.toLocal())),
                ],
              ),
            ],
            if (job.order.customerNotes?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('ملاحظة العميل: ${job.order.customerNotes}'),
              ),
            ],
            // الدفع عند التسليم يُعلَن هنا لا في الفاتورة: سائقٌ لم يعرف أنه
            // يقبض يعود بلا مال.
            if (job.kind == JobKind.delivery &&
                job.order.paymentStatus != PaymentStatus.paid) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'يُحصَّل عند التسليم: ${job.order.total.toStringAsFixed(2)} ر.س',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.job,
    required this.onNavigate,
    this.onCall,
  });

  final DriverJob job;
  final VoidCallback onNavigate;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final a = job.address;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.order.customerName ?? 'عميل',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (a == null)
              Text('لا عنوان مرفق بهذه المهمّة.',
                  style: Theme.of(context).textTheme.bodySmall)
            else ...[
              Text(a.summary),
              if (a.isHotel && a.checkoutDate != null)
                Text(
                  'يغادر الفندق: ${DateFormat('d MMMM', 'ar').format(a.checkoutDate!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (a.notes?.isNotEmpty == true)
                Text('علامة مميّزة: ${a.notes}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('الملاحة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(onCall == null ? 'لا رقم' : 'اتّصال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final LaundryOrder order;

  @override
  Widget build(BuildContext context) {
    if (order.items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('محتوى الطلب',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final i in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(i.serviceNameAr)),
                    Text('${i.quantity.toStringAsFixed(0)} ${i.unit.labelAr}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.job,
    required this.busy,
    required this.onAdvance,
    required this.onFinishPickup,
    required this.onFinishDelivery,
  });

  final DriverJob job;
  final bool busy;
  final void Function(OrderStatus) onAdvance;
  final VoidCallback onFinishPickup;
  final VoidCallback onFinishDelivery;

  @override
  Widget build(BuildContext context) {
    final next = job.nextStatus;
    if (next == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.flag_outlined),
          title: Text('لا خطوة تالية من هنا'),
        ),
      );
    }

    final label = switch (job.order.status) {
      OrderStatus.pickupAssigned => 'انطلقتُ للاستلام',
      OrderStatus.pickupEnRoute => 'استلمتُ الملابس',
      OrderStatus.deliveryAssigned => 'خرجتُ للتوصيل',
      OrderStatus.outForDelivery => 'سلّمتُ الطلب',
      _ => next.labelAr,
    };

    VoidCallback? action;
    if (!busy) {
      action = switch (job.order.status) {
        OrderStatus.pickupEnRoute => onFinishPickup,
        OrderStatus.outForDelivery => onFinishDelivery,
        _ => () => onAdvance(next),
      };
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: action,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label),
          ),
        ),
        if (job.isFinalStep) ...[
          const SizedBox(height: 8),
          Text(
            job.isPickup
                ? 'يُسجَّل موقعك مع الاستلام سندًا عند الخلاف.'
                : 'يُطلب رمزُ العميل، ويُسجَّل موقعك مع التسليم.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// حوار التسليم: الرمز والملاحظة معًا.
///
/// **الرمز يُطلب دائمًا وإن لم يُشترط**: الفرع قد يكون أعفى منه، والقاعدة
/// تتجاهله حينئذٍ — أمّا شاشةٌ تقرّر بنفسها ألّا تسأل فتترك السائق أمام رفضٍ
/// لا يفهمه حين يكون مشترطًا.
class _DeliveryDialog extends StatefulWidget {
  const _DeliveryDialog();

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  final _code = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إتمام التسليم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 8),
            decoration: const InputDecoration(
              labelText: 'رمز العميل',
              hintText: '0000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text('الرمز في رسالة العميل حين خرج الطلب.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياريّة)',
              hintText: 'سُلّم للحارس…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            code: _code.text.trim(),
            note: _note.text.trim(),
          )),
          child: const Text('سلّمت'),
        ),
      ],
    );
  }
}
