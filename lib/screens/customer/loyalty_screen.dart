import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/models.dart';
import '../../services/feedback_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/async_view.dart';

/// نقاطي: الرصيد وسجلُّه.
///
/// **السجلّ يُعرض لا الرصيد وحده**: رقمٌ ينقص بلا بيانٍ يُقرأ خطأً، ومن رأى
/// «صُرفت على الطلب ١٠٠٤٢» لم يسأل الدعم.
class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key, required this.laundryId});

  final String laundryId;

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _feedback = const FeedbackService();
  late Future<(LoyaltyState, List<LoyaltyTxn>)> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final userId = Db.currentUser?.id;
    setState(() {
      _future = userId == null
          ? Future.value((const LoyaltyState(balance: 0), <LoyaltyTxn>[]))
          : () async {
              final state = await _feedback.loyalty(
                  userId: userId, laundryId: widget.laundryId);
              final history = await _feedback.loyaltyHistory(
                  userId: userId, laundryId: widget.laundryId);
              return (state, history);
            }();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('d MMMM • h:mm a', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('نقاطي'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<(LoyaltyState, List<LoyaltyTxn>)>(
        future: _future,
        onRetry: _reload,
        builder: (context, data) {
          final (state, history) = data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('${state.balance}',
                          style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: scheme.primary)),
                      const Text('نقطة',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('تُصرف من فاتورتك عند إتمام الطلب — للصرف حدٌّ أدنى '
                          'وسقفٌ من الفاتورة تحدّدهما المغسلة.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('السجلّ',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (history.isEmpty)
                Text('لا حركة بعد. تُكسب النقاط عند تسليم طلبك.',
                    style: Theme.of(context).textTheme.bodySmall)
              else
                for (final t in history)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      t.isEarn ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: t.isEarn ? scheme.primary : scheme.outline,
                    ),
                    title: Text(
                      '${t.isEarn ? '+' : ''}${t.points} نقطة',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [t.note, df.format(t.createdAt.toLocal())]
                          .whereType<String>()
                          .join(' — '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
