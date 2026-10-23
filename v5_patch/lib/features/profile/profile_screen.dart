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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await service.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      name.text = p.nickname;
      style = p.style;
      humor = p.humor;
      memory = p.memoryEnabled;
      adviceOnlyWhenAsked = p.adviceOnlyWhenAsked;
      memories = p.memories;
      guest = prefs.getBool('guest_mode') ?? false;
      loading = false;
    });
  }

  Future<void> _save() async {
    await service.save(MemoryProfile(
      nickname: name.text.trim(),
      style: style,
      humor: humor,
      memoryEnabled: memory,
      adviceOnlyWhenAsked: adviceOnlyWhenAsked,
      memories: memories,
    ));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتحفظت إعداداتك')));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AuthScreen(fromProfile: true)));
    if (ok == true) await _load();
  }

  Future<void> _logout() async {
    await auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('guest_mode', true);
    try { await auth.ensureGuest().timeout(const Duration(seconds: 8)); } catch (_) {}
    await _load();
  }

  void _showMemories() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('معلش فاكر عني إيه؟', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              if (memories.isEmpty) const Text('لسه مفيش حاجات محفوظة.'),
              if (memories.isNotEmpty) ...memories.reversed.take(12).map((e) => ListTile(leading: const Icon(Icons.memory_rounded), title: Text(e))),
              if (memories.isNotEmpty) TextButton.icon(
                onPressed: () async {
                  await service.clearMemories();
                  if (!mounted) return;
                  setState(() => memories = []);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                label: const Text('امسح الذاكرة', style: TextStyle(color: AppColors.red)),
              ),
            ]),
          ),
        ),
      ),
    );
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
          const Divider(height: 34),
          ListTile(onTap: _showMemories, title: const Text('معلش فاكر عني إيه؟'), trailing: const Icon(Icons.chevron_left_rounded)),
          const ListTile(title: Text('الخصوصية'), subtitle: Text('الذاكرة وملخصات الجلسات بتتحفظ في حسابك مع نسخة محلية. رسائل المحادثة بتتبعت لخدمة Gemini عشان ترد عليك.'), trailing: Icon(Icons.lock_outline_rounded)),
        ],
      ),
    );
  }
}
