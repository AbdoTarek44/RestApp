import 'dart:ui';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await AuthService.initialize(); } catch (_) {}
  if (AuthService.ready) {
    final prefs = await SharedPreferences.getInstance();
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(prefs.getBool('crash_reports_enabled') ?? false);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordError(details.exception.runtimeType.toString(),details.stack,fatal:true);
      };
      PlatformDispatcher.instance.onError = (error,stack) {
        FirebaseCrashlytics.instance.recordError(error.runtimeType.toString(),stack,fatal:true);
        return true;
      };
    } catch (_) {}
  }
  runApp(const MaalishApp());
}

class MaalishApp extends StatelessWidget {
  const MaalishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'معلش',
      theme: AppTheme.light,
      home: const Directionality(textDirection: TextDirection.rtl, child: StartupGate()),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  Widget? target;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final guest = prefs.getBool('guest_mode') ?? false;
    if (onboardingDone && guest && AuthService.ready) {
      try { await AuthService().ensureGuest().timeout(const Duration(seconds: 8)); } catch (_) {}
    }
    if (!onboardingDone) {
      target = const OnboardingScreen();
    } else if (AuthService.ready && AuthService().currentUser != null) {
      target = const HomeShell();
    } else if (guest) {
      target = const HomeShell();
    } else {
      target = const AuthScreen();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => target ?? const Scaffold(body: Center(child: CircularProgressIndicator()));
}
