class VentSession {
  final String id;
  final String title;
  final String preview;
  final String primaryCategory;
  final List<String> categories;
  final String beforeMood;
  final String afterMood;
  final DateTime createdAt;

  const VentSession({required this.id, required this.title, required this.preview, required this.primaryCategory, required this.categories, required this.beforeMood, required this.afterMood, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'preview': preview, 'primaryCategory': primaryCategory, 'categories': categories, 'beforeMood': beforeMood, 'afterMood': afterMood, 'createdAt': createdAt.toIso8601String()};

  factory VentSession.fromJson(Map<String, dynamic> j) => VentSession(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? 'فضفضة',
    preview: j['preview']?.toString() ?? '',
    primaryCategory: j['primaryCategory']?.toString() ?? 'other',
    categories: List<String>.from(j['categories'] ?? const <String>[]),
    beforeMood: j['beforeMood']?.toString() ?? '',
    afterMood: j['afterMood']?.toString() ?? '',
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
  );
}
