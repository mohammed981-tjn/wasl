import 'package:flutter/material.dart';

import '../../../constants.dart';
import '../../../demo_data.dart';
import '../../../screens/details/details_screen.dart';

class RestaurantsScreen extends StatelessWidget {
  const RestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المطاعم | Restaurants'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(defaultPadding, 12, defaultPadding, 24),
          children: [
            // Search (Uber-like)
            TextField(
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث عن مطعم... | Search restaurants...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: Icon(Icons.tune_rounded, color: cs.secondary),
              ),
            ),
            const SizedBox(height: 14),

            // Quick chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Chip(label: 'قريب', icon: Icons.near_me_rounded),
                  _Chip(label: 'الأعلى تقييماً', icon: Icons.star_rounded),
                  _Chip(label: 'خصومات', icon: Icons.local_offer_rounded),
                  _Chip(label: 'توصيل سريع', icon: Icons.bolt_rounded),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'مطاعم قريبة منك | Nearby',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),

            ...demoMediumCardData.map((r) => _RestaurantTile(
                  name: r['name']?.toString() ?? '',
                  image: r['image']?.toString() ?? '',
                  location: r['location']?.toString() ?? '',
                  rating: (r['rating'] as num?)?.toDouble() ?? 0,
                  minutes: (r['delivertTime'] as num?)?.toInt() ?? 0,
                )),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantTile extends StatelessWidget {
  const _RestaurantTile({
    required this.name,
    required this.image,
    required this.location,
    required this.rating,
    required this.minutes,
  });

  final String name;
  final String image;
  final String location;
  final double rating;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: cs.surface,
        elevation: 10,
        shadowColor: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DetailsScreen()),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(
                    image,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 16, color: cs.secondary),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.schedule_rounded, size: 16, color: cs.primary.withOpacity(0.75)),
                        const SizedBox(width: 4),
                        Text(
                          '$minutes min',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.secondary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'اطلب | Order',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: cs.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      location,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
