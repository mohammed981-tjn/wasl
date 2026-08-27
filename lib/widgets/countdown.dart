import 'dart:async';

import 'package:flutter/material.dart';

/// صياغةٌ عربيّةٌ سليمةٌ لمدّةٍ متبقّية — «ساعتان» لا «٢ ساعة».
///
/// **العربية تعدّ ثلاثةَ أعداد لا عددين**: مفردٌ ومثنًّى وجمع، والجمعُ نفسُه
/// ينقسم (٣–١٠ جمعُ قلّة، وما فوقها مفرد منصوب). و«2 ساعة» في شاشةٍ عربيّة
/// تُقرأ ركيكة، وركّةُ النصّ في لحظةِ شكوى تزيد الشاكيَ نفورًا.
String formatRemaining(Duration left) {
  if (left <= Duration.zero) return 'انتهت';

  final days = left.inDays;
  if (days >= 1) {
    if (days == 1) return 'يومٌ واحد';
    if (days == 2) return 'يومان';
    if (days <= 10) return '$days أيّام';
    return '$days يومًا';
  }

  final hours = left.inHours;
  if (hours >= 1) {
    if (hours == 1) return 'ساعةٌ واحدة';
    if (hours == 2) return 'ساعتان';
    if (hours <= 10) return '$hours ساعات';
    return '$hours ساعة';
  }

  final mins = left.inMinutes;
  if (mins <= 0) return 'أقلّ من دقيقة';
  if (mins == 1) return 'دقيقةٌ واحدة';
  if (mins == 2) return 'دقيقتان';
  if (mins <= 10) return '$mins دقائق';
  return '$mins دقيقة';
}

/// عدّادٌ حيٌّ لمهلةٍ — يعيد بناء نفسه فينتهي في لحظته.
///
/// **ولماذا عدّادٌ لا نصٌّ ثابت**: «متبقٍ ثلاثُ ساعات» يُحسب لحظةَ بناء
/// الشاشة ثم يتجمّد. ومن ترك الشاشة مفتوحة يرى رقمًا كاذبًا — والأسوأ أنّ
/// الزرّ يبقى قابلًا للضغط بعد انقضاء المهلة لأن لا شيء يعيد بناءه، فيكتب
/// الشاكي شكواه ثم تُردّ. وردٌّ بعد الكتابة أسوأُ من زرٍّ معطَّلٍ قبلها.
///
/// **ودقّةُ العدّ بحسب ما يُعرض**: ما دام العرضُ بالأيّام أو الساعات فدقيقةٌ
/// تكفي، وفي الساعة الأخيرة يُشدَّد إلى خمسَ عشرةَ ثانية. وبعد الانقضاء
/// يتوقّف المؤقّت نهائيًّا — لا عدَّ بلا فائدةٍ في الخلفيّة يأكل بطاريّة.
class Countdown extends StatefulWidget {
  const Countdown({
    super.key,
    required this.deadline,
    required this.builder,
    this.now = DateTime.now,
  });

  /// `null` = لا مهلة أصلًا (طلبٌ جارٍ، أو شكوى لم تُحلّ بعد).
  final DateTime? deadline;

  /// [left] هي المتبقّي، و`null` حين لا مهلة. و[expired] محسوبةٌ لحظتَها.
  final Widget Function(BuildContext context, Duration? left, bool expired)
      builder;

  /// مصدرُ الوقت — يُحقَن في الاختبار.
  ///
  /// **ومناداةُ `DateTime.now()` مباشرةً تجعل هذا الودجت غيرَ قابلٍ للاختبار
  /// أصلًا**: `pump` في اختبار Flutter يقدّم ساعةَ المؤقّتات وحدها، أمّا ساعةُ
  /// الحائط فلا تتحرّك. فيُطلق المؤقّتُ نبضتَه ويقرأ الوقتَ نفسه، فلا ينقضي
  /// العدّاد أبدًا — وهو بالضبط السلوكُ الذي يجب أن يُختبر.
  final DateTime Function() now;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(Countdown old) {
    super.didUpdateWidget(old);
    // قد تتغيّر المهلة تحت الودجت نفسه (شكوى حُلّت للتوّ فانفتحت مهلةُ
    // تأكيدها) — فتُعاد الجدولة على قيمتها الجديدة.
    if (old.deadline != widget.deadline) _arm();
  }

  Duration? get _left {
    final d = widget.deadline;
    if (d == null) return null;
    final left = d.difference(widget.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _arm() {
    _ticker?.cancel();
    final left = _left;
    if (left == null || left <= Duration.zero) return;

    final period = left.inHours >= 1
        ? const Duration(minutes: 1)
        : const Duration(seconds: 15);

    _ticker = Timer.periodic(period, (_) {
      if (!mounted) return;
      setState(() {});
      final now = _left ?? Duration.zero;
      // الدخولُ في الساعة الأخيرة يستدعي دقّةً أعلى، والانقضاءُ يُنهي العدّ.
      if (now <= Duration.zero || (now.inHours < 1 && period.inMinutes >= 1)) {
        _arm();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    return widget.builder(context, left, left != null && left <= Duration.zero);
  }
}
