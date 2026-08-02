import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../../../constants.dart';

class Body extends StatelessWidget {
  const Body({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: defaultPadding),
              Text("إعدادات الحساب",
                  style: Theme.of(context).textTheme.headlineMedium),
              Text(
                "كل شيء يخص حسابك والاشتراكات وطرق الدفع…",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ProfileMenuCard(
                svgSrc: "assets/icons/profile.svg",
                title: "معلومات الملف الشخصي",
                subTitle: "تعديل بيانات الحساب",
                press: () {},
              ),
              ProfileMenuCard(
                svgSrc: "assets/icons/lock.svg",
                title: "تغيير كلمة المرور",
                subTitle: "تحديث كلمة المرور",
                press: () {},
              ),
              ProfileMenuCard(
                svgSrc: "assets/icons/card.svg",
                title: "طرق الدفع",
                subTitle: "إضافة بطاقات الدفع",
                press: () {},
              ),
              ProfileMenuCard(
                svgSrc: "assets/icons/marker.svg",
                title: "العناوين",
                subTitle: "إضافة/حذف عناوين التوصيل",
                press: () {},
              ),
              const SizedBox(height: 6),

              // ✅ Subscriptions live here (requested)
              Text(
                "الاشتراكات",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              ProfileMenuCard(
                svgSrc: "assets/icons/document.svg",
                title: "اشتراك السائقين",
                subTitle: "إدارة اشتراكات السائقين",
                press: () {},
              ),
              ProfileMenuCard(
                svgSrc: "assets/icons/document.svg",
                title: "اشتراك المطاعم",
                subTitle: "إدارة اشتراكات المطاعم والعروض",
                press: () {},
              ),

              ProfileMenuCard(
                svgSrc: "assets/icons/fb.svg",
                title: "الحسابات الاجتماعية",
                subTitle: "ربط حسابات التواصل",
                press: () {},
              ),
              ProfileMenuCard(
                svgSrc: "assets/icons/share.svg",
                title: "دعوة الأصدقاء",
                subTitle: "شارك رابط الدعوة",
                press: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileMenuCard extends StatelessWidget {
  const ProfileMenuCard({
    super.key,
    this.title,
    this.subTitle,
    this.svgSrc,
    this.press,
  });

  final String? title, subTitle, svgSrc;
  final VoidCallback? press;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: defaultPadding / 2),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        onTap: press,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SvgPicture.asset(
                svgSrc!,
                height: 24,
                width: 24,
                colorFilter: ColorFilter.mode(
                  titleColor.withOpacity(0.64),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title!,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subTitle!,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        color: titleColor.withOpacity(0.54),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_outlined,
                size: 20,
              )
            ],
          ),
        ),
      ),
    );
  }
}
