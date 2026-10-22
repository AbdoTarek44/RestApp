class ProblemAnalysis {
  final String primary;
  final List<String> categories;
  final String emotion;
  final int intensity;
  final bool sensitive;
  final String suggestedTitle;
  const ProblemAnalysis({required this.primary, required this.categories, required this.emotion, required this.intensity, required this.sensitive, required this.suggestedTitle});
}

class ProblemAnalyzer {
  static const _groups = <String, List<String>>{
    'marriage': ['مراتي','جوزي','زوجي','زوجتي','زواج','جواز','طلاق','خيانة','خانتني','خاني','حماتي','حمايا','خطوبتي','خطيبتي','خطيبي'],
    'family': ['امي','أمي','ابويا','أبويا','والدي','والدتي','اهلي','أهلي','اخويا','أخويا','اختي','أختي','ابني','بنتي','اولادي','أولادي','العيلة','العائلة'],
    'relatives': ['قرايبي','قريبي','قريبتي','عمي','خالتي','خالي','عمتي','ابن عمي','بنت عمي','ميراث','ورث'],
    'friends': ['صاحبي','صحبي','صاحبتي','صديقي','صديقتي','اصحابي','أصحابي','صحابي'],
    'work': ['شغل','مدير','زميلي','زميل','شركة','مرتب','وظيفة','استقالة','فصلوني','ترقية','كارير','career'],
    'money': ['فلوس','ديون','مديون','قسط','اقساط','أقساط','مصاريف','خسرت','خسارة','قرض'],
    'study': ['دراسة','جامعة','كلية','امتحان','امتحانات','مدرسة','درجات','مذاكرة','رسوب','سقطت'],
    'relationship': ['حبيبتي','حبيبي','سابني','سابتني','انفصلنا','فراق','ارتباط','علاقة','غيرة'],
    'grief': ['مات','وفاة','اتوفى','توفى','فقدت','ماتت','ماتلي','جنازة'],
    'loneliness': ['لوحدي','وحيد','وحدة','محدش','مفيش حد','مش لاقي حد'],
    'self': ['فاشل','مش واثق','ثقة','شكلي','كرهت نفسي','مش بحب نفسي','جلد الذات','مقارنة'],
    'future': ['المستقبل','مستقبلي','تايه','مش عارف اعمل ايه','مش عارف أعمل إيه','قرار','اسافر','أسافر','هجرة'],
    'health_concern': ['مرض','مريض','تحليل','نتيجة التحليل','عملية','دكتور','صحة','سرطان','مستشفى'],
    'daily_life': ['زحمة','مواصلات','العربية','الموبايل','النت','خدمة','طلب','يومي','اليوم باظ'],
  };

  static ProblemAnalysis analyze(String raw) {
    final text = raw.toLowerCase();
    final found = <String>[];
    _groups.forEach((key, words) { if (words.any(text.contains)) found.add(key); });
    if (found.isEmpty) found.add('other');
    String emotion = 'frustrated';
    if (['حزين','زعلان','بعيط','بكيت','مكسور','موجوع'].any(text.contains)) emotion = 'sad';
    if (['قلقان','خايف','خوف','متوتر','توتر'].any(text.contains)) emotion = 'anxious';
    if (['متعصب','متنرفز','غضبان','مستفز','عصبي'].any(text.contains)) emotion = 'angry';
    if (['مضحك','ضحكت','😂','هههه'].any(text.contains)) emotion = 'amused';
    int intensity = 4;
    if (['مخنوق جدا','مخنوق جدًا','مش قادر','انهرت','منهار','كرهت حياتي','خلاص'].any(text.contains)) intensity = 8;
    if (['شوية','حاجة بسيطة','موقف صغير'].any(text.contains)) intensity = 2;
    final sensitive = ['هموت نفسي','هقتل نفسي','انتحر','مش عايز اعيش','مش عايز أعيش','ضربني','بيهددني','هقتل','اغتصاب','اعتداء'].any(text.contains);
    final primary = found.first;
    return ProblemAnalysis(primary: primary, categories: found, emotion: emotion, intensity: intensity, sensitive: sensitive, suggestedTitle: _title(primary));
  }

  static String _title(String c) => switch (c) {
    'marriage' => 'موضوع بيني وبين شريك حياتي', 'family' => 'موضوع في البيت', 'relatives' => 'مشكلة مع القرايب', 'friends' => 'موضوع مع صحابي',
    'work' => 'ضغط الشغل', 'money' => 'ضغط الفلوس', 'study' => 'ضغط الدراسة', 'relationship' => 'موضوع في العلاقة', 'grief' => 'فقد ووجع',
    'loneliness' => 'إحساس بالوحدة', 'self' => 'أنا مع نفسي', 'future' => 'قرار ومُستقبل', 'health_concern' => 'قلق على الصحة', 'daily_life' => 'اليوم اللي باظ', _ => 'فضفضة',
  };

  static String arabicLabel(String c) => switch (c) {
    'marriage' => 'زوجية', 'family' => 'أهل', 'relatives' => 'قرايب', 'friends' => 'أصحاب', 'work' => 'شغل', 'money' => 'فلوس', 'study' => 'دراسة',
    'relationship' => 'علاقة', 'grief' => 'فقد', 'loneliness' => 'وحدة', 'self' => 'ثقة ونفس', 'future' => 'مستقبل وقرارات', 'health_concern' => 'قلق صحي', 'daily_life' => 'يوميات', _ => 'أخرى',
  };
}
