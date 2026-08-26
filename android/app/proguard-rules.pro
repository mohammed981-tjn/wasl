# قواعد التقليم.
#
# **ما يُحفظ هنا هو ما يُنادى بالانعكاس** — والمقلّم لا يراه، فيحذفه، فينهار
# التطبيق في نسخة release وحدها بينما يعمل في debug تمامًا. وهذا أسوأ أنواع
# الأعطال: لا يظهر إلا بعد النشر.

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ML Kit — يستعمله mobile_scanner لقراءة الباركود، ويُحمَّل ديناميكيًّا.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# نماذج ML Kit الاختيارية التي لا نستعملها: تُسكت تحذيراتها ولا تُحزَم.
-dontwarn com.google.android.play.core.**

# رسائل الاستثناءات تُحفظ: بلا أسطر المصدر يصير تقرير العطل بلا موضع.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
