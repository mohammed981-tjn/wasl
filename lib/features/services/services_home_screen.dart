import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../demo_data.dart';
import '../../screens/details/details_screen.dart';
import '../../screens/filter/filter_screen.dart';
import '../../components/cards/big/restaurant_info_big_card.dart';

/// WASL Home (Marketing-only)
/// - Inspired by DoorDash layout
/// - Uses WASL official palette from constants.dart
/// - Keeps "اشتراكات" and account options in Profile screen (not here)
class ServicesHomeScreen extends StatefulWidget {
  const ServicesHomeScreen({super.key});

  @override
  State<ServicesHomeScreen> createState() => _ServicesHomeScreenState();
}

class _ServicesHomeScreenState extends State<ServicesHomeScreen> {
  int _activeTopFilter = 0; // 0: الكل, 1: المطاعم, 2: البقالة

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(
                      onFilterTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FilterScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const _NoticeBanner(),
                    const SizedBox(height: 12),
                    _SearchPill(
                      onTap: () {
                        // Placeholder for search screen.
                      },
                    ),
                    const SizedBox(height: 12),
                    _TopFilters(
                      activeIndex: _activeTopFilter,
                      onChanged: (v) => setState(() => _activeTopFilter = v),
                    ),
                    const SizedBox(height: 16),
                    const _SectionHeader(title: 'العروض'),
                    const SizedBox(height: 10),
                    _PromoCarousel(images: demoBigImages),
                    const SizedBox(height: 18),
                    const _SectionHeader(title: 'الأقسام'),
                    const SizedBox(height: 10),
                    const _QuickIconsRow(),
                    const SizedBox(height: 18),
                    const _SectionHeader(title: 'أفضل المتاجر والمطاعم'),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),

            // Big restaurant cards
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MarketingBigCard(
                        title: index.isEven ? "McDonald's" : 'بيت الكبسّة',
                        rating: index.isEven ? 4.3 : 4.9,
                        numOfRating: index.isEven ? 200 : 120,
                        deliveryTime: index.isEven ? 25 : 30,
                        images: demoBigImages..shuffle(),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DetailsScreen()),
                        ),
                      ),
                    );
                  },
                  childCount: 5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onFilterTap});

  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: const [
                  Icon(Icons.location_on_rounded, color: primaryColor),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'جدة • Jeddah',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6B7280)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _IconBtn(icon: Icons.tune_rounded, onTap: onFilterTap),
        const SizedBox(width: 10),
        _IconBtn(icon: Icons.shopping_bag_outlined, onTap: () {}),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x0F000000)),
        ),
        child: Icon(icon, color: primaryColor),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.80),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: const [
          Expanded(
            child: Text(
              'يبدو أنك بعيد… هل هذا هو العنوان الصحيح؟',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: 8),
          Icon(Icons.close_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x0F000000)),
        ),
        child: Row(
          children: const [
            Icon(Icons.search_rounded, color: Color(0xFF6B7280)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'ابحث عن مطعم أو متجر…',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopFilters extends StatelessWidget {
  const _TopFilters({required this.activeIndex, required this.onChanged});

  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const ['الكل', 'المطاعم', 'البقالة'];
    return Row(
      children: List.generate(items.length, (i) {
        final selected = i == activeIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? primaryColor : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? primaryColor : const Color(0x14000000),
                  ),
                ),
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _PromoCarousel extends StatelessWidget {
  const _PromoCarousel({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: images.length.clamp(1, 8),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                Image.asset(
                  images[index % images.length],
                  width: 300,
                  height: 170,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.86),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'خصم 30% على أول طلب',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuickIconsRow extends StatelessWidget {
  const _QuickIconsRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      _QuickIcon('بقالة', Icons.local_grocery_store_outlined),
      _QuickIcon('مطاعم', Icons.restaurant_rounded),
      _QuickIcon('قهوة', Icons.coffee_outlined),
      _QuickIcon('صيدلية', Icons.local_pharmacy_outlined),
      _QuickIcon('هدايا', Icons.card_giftcard_rounded),
      _QuickIcon('المزيد', Icons.grid_view_rounded),
    ];

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _QuickIconTile(item: items[i]),
      ),
    );
  }
}

class _QuickIcon {
  const _QuickIcon(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _QuickIconTile extends StatelessWidget {
  const _QuickIconTile({required this.item});
  final _QuickIcon item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x0F000000)),
            ),
            child: Icon(item.icon, color: primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MarketingBigCard extends StatelessWidget {
  const _MarketingBigCard({
    required this.title,
    required this.rating,
    required this.numOfRating,
    required this.deliveryTime,
    required this.images,
    required this.onTap,
  });

  final String title;
  final double rating;
  final int numOfRating;
  final int deliveryTime;
  final List<String> images;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RestaurantInfoBigCard(
      images: images,
      name: title,
      rating: rating,
      numOfRating: numOfRating,
      deliveryTime: deliveryTime,
      // Keep types as marketing tags for now.
      foodType: const ['سوبر ماركت', 'مطاعم', 'عروض'],
      press: onTap,
    );
  }
}
