import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_role.dart';
import 'core/theme/app_theme.dart';
import 'screens/admin/admin_home.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/customer/customer_home.dart';
import 'screens/laundry/laundry_home.dart';
import 'services/cart.dart';
import 'services/session_service.dart';

/// جذر التطبيق، واعٍ بالنكهة ولا يعرف من ثبّتها.
class WaslApp extends StatelessWidget {
  const WaslApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionService()..refresh()),
        // السلّة تعيش فوق الشاشات لا داخلها: العميل يتصفّح ويعود، ويجب ألّا
        // يفقد اختياره بضغطة رجوع.
        ChangeNotifierProvider(create: (_) => Cart()),
      ],
      child: MaterialApp(
        title: flavor.titleAr,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar'), Locale('en')],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        // العربية تُقرأ من اليمين، والاتجاه يُفرض على الشجرة كلّها لا على شاشة.
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _FlavorGate(flavor: flavor),
      ),
    );
  }
}

class _FlavorGate extends StatelessWidget {
  const _FlavorGate({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();

    if (!session.isSignedIn) {
      return SignInScreen(flavor: flavor);
    }
    if (session.isLoading && session.roles.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return switch (flavor) {
      AppFlavor.admin => const AdminHome(),
      AppFlavor.customer => const CustomerHome(),
      AppFlavor.laundry => const LaundryHome(),
      _ => _ComingSoon(flavor: flavor),
    };
  }
}

/// نكهةٌ لم تُبنَ بعد.
///
/// وهذه شاشةٌ صريحةٌ عمدًا: «قيد التجهيز» أصدقُ من شاشةٍ تبدو عاملةً ببيانات
/// وهمية — وأوّل ما مُسح من هذا المستودع كان بالضبط ذلك النوع من الشاشات.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionService>();
    return Scaffold(
      appBar: AppBar(title: Text(flavor.titleAr)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 48),
            const SizedBox(height: 12),
            Text('${flavor.titleAr} — لم تُبنَ بعد',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('المبنيّ حتى الآن: الإدارة والعميل والمغسلة',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            TextButton(
              onPressed: session.signOut,
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}
