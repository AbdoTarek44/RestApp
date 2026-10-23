import '../../services/insights_service.dart';
import '../../services/notification_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/memory_service.dart';
import '../auth/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final service = MemoryService();
  final auth = AuthService();
  final name = TextEditingController();
  String style = 'متوازن';
  bool humor = true, memory = true, adviceOnlyWhenAsked = true, loading = true;
  List<String> memories = [];
  bool guest = false;
  bool deleting = false, crashReports = false, pushEnabled = false, insightEnabled = false, pushBusy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await service.load();
    final prefs = await SharedPreferences.getInstance();
    final push = await NotificationService.enabled();
    final insight = await InsightsService().enabled();
    if (!mounted) return;
    setState(() {
      name.text = p.nickname;
      style = p.style;
      humor = p.humor;
      memory = p.memoryEnabled;
      adviceOnlyWhenAsked = p.adviceOnlyWhenAsked;
      memories = p.memories;
      guest = prefs.getBool('guest_mode') ?? false;
      pushEnabled = push; insightEnabled = insight;
      crashReports = prefs.getBool('crash_reports_enabled') ?? false;
      loading = false;
    });
  }

  Future<void> _save() async {
    final latest = await service.load();
    await service.save(latest.copyWith(
      nickname: name.text.trim(),
      style: style,
      humor: humor,
      memoryEnabled: memory,
      adviceOnlyWhenAsked: adviceOnlyWhenAsked,
    ));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتحفظت إعداداتك')));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AuthScreen(fromProfile: true)));
    if (ok == true) await _load();
  }

  Future<void> _logout() async {
    await NotificationService.detach();
    await auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest_mode', true);
    try { await auth.ensureGuest().timeout(const Duration(seconds: 8)); } catch (_) {}
    await _load();
  }

  Future<void> _deleteAccount() async {
    final user = auth.currentUser;
    if (user == null || deleting) return;
    final uid = user.uid;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف حسابك وبياناتك؟'),
      content: const Text('هتتحذف محادثاتك وذكرياتك وتفضيلاتك من الحساب. العملية نهائية. لو مسجل بجوجل هنطلب منك تأكيد الدخول بنفس الحساب.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('رجوع')),
        TextButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('احذف الحساب'))]));
    if (confirmed != true || !mounted) return;
    setState(() => deleting = true);
    try {
      if (!user.isAnonymous) {
        final result = await auth.signInWithGoogle();
        if (result.user?.uid != uid) throw StateError('اختار نفس حساب Google لتأكيد الحذف.');
      }
      final token = await auth.idToken(forceRefresh: true).timeout(const Duration(seconds: 8));
      final endpoint = Uri.parse(AiService.buildApiUrl).replace(path: '/account');
      final response = await http.delete(endpoint,headers:{'Authorization':'Bearer $token'})
        .timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        final data = jsonDecode(response.body) as Map<String,dynamic>;
        throw StateError((data['error'] ?? 'تعذّر إكمال الحذف. جرّب تاني.').toString());
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('purge_firestore_cache',true);
      for (final key in prefs.getKeys().where((k) => k.startsWith('$uid:')).toList()) { await prefs.remove(key); }
      if (prefs.getString('maalish_legacy_owner') == uid) {
        for (final key in ['nickname','style','humor','memory_enabled','advice_only_when_asked','memories_json','sessions_json','backend_url']) {
          await prefs.remove(key); await prefs.remove('local:$key');
        }
      }
      await NotificationService.detach();
      await auth.signOut();
      await prefs.setBool('guest_mode',false);
      if (mounted) Navigator.pushAndRemoveUntil(context,MaterialPageRoute<void>(builder: (_) => const AuthScreen()),(_) => false);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error is StateError ? error.message : 'الحذف ما اكتملش. راجع الاتصال وجرّب تاني.')));
    } finally { if (mounted) setState(() => deleting = false); }
  }

  Future<void> _showMemories() async {
    final owner = auth.currentUser?.uid;
    final loaded = await service.load();
    var values = [...loaded.memories];
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, builder: (sheet) => StatefulBuilder(builder: (sheet, update) {
        Future<void> change(String old, String? replacement) async {
          if (auth.currentUser?.uid != owner) return;
          final latest = await service.load();
          final changed = [...latest.memories];
          final index = changed.indexOf(old);
          if (index < 0) return;
          if (replacement == null) { changed.removeAt(index); }
          else { changed[index] = replacement; }
          await service.save(latest.copyWith(memories: changed));
          if (sheet.mounted) update(() => values = changed);
          if (mounted) setState(() => memories = changed);
        }
        return Directionality(textDirection: TextDirection.rtl, child: SafeArea(child: SizedBox(
          height: MediaQuery.of(sheet).size.height * .75,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('معلش فاكر عني إيه؟', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('المعلومات دي بتساعد الشات الجديد يفهمك. تقدر تعدّلها أو تمسحها، وتقفل الذاكرة من الإعدادات.')),
            Expanded(child: ListView(children: [
              if (values.isEmpty) const ListTile(title: Text('لسه مفيش معلومات محفوظة.')),
              ...values.map((value) => ListTile(title: Text(value), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () async {
                  final controller = TextEditingController(text: value);
                  final replacement = await showDialog<String>(context: sheet, builder: (ctx) => AlertDialog(
                    title: const Text('تعديل المعلومة'), content: TextField(controller: controller, maxLength: 250, maxLines: 3),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('رجوع')),
                      TextButton(onPressed: () => Navigator.pop(ctx,controller.text.trim()), child: const Text('حفظ'))]));
                  // Controller lives until the dialog route has finished its transition.
                  if (replacement != null && replacement.isNotEmpty) await change(value,replacement);
                }),
                IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: () => change(value,null)),
              ]))),
            ])),
          ]))));
      }));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final user = AuthService.ready ? auth.currentUser : null;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text('أنا ومعلش', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: user != null && !user.isAnonymous
                ? Row(children: [
                    CircleAvatar(child: Text((user.displayName ?? user.phoneNumber ?? 'م').characters.first)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.displayName ?? 'حساب معلش', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(user.email ?? user.phoneNumber ?? 'مسجل الدخول', style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                    ])),
                    TextButton(onPressed: _logout, child: const Text('خروج')),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('أنت داخل كضيف', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('اربط حساب Google عشان تقدر ترجع لذاكرتك وسجل جلساتك من أجهزة تانية.', style: TextStyle(color: AppColors.text2)),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _openLogin, child: const Text('سجل بحساب Google')),
                  ]),
          ),
          const SizedBox(height: 22),
          const Text('معلش يناديني'),
          const SizedBox(height: 8),
          TextField(controller: name, decoration: const InputDecoration(hintText: 'اسمك أو اللقب اللي تحبه')),
          const SizedBox(height: 20),
          const Text('طريقة كلام معلش'),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'متوازن', label: Text('متوازن')),
              ButtonSegment(value: 'هادي', label: Text('هادي')),
              ButtonSegment(value: 'صاحبي', label: Text('صاحبي')),
              ButtonSegment(value: 'ساخر', label: Text('ساخر')),
            ],
            selected: {style},
            onSelectionChanged: (v) => setState(() => style = v.first),
          ),
          const SizedBox(height: 22),
          SwitchListTile(value: humor, onChanged: (v) => setState(() => humor = v), title: const Text('عادي تهزر معايا')),
          SwitchListTile(value: memory, onChanged: (v) => setState(() => memory = v), title: const Text('افتكر المواضيع المهمة')),
          SwitchListTile(value: adviceOnlyWhenAsked, onChanged: (v) => setState(() => adviceOnlyWhenAsked = v), title: const Text('متدينيش نصايح إلا لما أطلب')),
          const SizedBox(height: 18),
          ElevatedButton(onPressed: _save, child: const Text('احفظ الإعدادات')),
          const Divider(height: 30),
          SwitchListTile(value: pushEnabled, title: const Text('إشعارات معلش'),
            subtitle: Text(pushBusy ? 'جاري تسجيل اختيارك…' : 'تذكير عام يومي بالكتير قريب من ميعادك بالليل، ورسائل الإدارة في أي وقت. بنستخدم ساعة الاستخدام فقط. تقدر توقفها هنا.'),
            onChanged: pushBusy ? null : (value) async {
              setState(()=>pushBusy=true);
              try { await NotificationService.setEnabled(value); }
              catch(error) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error is StateError ? error.message : 'تعذّر تفعيل الإشعارات. جرّب تاني.'))); }
              final current=await NotificationService.enabled();
              if(mounted)setState(() {pushBusy=false;pushEnabled=current;});
            }),
          TextButton(onPressed:NotificationService.openSettings,child:const Text('إعدادات إشعارات الجهاز')),
          SwitchListTile(value: insightEnabled,title:const Text('مشاركة إحصائيات الجلسات'),
            subtitle:const Text('اختياري: تصنيفات عامة وشعورك قبل وبعد فقط، بدون رسائلك. إيقاف المشاركة يمسح سجلات التحليل المرتبطة بحسابك عند الاتصال.'),
            onChanged:(value) async { await InsightsService().setEnabled(value); if(mounted)setState(()=>insightEnabled=value); }),
          SwitchListTile(value: crashReports, title: const Text('مشاركة تقارير الأعطال'),
            subtitle: const Text('اختياري: معلومات تقنية عن الأعطال لمساعدتنا نصلحها. لا نضيف رسائلك أو ذكرياتك للتقارير.'),
            onChanged: (value) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('crash_reports_enabled',value);
              await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(value);
              if (mounted) setState(() => crashReports = value);
            }),
          const Divider(height: 34),
          ListTile(onTap: _showMemories, title: const Text('معلش فاكر عني إيه؟'), trailing: const Icon(Icons.chevron_left_rounded)),
          ListTile(enabled: !deleting, onTap: _deleteAccount, leading: const Icon(Icons.person_remove_outlined), title: Text(deleting ? 'جاري حذف الحساب…' : 'حذف الحساب وبياناته')),
          const ListTile(title: Text('الخصوصية'), subtitle: Text('الذاكرة والمحادثات بتتحفظ في حسابك مع نسخة محلية. تقدر تحذف كل محادثة أو معلومة لوحدها. رسائل المحادثة بتتبعت لخدمة Gemini عشان ترد عليك.'), trailing: Icon(Icons.lock_outline_rounded)),
        ],
      ),
    );
  }
}
