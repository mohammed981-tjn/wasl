import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// intl يصدّر `TextDirection` خاصًّا به يحجب نظيرَ Flutter، فيُخفى.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../services/csv.dart';
import '../../services/reports_service.dart';
import '../../services/session_service.dart';
import '../../widgets/csv_download.dart';
import '../../widgets/async_view.dart';

/// التقارير.
///
/// **كل رقمٍ هنا محسوبٌ في القاعدة.** والسبب ليس الأداء وحده: التجميع في
/// الجهاز يعطي رقمًا قد يختلف بين جهازٍ وآخر — وتقريران متضاربان أسوأ من لا
/// تقرير، لأن الخلاف حينها يكون على الرقم لا على القرار.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

/// مدًى جاهز — الأسئلة التي تُطرح فعلًا لا تواريخُ تُنتقى واحدًا واحدًا.
enum _Range {
  week('آخر ٧ أيام', 7),
  month('آخر ٣٠ يومًا', 30),
  quarter('آخر ٩٠ يومًا', 90);

  const _Range(this.labelAr, this.days);
  final String labelAr;
  final int days;
}

class _ReportsTabState extends State<ReportsTab> {
  final _reports = const ReportsService();
  late Future<
      (ReportSummary, List<DailyPoint>, List<ServiceMixRow>, List<StageDuration>)> _future;
  String? _branchId;
  _Range _range = _Range.month;

