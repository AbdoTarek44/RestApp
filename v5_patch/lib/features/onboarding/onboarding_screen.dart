import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/maalish_face.dart';
import '../auth/auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int index = 0;

  final pages = const [
    ('احكي.', 'مش لازم ترتب كلامك.\nقول اللي جواك زي ما هو.', 'listening'),
    ('مش هقاطعك.', 'اكتب أو اتكلم براحتك.\nمفيش حكم ومفيش استعجال.', 'comforting'),
    ('وفي الآخر…', 'مش كل حاجة ليها حل دلوقتي.\nبس ساعات إن حد يسمعك بيفرق.', 'neutral'),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: controller,
                  itemCount: pages.length,
                  onPageChanged: (v) => setState(() => index = v),
                  itemBuilder: (_, i) {
                    final p = pages[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MaalishFace(expression: p.$3),
                        const SizedBox(height: 36),
                        Text(p.$1, style: Theme.of(context).textTheme.displayLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(p.$2, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
                        if (i == 2) ...[
                          const SizedBox(height: 22),
                          const Text('معلش.', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: AppColors.orange)),
                        ]
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == index ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: i == index ? AppColors.navy : AppColors.navy.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
                )),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (index < 2) {
                    controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                  } else {
                    _finish();
                  }
                },
                child: Text(index == 2 ? 'يلا نبدأ' : 'التالي'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
