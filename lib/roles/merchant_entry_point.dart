import 'package:flutter/material.dart';

class MerchantEntryPoint extends StatelessWidget {
  const MerchantEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wasl • Merchant'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('واجهة المتجر/المطعم (قيد التجهيز)'),
      ),
    );
  }
}