  DateTime get _from =>
      DateTime.now().subtract(Duration(days: _range.days - 1));
  DateTime get _to => DateTime.now();

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
      final id = _branchId;
      if (id == null) {
        _future = Future.value((
          ReportSummary.empty,
          <DailyPoint>[],
          <ServiceMixRow>[],
          <StageDuration>[]
        ));
        return;
      }
      _future = () async {
        final s = await _reports.summary(id, _from, _to);
        final d = await _reports.daily(id, _from, _to);
        final m = await _reports.serviceMix(id, _from, _to);
        final st = await _reports.stageDurations(id, _from, _to);
        return (s, d, m, st);
      }();
    });
  }

  Future<void> _export(String name, String csv) async {
    final ok = await downloadText(name, csv);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('نُزِّل $name')));
      return;
    }
    // لا تنزيل خارج المتصفّح — فالبديل نسخٌ صريح لا زرٌّ لا يفعل شيئًا.
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('نُسخ الجدول إلى الحافظة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money =
        NumberFormat.currency(locale: 'ar', symbol: 'ر.س', decimalDigits: 2);

    return AsyncView<
        (ReportSummary, List<DailyPoint>, List<ServiceMixRow>, List<StageDuration>)>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final (summary, daily, mix, stages) = data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Row(
              children: [
                Text('التقارير',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث'),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<_Range>(
              segments: [
                for (final r in _Range.values)
                  ButtonSegment(value: r, label: Text(r.labelAr)),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                _range = s.first;
                _reload();
              },
            ),
            const SizedBox(height: 20),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Tile(label: 'الطلبات', value: '${summary.ordersCount}'),
                _Tile(label: 'الإيراد', value: money.format(summary.revenue)),
                _Tile(
                    label: 'متوسّط الطلب',
                    value: money.format(summary.avgOrderValue)),
                _Tile(
                    label: 'إيراد التوصيل',
                    value: money.format(summary.deliveryRevenue)),
                _Tile(
                    label: 'الخصومات',
                    value: money.format(summary.discountsGiven)),
                _Tile(
                    label: 'القطع المعالَجة',
                    value: summary.piecesProcessed.toStringAsFixed(0)),
                _Tile(
                    label: 'نسبة الإلغاء',
                    value: '${summary.cancelRate.toStringAsFixed(1)}٪',
                    danger: summary.cancelRate > 10),
                _Tile(
                    label: 'متأخّر الآن',
                    value: '${summary.lateCount}',
                    danger: summary.lateCount > 0),
              ],
            ),
            const SizedBox(height: 28),

            _RevenueChart(points: daily),
            const SizedBox(height: 20),

            _ServiceMixCard(
              rows: mix,
              onExport: () => _export(
                'wasl-services-${DateFormat('yyyy-MM-dd').format(_to)}.csv',
                toCsv(
                  ['الخدمة', 'الوحدة', 'عدد الطلبات', 'الكمّية', 'الإيراد'],
                  [
                    for (final r in mix)
                      [r.serviceName, r.unit, r.ordersCount, r.quantity, r.revenue]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            _StagesCard(
              stages: stages,
              onExport: () => _export(
                'wasl-stages-${DateFormat('yyyy-MM-dd').format(_to)}.csv',
                toCsv(
                  ['المرحلة', 'العيّنات', 'المتوسّط (ساعة)', 'الوسيط (ساعة)', 'الأقصى (ساعة)'],
                  [
                    for (final s in stages)
                      [
                        OrderStatus.fromWire(s.stage).labelAr,
                        s.samples, s.avgHours, s.medianHours, s.maxHours
                      ]
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.onSurface;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: danger
                ? scheme.error.withValues(alpha: 0.4)
                : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: fg)),
          ),
        ],
      ),
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points});

  final List<DailyPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxY = points.fold<double>(0, (m, p) => p.revenue > m ? p.revenue : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الإيراد اليوميّ',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'اليوم الذي لا طلب فيه يظهر صفرًا لا يُحذف — رسمٌ يقفز فوق '
              'الأيام الفارغة يُخفي ركودًا.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY == 0 ? 10 : maxY * 1.2,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        getTitlesWidget: (v, meta) => Text(
                          v >= 1000
                              ? '${(v / 1000).toStringAsFixed(1)}k'
                              : v.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        // تسميةٌ كل بضعة أيام لا كل يوم: المحور المزدحم لا يُقرأ.
                        interval: (points.length / 6).ceilToDouble().clamp(1, 30),
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('MM-dd').format(points[i].day),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < points.length; i++)
                          FlSpot(i.toDouble(), points[i].revenue),
                      ],
                      isCurved: false,
                      color: scheme.primary,
                      barWidth: 2.5,
                      dotData: FlDotData(show: points.length <= 14),
                      belowBarData: BarAreaData(
                        show: true,
                        color: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceMixCard extends StatelessWidget {
  const _ServiceMixCard({required this.rows, required this.onExport});

  final List<ServiceMixRow> rows;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final top = rows.isEmpty ? 0.0 : rows.first.revenue;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('الخدمات الأكثر إيرادًا',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (rows.isNotEmpty)
                  TextButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('تصدير CSV'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('لا بيانات في هذه الفترة.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final r in rows.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(r.serviceName)),
                          Text('${r.quantity.toStringAsFixed(0)} × ',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text('${r.revenue.toStringAsFixed(2)} ر.س',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: top == 0 ? 0 : r.revenue / top,
                          minHeight: 5,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _StagesCard extends StatelessWidget {
  const _StagesCard({required this.stages, required this.onExport});

  final List<StageDuration> stages;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('زمن كل مرحلة',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (stages.isNotEmpty)
                  TextButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('تصدير CSV'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'محسوبٌ من سجلّ الأحداث. والوسيط مع المتوسّط: طلبٌ نُسي في آلةٍ '
              'أسبوعًا يرفع الثاني ولا يمسّ الأول — فاختلافُهما هو الإشارة.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (stages.isEmpty)
              Text('لا أحداث كافية بعد.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final s in stages)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          OrderStatus.fromWire(s.stage).labelAr,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (s.isSkewed)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Tooltip(
                            message:
                                'المتوسّط يتجاوز ضعف الوسيط — طلبٌ أو أكثر عَلِق',
                            child: Icon(Icons.warning_amber_rounded,
                                size: 18, color: scheme.error),
                          ),
                        ),
                      Text('${s.avgHours.toStringAsFixed(1)} س',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: Text(
                          'وسيط ${s.medianHours.toStringAsFixed(1)} • '
                          'أقصى ${s.maxHours.toStringAsFixed(1)}',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
