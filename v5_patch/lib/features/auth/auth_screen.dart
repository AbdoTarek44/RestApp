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
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }

  Future<void> _guest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest_mode', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  Future<void> _google() async {
    if (!AuthService.configured) {
      _show('تسجيل Google جاهز في الكود، وباقي إضافة إعدادات Firebase للمشروع.');
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

  void _phone() {
    if (!AuthService.configured) {
      _show('تسجيل الموبايل جاهز في الكود، وباقي إضافة إعدادات Firebase للمشروع.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PhoneAuthSheet(),
    ).then((ok) {
      if (ok == true) _completeLogin();
    });
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
                const Text('معلش', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: AppColors.navy)),
                const SizedBox(height: 8),
                const Text('مكانك الخاص للكلام براحتك.', style: TextStyle(fontSize: 17, color: AppColors.text2)),
                const SizedBox(height: 34),
                if (!AuthService.configured)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(16)),
                    child: const Text('نسخة Firebase جاهزة، لكن بيانات المشروع لسه مش متضافة للـBuild. الدخول كضيف شغال عادي.', textAlign: TextAlign.center),
                  ),
                ElevatedButton.icon(
                  onPressed: loading ? null : _google,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                  label: const Text('الدخول بحساب Google'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: loading ? null : _phone,
                  icon: const Icon(Icons.phone_android_rounded),
                  label: const Text('الدخول برقم الموبايل'),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: loading ? null : _guest, child: const Text('الدخول كضيف')),
                const SizedBox(height: 16),
                const Text('تقدر تعمل حساب بعدين من "أنا ومعلش" من غير ما نخلي التسجيل يعطلك عن الفضفضة.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.text2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneAuthSheet extends StatefulWidget {
  const _PhoneAuthSheet();
  @override
  State<_PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<_PhoneAuthSheet> {
  final phone = TextEditingController(text: '+20');
  final code = TextEditingController();
  final auth = AuthService();
  String verificationId = '';
  bool busy = false;

  void _error(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    setState(() => busy = false);
  }

  Future<void> _send() async {
    final value = phone.text.trim().replaceAll(' ', '');
    if (!value.startsWith('+') || value.length < 8) {
      _error('اكتب الرقم بصيغة دولية، مثال +2010...');
      return;
    }
    setState(() => busy = true);
    await auth.sendPhoneCode(
      phoneNumber: value,
      onCodeSent: (id) {
        if (!mounted) return;
        setState(() { verificationId = id; busy = false; });
      },
      onError: _error,
    );
  }

  Future<void> _confirm() async {
    if (code.text.trim().length < 6) return;
    setState(() => busy = true);
    try {
      await auth.confirmPhoneCode(verificationId: verificationId, smsCode: code.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _error('الكود غير صحيح أو انتهت صلاحيته.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(verificationId.isEmpty ? 'رقم الموبايل' : 'كود التحقق', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (verificationId.isEmpty) ...[
              TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: '+2010xxxxxxxx')),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: busy ? null : _send, child: Text(busy ? 'جاري الإرسال…' : 'ابعت الكود')),
            ] else ...[
              TextField(controller: code, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, maxLength: 6, decoration: const InputDecoration(hintText: '000000')),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: busy ? null : _confirm, child: Text(busy ? 'جاري التحقق…' : 'تأكيد')),
              TextButton(onPressed: busy ? null : () => setState(() => verificationId = ''), child: const Text('غير الرقم')),
            ],
          ],
        ),
      ),
    );
  }
}
