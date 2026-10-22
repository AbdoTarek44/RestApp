import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import 'maalish_engine.dart';
import 'memory_service.dart';

class AiService {
  static const buildApiUrl = String.fromEnvironment('MAALISH_API_URL', defaultValue: '');
  final MaalishEngine fallback = MaalishEngine();
  final MemoryService memory = MemoryService();

  Future<MaalishReply> reply(List<ChatMessage> messages) async {
    final latest = messages.last.text;
    final profile = await memory.load();
    final url = profile.backendUrl.trim().isNotEmpty ? profile.backendUrl.trim() : buildApiUrl;
    if (url.isEmpty) return fallback.reply(latest);
    try {
      final response = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'messages': messages.map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}).toList(),
        'profile': {'nickname': profile.nickname, 'style': profile.style, 'humor': profile.humor, 'adviceOnlyWhenAsked': profile.adviceOnlyWhenAsked, 'memories': profile.memoryEnabled ? profile.memories : <String>[]},
      })).timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) return fallback.reply(latest);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return MaalishReply(text: (data['text'] ?? data['response'] ?? 'أنا سامعك. كمل.').toString(), expression: (data['expression'] ?? 'listening').toString(), showIntentChoices: data['showIntentChoices'] == true, safetyMode: data['safetyMode'] == true);
    } catch (_) { return fallback.reply(latest); }
  }
}
