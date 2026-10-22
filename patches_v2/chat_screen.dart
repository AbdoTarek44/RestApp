import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chat_message.dart';
import '../../services/ai_service.dart';
import '../../services/memory_service.dart';
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
  bool showIntent = false;
  bool safetyMode = false;
  bool ended = false;
  bool typing = false;
  bool listening = false;

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

    final r = await ai.reply(messages);
    if (!mounted) return;
    setState(() {
      typing = false;
      expression = r.expression;
      showIntent = r.showIntentChoices;
      safetyMode = r.safetyMode;
      messages.add(ChatMessage(text: r.text, fromUser: false));
    });
  }

  Future<void> toggleVoice() async {
    if (listening) {
      await speech.stop();
      if (!mounted) return;
      setState(() => listening = false);
      return;
    }
    setState(() => listening = true);
    await speech.start((text) {
      if (!mounted) return;
      setState(() => input.text = text);
    });
  }

  void chooseIntent(String intent) {
    setState(() {
      showIntent = false;
      final response = switch (intent) {
        'اسمعني بس' => 'تمام. ولا رأي ولا نصايح. كمل وأنا سامعك.',
        'قولّي رأيك' => 'هقولك رأيي، بس من غير ما أحكم عليك أو على الطرف التاني. خليني أبدأ من أكتر نقطة واضحة في كلامك.',
        'ساعدني أفكر' => 'تمام. هنفصل المشكلة حتة حتة ونشوف إيه اللي في إيدك وإيه اللي مش في إيدك.',
        _ => 'تمام 😂 بس هنخلي الهزار على قد الموقف. احكيلي أكتر.',
      };
      messages.add(ChatMessage(text: intent, fromUser: true));
      messages.add(ChatMessage(text: response, fromUser: false));
      expression = intent == 'خلينا نهزر عليها' ? 'laughing' : 'comforting';
    });
  }

  Future<void> finishSession() async {
    final profile = await memory.load();
    if (profile.memoryEnabled && messages.isNotEmpty) {
      final first = messages.firstWhere((m) => m.fromUser, orElse: () => messages.first).text;
      final clean = first.length > 80 ? '${first.substring(0, 80)}…' : first;
      await memory.addMemory(clean);
    }
    if (mounted) setState(() => ended = true);
  }

  @override
  Widget build(BuildContext context) {
    if (ended) return _MaalishMoment(onBack: () => Navigator.pop(context));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.cream,
          elevation: 0,
          title: Column(children: [
            const Text('معلش', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(listening ? 'سامع صوتك 🎙️' : typing ? 'بفكر معاك…' : 'سامعك 👂', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
          ]),
          centerTitle: true,
        ),
        body: Column(
          children: [
            if (safetyMode)
              Container(
                width: double.infinity,
                color: AppColors.red.withValues(alpha: .12),
                padding: const EdgeInsets.all(14),
                child: const Text('لو في خطر مباشر عليك أو على شخص تاني، تواصل فورًا مع شخص موثوق أو خدمات الطوارئ المحلية.', textAlign: TextAlign.center),
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
                    return const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('معلش بيفكر…', style: TextStyle(color: AppColors.text2)),
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
                      child: Text(m.text, style: TextStyle(color: m.fromUser ? Colors.white : AppColors.navy, height: 1.45)),
                    ),
                  );
                },
              ),
            ),
            if (showIntent)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['اسمعني بس', 'قولّي رأيك', 'ساعدني أفكر', 'خلينا نهزر عليها']
                      .map((e) => ActionChip(label: Text(e), onPressed: () => chooseIntent(e), backgroundColor: AppColors.softBlue, side: BorderSide.none))
                      .toList(),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.of(context).padding.bottom + 8),
              child: Row(
                children: [
                  IconButton(onPressed: finishSession, icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.green, size: 30)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: input,
                      onSubmitted: send,
                      decoration: InputDecoration(
                        hintText: listening ? 'اتكلم…' : 'احكي…',
                        prefixIcon: IconButton(
                          onPressed: toggleVoice,
                          icon: Icon(listening ? Icons.stop_circle_rounded : Icons.mic_none_rounded, color: listening ? AppColors.red : null),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(onPressed: () => send(input.text), icon: const Icon(Icons.send_rounded, color: AppColors.navy)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _MaalishMoment extends StatefulWidget {
  final VoidCallback onBack;
  const _MaalishMoment({required this.onBack});
  @override
  State<_MaalishMoment> createState() => _MaalishMomentState();
}

class _MaalishMomentState extends State<_MaalishMoment> {
  String? mood;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                children: ['😣 زي ما أنا', '😐 أخف شوية', '🙂 أحسن', '😌 تمام'].map((e) => ChoiceChip(
                  selected: mood == e,
                  label: Text(e),
                  onSelected: (_) => setState(() => mood = e),
                  selectedColor: AppColors.softBlue,
                  side: BorderSide.none,
                )).toList(),
              ),
              const SizedBox(height: 28),
              ElevatedButton(onPressed: widget.onBack, child: const Text('خلاص كده')),
            ],
          ),
        ),
      ),
    );
  }
}
