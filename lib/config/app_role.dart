/// دور من يستعمل هذه الحزمة.
///
/// **لماذا هذا الملفّ قبل النكهات**: «نكهة بناء» و«جذر واعٍ بالدور» ليسا
/// خيارين متقابلين بل مرحلتان. الجذر شيفرةٌ يجب أن توجد أوّلًا — لا وجود
/// لشاشة إدارة قبل أن يعرف التطبيق أنه ينظر إلى إداريّ. والنكهة تغليفٌ يأتي
/// بعده: نفس الشيفرة تُقسَّم إلى أربع حزم بمداخل منفصلة.
///
/// وبعد هذا الملفّ تصير النكهة **مفتاحًا يُقلَب** لا مشروعًا يُبدأ:
///
///   ١) ملفّ مدخل لكل نكهة، سطران فيه:
///        `// lib/main_admin.dart`
///        `void main() => bootstrap(pinned: AppFlavor.admin);`
///
///   ٢) و`productFlavors` في `android/app/build.gradle` يعطي كلّ نكهة
///      `applicationId` واسمًا وأيقونة.
///
///   ٣) والبناء: `flutter build apk --flavor admin -t lib/main_admin.dart`
///
/// ولا شيء في بقيّة الشيفرة يتغيّر: الجذر يقرأ [AppFlavor] ولا يعرف من أين جاء.
library;

/// النكهات الأربع — حزمٌ تُبنى، لا أدوارٌ في القاعدة.
///
/// والفرق مقصود: القاعدة تعرف سبعة أدوار ([`app_role`] في SQL)، والحزم أربع.
/// فـ`branch_manager` و`accountant` و`customer_service` يستعملون **حزمة
/// الإدارة نفسها**، ويرى كلٌّ منهم ما تسمح به سياسات RLS لا ما تُظهره الشاشة.
enum AppFlavor {
  /// العميل — الطلب والتتبّع والفواتير. الافتراضي.
  customer,

  /// السائق — الاستلام والتسليم وإثباتهما.
  driver,

  /// موظّف المغسلة — مراحل التشغيل والباركود.
  laundry,

  /// الإدارة — الأسعار والرسوم والتقارير والموظّفون.
  admin,
}

/// الدور المثبَّت وقت البناء، إن ثُبِّت.
///
/// `--dart-define=WASL_FLAVOR=admin` هو ما تمرّره نكهةُ البناء، فيصير الانتقال
/// إلى النكهات تغييرًا في **أمر البناء** لا في الشيفرة. وحتى قبلها يعمل: حزمة
/// واحدة تُبنى أربع مرّات بأربع قيم.
const String _pinned = String.fromEnvironment('WASL_FLAVOR');

AppFlavor? get pinnedFlavor => switch (_pinned) {
      'customer' => AppFlavor.customer,
      'driver' => AppFlavor.driver,
      'laundry' => AppFlavor.laundry,
      'admin' => AppFlavor.admin,
      _ => null,
    };

extension AppFlavorLabel on AppFlavor {
  String get titleAr => switch (this) {
        AppFlavor.customer => 'وصل',
        AppFlavor.driver => 'وصل • السائق',
        AppFlavor.laundry => 'وصل • المغسلة',
        AppFlavor.admin => 'وصل • الإدارة',
      };
}
