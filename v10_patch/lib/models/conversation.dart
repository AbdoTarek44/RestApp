import 'chat_message.dart';

class SavedMessage {
  final String id;
  final ChatMessage message;
  const SavedMessage(this.id, this.message);
  Map<String, dynamic> toJson() => {'id': id, 'text': message.text,
    'fromUser': message.fromUser, 'sentAt': message.createdAt.toIso8601String()};
  factory SavedMessage.fromJson(Map<String, dynamic> data) => SavedMessage(
    data['id'] as String,
    ChatMessage(text: data['text'] as String, fromUser: data['fromUser'] as bool,
      createdAt: DateTime.parse(data['sentAt'] as String)));
}

class Conversation {
  final String id, title, preview, mood, summary;
  final DateTime createdAt, lastMessageAt;
  final bool closed, deleted;
  final List<SavedMessage> messages;
  const Conversation({required this.id, required this.title, required this.preview,
    required this.createdAt, required this.lastMessageAt, this.mood = '', this.summary = '',
    this.closed = false, this.deleted = false, this.messages = const []});
  Conversation copyWith({String? title, String? preview, String? mood, String? summary,
    bool? closed, bool? deleted, List<SavedMessage>? messages, DateTime? lastMessageAt}) =>
    Conversation(id: id, title: title ?? this.title, preview: preview ?? this.preview,
      createdAt: createdAt, lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      mood: mood ?? this.mood, summary: summary ?? this.summary, closed: closed ?? this.closed,
      deleted: deleted ?? this.deleted, messages: messages ?? this.messages);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'preview': preview,
    'mood': mood, 'summary': summary, 'createdAt': createdAt.toIso8601String(),
    'lastMessageAt': lastMessageAt.toIso8601String(), 'closed': closed,
    'deleted': deleted, 'messages': messages.map((e) => e.toJson()).toList()};
  factory Conversation.fromJson(Map<String, dynamic> data) => Conversation(
    id: data['id'] as String, title: data['title'] as String,
    preview: data['preview'] as String, summary: data['summary'] as String? ?? '', mood: data['mood'] as String? ?? '',
    createdAt: DateTime.parse(data['createdAt'] as String),
    lastMessageAt: DateTime.parse(data['lastMessageAt'] as String),
    closed: data['closed'] == true, deleted: data['deleted'] == true,
    messages: (data['messages'] as List? ?? []).map((e) =>
      SavedMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}
