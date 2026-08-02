import 'package:flutter/material.dart';
import 'reset_email_sent_screen.dart';

import '../../components/welcome_text.dart';
import '../../constants.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نسيت كلمة المرور'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WelcomeText(
              title: 'نسيت كلمة المرور',
              text: 'اكتب بريدك الإلكتروني وسنرسل لك\nتعليمات إعادة التعيين.',
            ),
            SizedBox(height: defaultPadding),
            ForgotPassForm(),
          ],
        ),
      ),
    );
  }
}

class ForgotPassForm extends StatefulWidget {
  const ForgotPassForm({super.key});

  @override
  State<ForgotPassForm> createState() => _ForgotPassFormState();
}

class _ForgotPassFormState extends State<ForgotPassForm> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            validator: emailValidator.call,
            onSaved: (value) {},
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'البريد الإلكتروني',
            ),
          ),
          const SizedBox(height: defaultPadding),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                _formKey.currentState!.save();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ResetEmailSentScreen(),
                  ),
                );
              }
            },
            child: const Text('إعادة تعيين كلمة المرور'),
          ),
        ],
      ),
    );
  }
}