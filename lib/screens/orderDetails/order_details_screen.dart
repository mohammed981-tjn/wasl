import 'package:flutter/material.dart';

import '../../components/buttons/primary_button.dart';
import '../../constants.dart';
import 'components/order_item_card.dart';
import 'components/price_row.dart';
import 'components/total_price.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلباتي'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            children: [
              const SizedBox(height: defaultPadding),
              // List of cart items
              ...List.generate(
                demoItems.length,
                (index) => Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: defaultPadding / 2),
                  child: OrderedItemCard(
                    title: demoItems[index]["title"],
                    description:
                        'وصف مختصر للمنتج (تجريبي).',
                    numOfItem: demoItems[index]["numOfItem"],
                    price: demoItems[index]["price"].toDouble(),
                  ),
                ),
              ),
              const PriceRow(text: 'المجموع الفرعي', price: 28.0),
              const SizedBox(height: defaultPadding / 2),
              const PriceRow(text: 'التوصيل', price: 0),
              const SizedBox(height: defaultPadding / 2),
              const TotalPrice(price: 20),
              const SizedBox(height: defaultPadding * 2),
              PrimaryButton(
                text: 'إتمام الطلب (20.10 ر.س)',
                press: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Map> demoItems = [
  {
    "title": "كوكي ساندويتش",
    "price": 7.4,
    "numOfItem": 1,
  },
  {
    "title": "كومبو برجر",
    "price": 12,
    "numOfItem": 1,
  },
  {
    "title": "طبق محار",
    "price": 8.6,
    "numOfItem": 2,
  },
];
