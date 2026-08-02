import 'package:flutter/material.dart';

class DriverEntryPoint extends StatelessWidget {
  const DriverEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wasl • Driver'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('واجهة السائق (قيد التجهيز)'),
      ),
    );
  }
}
