import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session.dart';
import '../../services/memory_service.dart';
import '../../services/problem_analyzer.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final service = MemoryService();
  List<VentSession> sessions = [];
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final s = await service.loadSessions(); if (mounted) setState(() { sessions = s; loading = false; }); }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return SafeArea(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(22), children: [
      Row(children: [Expanded(child: Text('فضفضاتي', style: Theme.of(context).textTheme.headlineLarge)), if (sessions.isNotEmpty) IconButton(onPressed: () async { await service.clearSessions(); await _load(); }, icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.red))]),
      const SizedBox(height: 18),
      if (sessions.isEmpty) Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: const Text('لسه مفيش فضفضات محفوظة. لما تخلص أول جلسة هتظهر هنا.', textAlign: TextAlign.center)),
      ...sessions.map((i) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(i.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy))), Text('${i.createdAt.day}/${i.createdAt.month}/${i.createdAt.year}', style: const TextStyle(color: AppColors.text2))]),
        const SizedBox(height: 8), Text(i.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text2)), const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 7, children: [...i.categories.take(3).map((c) => Chip(label: Text(ProblemAnalyzer.arabicLabel(c)), side: BorderSide.none, backgroundColor: AppColors.softBlue)), if (i.afterMood.isNotEmpty) Chip(label: Text(i.afterMood), side: BorderSide.none, backgroundColor: AppColors.green.withValues(alpha: .20))]),
      ]))),
    ])));
  }
}
