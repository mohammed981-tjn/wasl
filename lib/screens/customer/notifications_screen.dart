import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/models.dart';
import '../../services/notifications_service.dart';
import '../../widgets/async_view.dart';
import 'my_complaints_screen.dart';
import 'order_tracking_screen.dart';

/// صندوقُ الرسائل.
///
/// **رسالةٌ تُقرأ ولا يُفعَل بها شيء نصفُ رسالة.** فكلُّ رسالةٍ تفتح ما
/// تتحدّث عنه: الشكوى إلى «شكاويّ»، والطلبُ إلى تتبّعه. وأهمُّها رسالةُ
/// «ردٌّ على شكواك» — تفتح الشاشة التي فيها زرّا «نعم» و«لا».
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = const NotificationsService();
  late Future<List<AppNotification>> _load = _service.inbox();

  void _reload() => setState(() => _load = _service.inbox());

  Future<void> _open(AppNotification n) async {
    if (n.isUnread) {
      // **تُعلَّم مقروءةً ولا يُنتظر ردُّ الخادم**: فتحُ الشاشة أهمُّ من ختمٍ
      // يتأخّر، والفشلُ هنا لا يضرّ — تبقى غيرَ مقروءة وتُقرأ لاحقًا.
      unawaited(_service.markRead(n.id));
    }
    if (!mounted) return;

    // الشكوى تسبق الطلب: رسالةٌ عن شكوى على طلبٍ تحمل المعرّفين، والمقصود
    // منها الشكوى.
    if (n.complaintId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyComplaintsScreen()),
      );
    } else if (n.orderId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: n.orderId!),
        ),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرسائل'),
        actions: [
          TextButton(
            onPressed: () async {
              await _service.markAllRead();
              _reload();
            },
            child: const Text('تعليم الكلّ مقروءًا'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: AsyncView<List<AppNotification>>(
          future: _load,
          onRetry: _reload,
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'لا رسائل بعد.',
          builder: (context, list) => ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _Tile(
              notification: list[i],
              onTap: () => _open(list[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.notification, required this.onTap});
  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final fmt = DateFormat('d MMMM • h:mm a', 'ar');
    final opens = n.complaintId != null || n.orderId != null;

    return ListTile(
      onTap: opens ? onTap : null,
      leading: Icon(
        n.complaintId != null
            ? Icons.support_agent_outlined
            : Icons.local_laundry_service_outlined,
        color: n.isUnread ? Theme.of(context).colorScheme.primary : Colors.black38,
      ),
      title: Text(
        n.title?.isNotEmpty == true ? n.title! : n.body.split('\n').first,
        style: TextStyle(
          fontWeight: n.isUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.title?.isNotEmpty == true)
            Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(fmt.format(n.createdAt),
              style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
        ],
      ),
      trailing: n.isUnread
          ? Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      isThreeLine: n.title?.isNotEmpty == true,
    );
  }
}

/// جرسٌ بعدّاد.
///
/// **والعدّادُ يُقرأ من الخادم لا يُخمَّن**: رقمٌ خاطئ على الجرس يُدرَّب
/// المستخدمُ على تجاهله، فيصير الجرسُ زينةً — وأوّلُ ما يُتجاهَل معه هو
/// سؤالُ تأكيد الشكوى.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key});

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  final _service = const NotificationsService();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final n = await _service.unreadCount();
      if (mounted) setState(() => _unread = n);
    } catch (_) {
      // عدّادٌ لا يُجلب لا يُسقط شريطَ العنوان: يبقى الجرسُ بلا رقم.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'الرسائل',
          icon: const Icon(Icons.notifications_none),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            _refresh();
          },
        ),
        if (_unread > 0)
          PositionedDirectional(
            top: 8,
            end: 8,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  _unread > 99 ? '٩٩+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
