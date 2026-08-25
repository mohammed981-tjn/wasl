import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_role.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';

/// شاشة الدخول.
///
/// **طريقان عمدًا**: الجوال هو المقصود — المخطّط يجعل `profiles.phone` فريدًا،
/// وعميل المغسلة يُعرف برقمه لا ببريده. لكنّ الجوال يحتاج مزوّد رسائل مفعَّلًا
/// في لوحة Supabase، وهو إعدادٌ بيد المالك لا شيفرةٌ تُكتب.
///
/// فيبقى البريد متاحًا حتى يُفعَّل — وحين يُفعَّل لا يتغيّر في هذا الملفّ حرف،
/// لأن `signInWithOtp` تعمل هي هي مهما كان المزوّد خلفها.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Method { phone, email }

class _SignInScreenState extends State<SignInScreen> {
  _Method _method = _Method.phone;
  final _phone = TextEditingController(text: '+9665');
  final _otp = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = humanizeDbError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionService>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text('وصل',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  Text(widget.flavor.titleAr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),

                  SegmentedButton<_Method>(
                    segments: const [
                      ButtonSegment(
                          value: _Method.phone,
                          icon: Icon(Icons.phone_android),
                          label: Text('الجوال')),
                      ButtonSegment(
                          value: _Method.email,
                          icon: Icon(Icons.alternate_email),
                          label: Text('البريد')),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) => setState(() {
                      _method = s.first;
                      _error = null;
                      _otpSent = false;
                    }),
                  ),
                  const SizedBox(height: 20),

                  if (_method == _Method.phone) ..._phoneFields(session)
                  else ..._emailFields(session),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: _error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneFields(SessionService session) => [
        TextField(
          controller: _phone,
          enabled: !_otpSent,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'رقم الجوال',
            hintText: '+9665XXXXXXXX',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        if (_otpSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'رمز التحقّق',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    if (_otpSent) {
                      await session.verifyPhoneOtp(
                          _phone.text.trim(), _otp.text.trim());
                    } else {
                      await session.sendPhoneOtp(_phone.text.trim());
                      if (mounted) setState(() => _otpSent = true);
                    }
                  }),
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_otpSent ? 'تأكيد الرمز' : 'إرسال رمز التحقّق'),
        ),
        if (_otpSent)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _otpSent = false),
            child: const Text('تغيير الرقم'),
          ),
      ];

  List<Widget> _emailFields(SessionService session) => [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'البريد الإلكتروني',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(() => session.signInWithPassword(
                  _email.text.trim(), _password.text)),
          child: _busy
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('دخول'),
        ),
      ];
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
