import 'package:flutter/material.dart';

class WaslPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const WaslPrimaryButton({super.key, required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }
}
