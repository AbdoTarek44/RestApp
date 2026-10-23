import '../../services/insights_service.dart';
import '../../services/notification_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/ai_service.dart';
import '../../services/conversation_service.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../history/history_screen.dart';
import '../profile/profile_screen.dart';
import 'home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int current = 0;
  String announcement = '';
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _notice(); ConversationService().retryPending(); InsightsService().flush(); NotificationService.refresh(); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) { _notice(); ConversationService().retryPending(); InsightsService().flush(); NotificationService.refresh(); }
  }
  Future<void> _notice() async {
    try {
      final url = Uri.parse(AiService.buildApiUrl).replace(path:'/app-config');
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if(response.statusCode != 200) return;
      final data=jsonDecode(response.body) as Map<String,dynamic>;
      if(mounted) setState(() => announcement = (data['announcement'] ?? '').toString());
    } catch (_) {}
  }
  final screens = const [HomeScreen(), HistoryScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(children: [
          if (announcement.isNotEmpty) SafeArea(bottom:false,child: MaterialBanner(
            content: Text(announcement), actions:[TextButton(onPressed:()=>setState(()=>announcement=''),child:const Text('تمام'))])),
          Expanded(child: screens[current]),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: current,
          onDestinationSelected: (v) => setState(() => current = v),
          backgroundColor: Colors.white,
          indicatorColor: AppColors.softBlue,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'مالك؟'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'فضفضاتي'),
            NavigationDestination(icon: Icon(Icons.face_rounded), label: 'أنا ومعلش'),
          ],
        ),
      ),
    );
  }
}
