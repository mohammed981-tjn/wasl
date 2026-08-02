import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'entry_point.dart';
import 'roles/role_gate.dart';

void main() {
  runApp(const WaslApp());
}

class WaslApp extends StatelessWidget {
  const WaslApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('ar'),
      title: 'Wasl',
      debugShowCheckedModeBanner: false,

  localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return Directionality(
          textDirection: (Localizations.localeOf(context).languageCode == 'ar')
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        );
      },

      home: const EntryPoint(),
    );
  }
}