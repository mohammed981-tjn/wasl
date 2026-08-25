import 'package:flutter/material.dart';

/// غلافٌ لعرض نتيجة جلبٍ من الخادم.
///
/// **لماذا مكوّنٌ واحد**: ثلاث حالاتٍ (تحميل، خطأ، فراغ) تتكرّر في كل شاشة،
/// وكتابتها في كلٍّ منها يجعل واحدةً تُنسى — وأكثر ما يُنسى **حالة الفراغ**،
/// فتظهر شاشةٌ بيضاء لا تقول شيئًا، ويظنّها المستخدم عطلًا.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
    this.emptyMessage,
    this.isEmpty,
  });

  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;
  final String? emptyMessage;
  final bool Function(T)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline,
            title: 'تعذّر جلب البيانات',
            detail: '${snap.error}',
            onRetry: onRetry,
          );
        }
        final data = snap.data as T;
        if (isEmpty?.call(data) ?? false) {
          return _Message(
            icon: Icons.inbox_outlined,
            title: emptyMessage ?? 'لا توجد بيانات بعد',
            onRetry: onRetry,
          );
        }
        return builder(context, data);
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
