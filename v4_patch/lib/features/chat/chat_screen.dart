import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../services/ai_service.dart';
import '../../services/memory_service.dart';
import '../../services/problem_analyzer.dart';
import '../../services/speech_service.dart';
import '../../widgets/maalish_face.dart';

class ChatScreen extends StatefulWidget {
  final String initialText;
  const ChatScreen({super.key, required this.initialText});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final ai = AiService();
  final speech = SpeechService();
  final memory = MemoryService();
  final messages = <ChatMessage>[];

  String expression = 'listening';
  bool showIntent = false, safetyMode = false, ended = false, typing = false, listening = false;
  String latestTitle = '';
  String latestEmotion = '';
  List<String> latestCategories = const [];
  VentSession? pendingSession;
  Timer? _replyTimer;
  String? requestError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => send(widget.initialText));
  }

  Future<void> send(String value) async {
    final text = value.trim();
    if (text.isEmpty || typing) return;
    setState(() {
      messages.add(ChatMessage(text: text, fromUser: true));
      input.clear();
      typing = true;
    });

    await _requestReply();
  }

  Future<void> _requestReply() async {
    if (messages.isEmpty) return;
    setState(() { typing = true; requestError = null; });
    _replyTimer?.cancel();
    _replyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && typing) setState(() {});
    });
    try {
      final r = await ai.reply(messages);
      if (!mounted) return;
      final displayClock = Stopwatch()..start();
      setState(() {
        typing = false;
        expression = r.expression;
        showIntent = r.showIntentChoices;
        safetyMode = r.safetyMode;
        if (r.sessionTitle.trim().isNotEmpty) latestTitle = r.sessionTitle.trim();
        if (r.emotion.trim().isNotEmpty) latestEmotion = r.emotion.trim();
        if (r.categories.isNotEmpty) latestCategories = r.categories;
        messages.add(ChatMessage(text: r.text, fromUser: false));
      });
      final trace = ai.lastTrace;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        displayClock.stop();
        trace?.timings['display'] = displayClock.elapsedMilliseconds;
      });
      unawaited(_remember(r.memoryCandidates));
    } on AiRequestException catch (error) {
      if (mounted) setState(() { typing = false; requestError = error.message; });
    } catch (_) {
      if (mounted) setState(() { typing = false; requestError = 'تعذّر استلام الرد. جرّب تاني.'; });
    } finally { _replyTimer?.cancel(); }
  }

  void _showTiming() {
    final t = ai.lastTrace;
    const labels = {
      'prepare': 'تجهيز الرسالة', 'auth': 'التأكد من الدخول',
      'request': 'الاتصال واستلام الرد', 'decode': 'قراءة الرد',
      'server_auth': 'تحقق الدخول داخل السيرفر', 'server_gemini': 'انتظار Gemini',
      'server_total': 'إجمالي وقت السيرفر', 'display': 'عرض الرد على الشاشة',
      'total': 'الإجمالي قبل عرض الرد',
    };
    final lines = t == null ? 'لسه مفيش طلب.' : [
      'الإصدار: V9 تجربة', 'الحالة: ${t.phase}',
      for (final entry in t.timings.entries)
        '${labels[entry.key] ?? entry.key}: ${(entry.value / 1000).toStringAsFixed(2)} ثانية',
      if (t.timings.containsKey('request') && t.timings.containsKey('server_total'))
        'خارج السيرفر (تقريبي): ${((t.timings['request']! - t.timings['server_total']!).clamp(0, 100000) / 1000).toStringAsFixed(2)} ثانية',
      if (t.error != null) 'نتيجة الطلب: ${t.error}',
      if (t.requestId != null) 'رقم التشخيص: ${t.requestId}',
      'الأوقات الفرعية أجزاء من الإجمالي، مش بتتجمع عليه.',
    ].join('\n');
    showDialog<void>(context: context, builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(title: const Text('تفاصيل زمن الرد'), scrollable: true,
        content: SelectableText(lines),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('تمام'))]),
    ));
  }

  @override
  void dispose() {
    _replyTimer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> _remember(List<String> candidates) async {
    if (candidates.isEmpty) return;
    try {
      final profile = await memory.load();
      if (!profile.memoryEnabled) return;
      for (final candidate in candidates) {
        await memory.addMemory(candidate);
      }
    } catch (_) { /* Reply is already displayed; local data stays available. */ }
  }

  Future<void> toggleVoice() async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    setState(() => listening = true);
    await speech.start((text) {
      if (mounted) setState(() => input.text = text);
    });
  }

  Future<void> chooseIntent(String intent) async {
    setState(() => showIntent = false);
    await send(intent);
  }

  Future<void> finishSession() async {
    final userMessages = messages.where((m) => m.fromUser).map((m) => m.text).toList();
    if (userMessages.isNotEmpty) {
      final combined = userMessages.join(' ');
      final analysis = ProblemAnalyzer.analyze(combined);
      final first = userMessages.first;
      final preview = first.length > 110 ? '${first.substring(0, 110)}…' : first;
      final categories = latestCategories.isNotEmpty ? latestCategories : analysis.categories;
      final title = latestTitle.isNotEmpty ? latestTitle : analysis.suggestedTitle;
      final emotion = latestEmotion.isNotEmpty ? latestEmotion : analysis.emotion;
      pendingSession = VentSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        preview: preview,
        primaryCategory: categories.isNotEmpty ? categories.first : analysis.primary,
        categories: categories,
        beforeMood: emotion,
        afterMood: '',
        createdAt: DateTime.now(),
      );
    }
    if (mounted) setState(() => ended = true);
  }

  Future<void> completeSession(String mood) async {
    final p = pendingSession;
    if (p != null) {
      await memory.addSession(VentSession(
        id: p.id,
        title: p.title,
        preview: p.preview,
        primaryCategory: p.primaryCategory,
        categories: p.categories,
        beforeMood: p.beforeMood,
        afterMood: mood,
        createdAt: p.createdAt,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (ended) return _MaalishMoment(onDone: completeSession);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          elevation: 0,
          title: Column(children: [
            const Text('معلش', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              safetyMode ? 'معاك بجدية 🤍' : listening ? 'سامع صوتك 🎙️' : typing ? '${ai.lastTrace?.phase ?? 'بجهز الرد'} (${(ai.lastTrace?.clock.elapsedMilliseconds ?? 0) ~/ 1000} ث)' : 'سامعك 👂',
              style: const TextStyle(fontSize: 12, color: AppColors.text2),
            ),
          ]),
          centerTitle: true,
          actions: [IconButton(onPressed: _showTiming, tooltip: 'تفاصيل زمن الرد', icon: const Icon(Icons.timer_outlined))],
        ),
        body: Column(children: [
          if (safetyMode)
            Container(
              width: double.infinity,
              color: AppColors.red.withValues(alpha: .12),
              padding: const EdgeInsets.all(14),
              child: const Text(
                'لو في خطر مباشر عليك أو على شخص تاني، تواصل فورًا مع شخص موثوق أو خدمات الطوارئ المحلية.',
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: MaalishFace(expression: listening ? 'listening' : expression, size: 72),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              itemCount: messages.length + (typing ? 1 : 0),
              itemBuilder: (_, i) {
                if (typing && i == messages.length) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(ai.lastTrace?.phase ?? 'بجهز الرد…', style: const TextStyle(color: AppColors.text2)),
                    ),
                  );
                }
                final m = messages[i];
                return Align(
                  alignment: m.fromUser ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 310),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: m.fromUser ? AppColors.blue : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(color: m.fromUser ? Colors.white : AppColors.navy, height: 1.45),
                    ),
                  ),
                );
              },
            ),
          ),
          if (requestError != null)
            MaterialBanner(content: Text(requestError!), actions: [
              TextButton(onPressed: typing ? null : _requestReply, child: const Text('إعادة المحاولة')),
              TextButton(onPressed: _showTiming, child: const Text('تفاصيل الزمن')),
            ]),
          if (showIntent && !safetyMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['اسمعني بس','قولّي رأيك','ساعدني أفكر','خلينا نهزر عليها']
                    .map((e) => ActionChip(
                          label: Text(e),
                          onPressed: () => chooseIntent(e),
                          backgroundColor: AppColors.softBlue,
                          side: BorderSide.none,
                        ))
                    .toList(),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.of(context).padding.bottom + 8),
            child: Row(children: [
              IconButton(
                onPressed: finishSession,
                icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.green, size: 30),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: input,
                  onSubmitted: send,
                  decoration: InputDecoration(
                    hintText: listening ? 'اتكلم…' : 'احكي…',
                    prefixIcon: IconButton(
                      onPressed: toggleVoice,
                      icon: Icon(
                        listening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                        color: listening ? AppColors.red : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(onPressed: () => send(input.text), icon: const Icon(Icons.send_rounded, color: AppColors.navy)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MaalishMoment extends StatefulWidget {
  final Future<void> Function(String mood) onDone;
  const _MaalishMoment({required this.onDone});
  @override
  State<_MaalishMoment> createState() => _MaalishMomentState();
}

class _MaalishMomentState extends State<_MaalishMoment> {
  String mood = '';
  bool saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const MaalishFace(expression: 'comforting', size: 150),
                const SizedBox(height: 30),
                const Text('يمكن المشكلة لسه موجودة…', style: TextStyle(fontSize: 20, color: AppColors.navy)),
                const SizedBox(height: 10),
                const Text('بس على الأقل طلعت اللي جواك.', style: TextStyle(fontSize: 18, color: AppColors.text2)),
                const SizedBox(height: 22),
                const Text('معلش.', style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: AppColors.orange)),
                const SizedBox(height: 34),
                Text('بقيت عامل إيه؟', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['😣 زي ما أنا','😐 أخف شوية','🙂 أحسن','😌 تمام']
                      .map((e) => ChoiceChip(
                            selected: mood == e,
                            label: Text(e),
                            onSelected: (_) => setState(() => mood = e),
                            selectedColor: AppColors.softBlue,
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          await widget.onDone(mood);
                        },
                  child: Text(saving ? 'بحفظ…' : 'خلاص كده'),
                ),
              ],
            ),
          ),
        ),
      );
}
