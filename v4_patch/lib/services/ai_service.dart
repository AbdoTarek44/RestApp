import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import 'maalish_engine.dart';
import 'memory_service.dart';

class AiService {
  static const buildApiUrl = String.fromEnvironment('MAALISH_API_URL', defaultValue: '');
  final MaalishEngine fallback = MaalishEngine();
  final MemoryService memory = MemoryService();

  Uri _chatUri(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.parse(trimmed);
    if (uri.path.endsWith('/chat')) return uri;
    final path = uri.path.endsWith('/') ? '${uri.path}chat' : '${uri.path}/chat';
    return uri.replace(path: path);
  }

  Future<MaalishReply> reply(List<ChatMessage> messages) async {
    final latest = messages.last.text;
    final profile = await memory.load();
    final rawUrl = profile.backendUrl.trim().isNotEmpty ? profile.backendUrl.trim() : buildApiUrl;
    if (rawUrl.isEmpty) return fallback.reply(latest);

    try {
      final response = await http.post(
        _chatUri(rawUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messages': messages
              .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text})
              .toList(),
          'profile': {
            'nickname': profile.nickname,
            'style': profile.style,
            'humor': profile.humor,
            'adviceOnlyWhenAsked': profile.adviceOnlyWhenAsked,
            'memories': profile.memoryEnabled ? profile.memories : <String>[],
          },
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback.reply(latest);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      List<String> asStrings(dynamic value) {
        if (value is! List) return const [];
        return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }

      final rawIntensity = data['intensity'];
      final intensity = rawIntensity is num ? rawIntensity.round().clamp(1, 10).toInt() : 5;

      return MaalishReply(
        text: (data['text'] ?? 'أنا سامعك. كمل.').toString(),
        expression: (data['expression'] ?? 'listening').toString(),
        showIntentChoices: data['showIntentChoices'] == true,
        safetyMode: data['safetyMode'] == true,
        emotion: (data['emotion'] ?? '').toString(),
        intensity: intensity,
        categories: asStrings(data['categories']),
        need: (data['need'] ?? 'listen').toString(),
        stage: (data['stage'] ?? 'listening').toString(),
        memoryCandidates: asStrings(data['memoryCandidates']).take(3).toList(),
        sessionTitle: (data['sessionTitle'] ?? '').toString(),
      );
    } catch (_) {
      return fallback.reply(latest);
    }
  }

  Future<bool> healthCheck(String rawUrl) async {
    try {
      final uri = Uri.parse(rawUrl.trim());
      final path = uri.path.endsWith('/chat')
          ? uri.path.substring(0, uri.path.length - 5) + 'health'
          : (uri.path.endsWith('/') ? '${uri.path}health' : '${uri.path}/health');
      final response = await http.get(uri.replace(path: path)).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data is Map && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
