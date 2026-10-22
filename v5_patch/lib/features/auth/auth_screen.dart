import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/maalish_face.dart';
import '../home/home_shell.dart';

class AuthScreen extends StatefulWidget {
  final bool fromProfile;
  const AuthScreen({super.key, this.fromProfile = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final auth = AuthService();
  bool loading = false;

  Future<void> _completeLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest_mode', false);
    if (!mounted) return;
    if (widget.fromProfile) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  Future<void> _guest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest_mode', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  Future<void> _google() async {
    if (!AuthService.configured) {
      _show('تسجيل Google جاهز، وباقي إضافة إعدادات Firebase للمشروع.');
      return;
    }
    setState(() => loading = true);
    try {
      await auth.signInWithGoogle();
      await _completeLogin();
    } catch (e) {
      _show('مقدرناش نسجل بـGoogle: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const MaalishFace(expression: 'neutral', size: 120),
                const SizedBox(height: 24),
                const Text(
                  'معلش',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'مكانك الخاص للكلام براحتك.',
                  style: TextStyle(fontSize: 17, color: AppColors.text2),
                ),
                const SizedBox(height: 34),
                if (!AuthService.configured)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.softBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'نسخة Firebase جاهزة، لكن بيانات المشروع لسه مش متضافة للـBuild. الدخول كضيف شغال عادي.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: loading ? null : _google,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                  label: const Text('الدخول بحساب Google'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: loading ? null : _guest,
                  child: const Text('الدخول كضيف'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'تقدر تربط حساب Google بعدين من "أنا ومعلش" من غير ما نخلي التسجيل يعطلك عن الفضفضة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
