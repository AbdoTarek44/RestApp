import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../services/conversation_service.dart';
import '../../services/ai_service.dart';
import '../../services/memory_service.dart';
import '../../services/speech_service.dart';
import '../../widgets/maalish_face.dart';

class ChatScreen extends StatefulWidget {
  final String initialText;
  final String? conversationId;
  const ChatScreen({super.key, this.initialText = '', this.conversationId});
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
  final conversations = ConversationService();
  Conversation? conversation;
  bool opening = true;
  String? saveError;
  int _storedCount = 0;
  final scroll = ScrollController();
  Timer? _replyTimer;
  String? requestError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      if (widget.conversationId != null) {
        conversation = await conversations.open(widget.conversationId!);
        if (!mounted) return;
        messages.addAll(conversation!.messages.map((m) => m.message));
        _storedCount = messages.length;
      }
      if (!mounted) return;
      setState(() => opening = false);
      _scrollToEnd();
      if (widget.conversationId == null && widget.initialText.trim().isNotEmpty) {
        await send(widget.initialText);
      }
    } catch (_) {
      if (mounted) setState(() { opening = false; saveError = 'مقدرناش نفتح الفضفضة. ارجع وجرّب تاني.'; });
    }
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  });

  Future<void> _persist({String? mood, bool closed = false}) async {
    if (messages.isEmpty) return;
    final first = messages.first;
    final old = conversation ?? Conversation(id: conversations.newId(),
      title: first.text.length > 45 ? first.text.substring(0,45) : first.text,
      preview: '', createdAt: first.createdAt, lastMessageAt: first.createdAt);
    final saved = [...old.messages.take(_storedCount)];
    final added = <SavedMessage>[];
    for (var i = _storedCount; i < messages.length; i++) {
      final item = SavedMessage(conversations.newId(), messages[i]);
      saved.add(item); added.add(item);
    }
    final preview = messages.last.text;
    conversation = old.copyWith(messages: saved, closed: closed,
      title: latestTitle.isEmpty ? old.title : latestTitle.substring(0, latestTitle.length.clamp(0,120)),
      preview: preview.length > 160 ? preview.substring(0,160) : preview,
      lastMessageAt: messages.last.createdAt, mood: mood);
    // Commit all new IDs to the local outbox before any network request.
    await conversations.store(conversation!, added);
    _storedCount = messages.length;
    if (mounted) setState(() => saveError = null);
  }

  Future<void> send(String value) async {
    final text = value.trim();
    if (text.isEmpty || typing || opening || !conversations.current) return;
    if (text.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خلّي الرسالة أقل من ٥٠٠٠ حرف وقسّم الكلام على رسايل.')));
      return;
    }
    setState(() {
      messages.add(ChatMessage(text: text, fromUser: true));
      input.clear();
      typing = true;
    });

    _scrollToEnd();
    try { await _persist(); }
    catch (_) {
      if (mounted) setState(() { typing = false; saveError = 'تعذّر حفظ الرسالة على الجهاز؛ جرّب الحفظ تاني.'; });
      return;
    }
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
      if (!conversations.current) throw StateError('Account changed');
      await _persist();
      final r = await ai.reply(messages, conversationSummary: conversation?.summary ?? '');
      if (!mounted) return;
      final displayClock = Stopwatch()..start();
      setState(() {
        expression = r.expression;
        showIntent = r.showIntentChoices;
        safetyMode = r.safetyMode;
        if (r.conversationSummary.isNotEmpty && conversation != null) conversation = conversation!.copyWith(summary: r.conversationSummary);
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
      _scrollToEnd();
      try { await _persist(); }
      catch (_) { if (mounted) setState(() => saveError = 'الرد ظاهر، لكن حفظه تعذّر. اضغط إعادة الحفظ.'); }
      if (mounted) setState(() => typing = false);
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
    scroll.dispose();
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
    if (typing || opening || messages.isEmpty) return;
    try { await _persist(closed: true); if (mounted) setState(() => ended = true); }
    catch (_) { if (mounted) setState(() => saveError = 'تعذّر الحفظ. جرّب تاني.'); }
  }

  Future<void> completeSession(String mood) async {
    try { await _persist(mood: mood, closed: true); if (mounted) Navigator.pop(context); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الحفظ. ارجع للمحادثة وحاول تاني.'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (opening) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          if (saveError != null) MaterialBanner(content: Text(saveError!), actions: [
            TextButton(onPressed: () async { try { await _persist(); } catch (_) {} }, child: const Text('إعادة الحفظ')),
          ]),
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
              controller: scroll,
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
                onPressed: typing ? null : finishSession,
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
