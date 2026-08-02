import 'package:flutter/material.dart';
import 'package:form_field_validator/form_field_validator.dart';

// Colors that we use in our app
const titleColor = Color(0xFF010F07);

// ✅ WASL Official Brand Palette (as provided)
// Primary Green  #2DB87A
// Navy Blue      #1A2744
// Gold           #D4A843
// Cream          #F7F5F0
const primaryColor = Color(0xFF2DB87A);
const navyColor = Color(0xFF1A2744);
const accentColor = Color(0xFFD4A843);
const creamColor = Color(0xFFF7F5F0);

const bodyTextColor = Color(0xFF6B7280);
const inputColor = Color(0xFFFBFBFB);

const double defaultPadding = 16;
const Duration kDefaultDuration = Duration(milliseconds: 250);

const TextStyle kButtonTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 14,
  fontWeight: FontWeight.bold,
);

const EdgeInsets kTextFieldPadding = EdgeInsets.symmetric(
  horizontal: defaultPadding,
  vertical: defaultPadding,
);

// Text Field Decoration
const OutlineInputBorder kDefaultOutlineInputBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(6)),
  borderSide: BorderSide(
    color: Color(0xFFF3F2F2),
  ),
);

const InputDecoration otpInputDecoration = InputDecoration(
  contentPadding: EdgeInsets.zero,
  counterText: "",
  errorStyle: TextStyle(height: 0),
);

const kErrorBorderSide = BorderSide(color: Colors.red, width: 1);

// Validator
final passwordValidator = MultiValidator([
  RequiredValidator(errorText: 'كلمة المرور مطلوبة'),
  MinLengthValidator(8, errorText: 'كلمة المرور لازم تكون 8 أحرف على الأقل'),
  PatternValidator(r'(?=.*?[#?!@$%^&*-/])',
      errorText: 'لازم تحتوي كلمة المرور على رمز خاص واحد على الأقل')
]);

final emailValidator = MultiValidator([
  RequiredValidator(errorText: 'البريد الإلكتروني مطلوب'),
  EmailValidator(errorText: 'أدخل بريد إلكتروني صحيح')
]);

final requiredValidator =
    RequiredValidator(errorText: 'هذا الحقل مطلوب');
final matchValidator = MatchValidator(errorText: 'كلمتا المرور غير متطابقتين');

final phoneNumberValidator = MinLengthValidator(10,
    errorText: 'رقم الجوال لازم يكون 10 أرقام على الأقل');

// Common Text
final Center kOrText = Center(
    child: Text("أو", style: TextStyle(color: titleColor.withOpacity(0.7))));
