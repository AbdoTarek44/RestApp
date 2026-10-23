import 'problem_analyzer.dart';

class MaalishReply {
  final String text;
  final String expression;
  final bool showIntentChoices;
  final bool safetyMode;
  final String emotion;
  final int intensity;
  final List<String> categories;
  final String need;
  final String stage;
  final List<String> memoryCandidates;
  final String sessionTitle;
  final String conversationSummary;

  const MaalishReply({
    required this.text,
    this.expression = 'listening',
    this.showIntentChoices = false,
    this.safetyMode = false,
    this.emotion = '',
    this.intensity = 5,
    this.categories = const [],
    this.need = 'listen',
    this.stage = 'listening',
    this.memoryCandidates = const [],
    this.sessionTitle = '',
    this.conversationSummary = '',
  });
}

class MaalishEngine {
  int _turn = 0;

  MaalishReply reply(String input) {
    _turn++;
    final a = ProblemAnalyzer.analyze(input);
    if (a.sensitive) {
      return MaalishReply(
        text: 'استنى معايا هنا. الكلام ده مهم ومش هتعامل معاه كهزار. أهم حاجة دلوقتي إنك تبقى في أمان، ولو في خطر مباشر تواصل فورًا مع شخص موثوق أو الطوارئ المحلية.',
        expression: 'worried',
        safetyMode: true,
        emotion: a.emotion,
        intensity: 9,
        categories: a.categories,
        need: 'safety',
        stage: 'safety',
        sessionTitle: a.suggestedTitle,
      );
    }
    if (_turn == 1) {
      final t = switch (a.primary) {
        'marriage' => 'الموضوع ده باين إنه واخد مساحة كبيرة منك… إيه أكتر حاجة وجعتك في اللي حصل بينكم؟',
        'family' => 'لما الزعل يبقى من الأهل بيبقى تقيل زيادة… إيه اللي حصل بالظبط؟',
        'relatives' => 'مشاكل القرايب بتتشابك بسرعة… اللي مضايقك أكتر الموقف نفسه ولا تدخل ناس تانية؟',
        'work' => 'شكلك شايل من الشغل بقالك فترة… إيه أكتر حاجة خانقاك: الناس، الضغط، ولا إحساسك إنك مش مقدَّر؟',
        'money' => 'ضغط الفلوس لوحده كفاية يضغط أي حد… أكتر حاجة مخوفاك دلوقتي إيه؟',
        'study' => 'واضح إن الدراسة بقت ضغط مش مجرد مذاكرة… إيه أكتر جزء مكركبك؟',
        'grief' => 'أنا سامعك… والفقد ملوش رد سهل. احكيلي عنه براحتك.',
        'loneliness' => 'الوحدة بتتعب حتى لو حواليك ناس… إمتى الإحساس ده بيبقى أقوى؟',
        'relationship' => 'واضح إن العلاقة نفسها سايبة أثر كبير عليك… إيه أكتر حاجة كسرتك في اللي حصل؟',
        'future' => 'أوقات القرار نفسه بيبقى أتقل من الاختيارات… إيه أكتر حاجة خايف تخسرها؟',
        'health_concern' => 'القلق على الصحة بيخلي الدماغ تسبق الأحداث… أنت مستني نتيجة ولا في حاجة حصلت فعلًا؟',
        _ => 'كمل… أنا سامعك. إيه أكتر حاجة مضايقاك في اللي حصل؟',
      };
      return MaalishReply(
        text: t,
        expression: a.emotion == 'sad' ? 'comforting' : 'listening',
        emotion: a.emotion,
        categories: a.categories,
        sessionTitle: a.suggestedTitle,
      );
    }
    if (_turn == 2) {
      return MaalishReply(
        text: 'فهمتك. واضح إن الموضوع مش موقف واحد وخلاص. تحبني أعمل إيه دلوقتي؟',
        expression: 'thinking',
        showIntentChoices: true,
        emotion: a.emotion,
        categories: a.categories,
        stage: 'understanding',
        sessionTitle: a.suggestedTitle,
      );
    }
    if (a.categories.length > 1) {
      return MaalishReply(
        text: 'حاسس إن في أكتر من حاجة داخلة في بعض. تعالى ناخدهم واحدة واحدة بدل ما كلهم يفضلوا فوق دماغك.',
        expression: 'thinking',
        emotion: a.emotion,
        categories: a.categories,
        need: 'thinking',
        stage: 'reflecting',
        sessionTitle: a.suggestedTitle,
      );
    }
    return MaalishReply(
      text: 'أنا معاك. خد راحتك وكمل من النقطة اللي شايف إنها الأهم.',
      expression: 'comforting',
      emotion: a.emotion,
      categories: a.categories,
      sessionTitle: a.suggestedTitle,
    );
  }
}
