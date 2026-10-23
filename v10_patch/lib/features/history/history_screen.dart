import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/conversation.dart';
import '../../models/session.dart';
import '../../services/conversation_service.dart';
import '../../services/memory_service.dart';
import '../chat/chat_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with WidgetsBindingObserver {
  ConversationService service = ConversationService();
  final memory = MemoryService();
  List<Conversation> conversations = [];
  List<VentSession> legacy = [];
  bool loading = true, refreshing = true;
  String? notice;
  StreamSubscription<void>? subscription;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = service.changes.listen((_) => _local());
    _load();
  }
  @override
  void dispose() { subscription?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }
  Future<void> _local() async {
    final data = await service.listLocal();
    if (mounted && service.current) setState(() { conversations = data; loading = false; });
  }
  Future<void> _load() async {
    if (mounted) setState(() => refreshing = true);
    if (!service.current) service = ConversationService();
    await _local();
    try {
      final previous = await memory.loadSessions();
      if (mounted) setState(() => legacy = previous);
      await service.refresh();
      if (mounted) setState(() => notice = null);
    } catch (_) {
      if (mounted) setState(() => notice = 'بتشوف النسخة المحفوظة على الجهاز. اسحب لتحديث المزامنة.');
    }
    await _local();
    if (mounted) setState(() => refreshing = false);
  }
  Future<bool> _confirm() async => await showDialog<bool>(context: context,
    builder: (ctx) => AlertDialog(title: const Text('حذف الفضفضة؟'),
      content: const Text('هتتمسح رسائلها من الجهاز والحساب عند الاتصال. المعلومات المحفوظة في الذاكرة تقدر تمسحها من «أنا ومعلش».'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('رجوع')),
        TextButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('حذف'))])) ?? false;
  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
  @override
  Widget build(BuildContext context) => SafeArea(child: RefreshIndicator(onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(22), physics: const AlwaysScrollableScrollPhysics(), children: [
      Text('فضفضاتي', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text('افتح أي فضفضة وكمّل من آخر نقطة. كلامك بيتحفظ تلقائيًا.'),
      if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(notice!)),
      if (loading || refreshing) const LinearProgressIndicator(),
      if (!loading && conversations.isEmpty && legacy.isEmpty)
        const Padding(padding: EdgeInsets.all(30), child: Text('أول فضفضة هتبدأها هتلاقيها هنا.')),
      ...conversations.map((item) => Card(child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.preview}\n${_date(item.lastMessageAt)}${item.mood.isEmpty ? '' : ' · ${item.mood}'}', maxLines: 3, overflow: TextOverflow.ellipsis),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: item.id)));
          await _load();
        },
        trailing: IconButton(tooltip: 'حذف الفضفضة', icon: const Icon(Icons.delete_outline), onPressed: () async {
          if (await _confirm()) { await service.delete(item); await _local(); }
        }),
      ))),
      if (legacy.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('ملخصات النسخ السابقة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const Text('النسخ القديمة حفظت ملخصات فقط؛ الرسائل الكاملة مش متاحة للاسترجاع.'),
        ...legacy.map((item) => Card(child: ListTile(title: Text(item.title),
          subtitle: Text('${item.preview}\n${_date(item.createdAt)}'),
          onTap: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
            title: Text(item.title), content: Text(item.preview), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
              TextButton(onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatScreen(initialText: 'عايز أرجع لموضوع ${item.title}. الملخص القديم: ${item.preview}')));
              }, child: const Text('ابدأ محادثة من الملخص'))])),
          trailing: IconButton(tooltip: 'حذف الملخص', icon: const Icon(Icons.delete_outline), onPressed: () async {
            if (await _confirm()) { await memory.deleteSession(item.id); await _load(); }
          })))),
      ],
    ])));
}
