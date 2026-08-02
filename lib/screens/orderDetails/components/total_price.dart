import 'package:flutter/material.dart';

import '../../../constants.dart';

class TotalPrice extends StatelessWidget {
  const TotalPrice({
    super.key,
    required this.price,
  });

  final double price;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text.rich(
          TextSpan(
            text: 'الإجمالي ',
            style: TextStyle(color: titleColor, fontWeight: FontWeight.w500),
            children: [
              TextSpan(
                text: '(شامل الضريبة)',
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ),
        Text(
          '${price.toStringAsFixed(2)} ر.س',
          style:
              const TextStyle(color: titleColor, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
