import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import 'maalish_engine.dart';
import 'memory_service.dart';
import 'auth_service.dart';

class ReplyTrace {
  final clock = Stopwatch()..start();
  final timings = <String, int>{};
  String phase = 'تجهيز الرسالة';
  String active = 'prepare';
  int stageStart = 0;
  bool finished = false;
  String? error;
  String? requestId;
  void start(String name, String label) {
    if (finished) throw TimeoutException('Reply deadline reached');
    active = name; phase = label; stageStart = clock.elapsedMilliseconds;
  }
  void complete() {
    if (!finished) timings[active] = clock.elapsedMilliseconds - stageStart;
  }
  void finish({String? failure}) {
    if (finished) return;
    if (!timings.containsKey(active)) complete();
    error = failure;
    phase = failure == null ? 'تم استلام الرد' : 'الاتصال اتأخر أو تعذّر';
    clock.stop(); timings['total'] = clock.elapsedMilliseconds; finished = true;
  }
}

class AiRequestException implements Exception {
  final String message;
  AiRequestException(this.message);
}

class AiService {
  static const buildApiUrl = String.fromEnvironment('MAALISH_API_URL', defaultValue: '');
  static const replyBudget = Duration(seconds: 20);
  final MemoryService memory = MemoryService();
  ReplyTrace? lastTrace;

  Future<MaalishReply> reply(List<ChatMessage> messages, {String conversationSummary = ''}) async {
    final trace = ReplyTrace(); lastTrace = trace;
    final client = http.Client();
    try {
      final reply = await _request(messages, trace, client, conversationSummary).timeout(replyBudget);
      trace.finish(); return reply;
    } on TimeoutException {
      trace.finish(failure: 'timeout');
      throw AiRequestException('الرد اتأخر. رسالتك موجودة؛ جرّب تاني من زر إعادة المحاولة.');
    } on AiRequestException catch (error) {
      trace.finish(failure: error.message); rethrow;
    } catch (_) {
      trace.finish(failure: 'connection_or_response');
      throw AiRequestException('مقدرناش نستلم الرد. راجع الاتصال وجرّب تاني.');
    } finally { client.close(); }
  }

  Future<MaalishReply> _request(List<ChatMessage> messages, ReplyTrace trace, http.Client client, String conversationSummary) async {
    if (messages.isEmpty) throw AiRequestException('اكتب رسالة الأول.');
    trace.start('prepare', 'تجهيز الرسالة');
    final profile = await memory.load(waitForCloud: false).timeout(const Duration(seconds: 2));
    trace.complete();
    final endpoint = Uri.tryParse(buildApiUrl.trim());
    if (endpoint == null || endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw AiRequestException('الاتصال بالخدمة غير متاح في النسخة دي.');
    }
    final chat = endpoint.replace(path: endpoint.path.endsWith('/chat') ? endpoint.path : '${endpoint.path.replaceFirst(RegExp(r'/+$'), '')}/chat');
    trace.start('auth', 'بنتأكد من الدخول');
    final token = await AuthService().idToken().timeout(const Duration(seconds: 6));
    trace.complete();
    trace.start('request', 'بنستنى رد معلش');
    final remaining = replyBudget.inMilliseconds - trace.clock.elapsedMilliseconds;
    if (remaining <= 0) throw TimeoutException('Reply deadline reached');
    final recent = messages.skip(messages.length > 20 ? messages.length - 20 : 0).toList();
    while (recent.length > 1 && utf8.encode(jsonEncode(recent.map((m) => m.text).toList())).length > 38000) {
      recent.removeAt(0);
    }
    final response = await client.post(chat,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({
        'conversationSummary': conversationSummary,
        'messages': recent.map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}).toList(),
        'profile': {'nickname': profile.nickname, 'style': profile.style, 'humor': profile.humor,
          'adviceOnlyWhenAsked': profile.adviceOnlyWhenAsked,
          'memories': profile.memoryEnabled ? profile.memories : <String>[]},
      }),
    ).timeout(Duration(milliseconds: remaining));
    trace.complete();
    trace.requestId = response.headers['x-request-id'];
    for (final match in RegExp(r'([a-z_]+);dur=([0-9.]+)').allMatches(response.headers['server-timing'] ?? '')) {
      trace.timings['server_${match.group(1)}'] = double.parse(match.group(2)!).round();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException(response.statusCode == 401
          ? 'جلسة الدخول محتاجة تتجدد. جرّب تاني أو سجل الدخول من جديد.'
          : response.statusCode == 429 ? 'طلبات كتير في وقت قصير. استنى شوية وجرّب تاني.'
          : 'خدمة الرد مش متاحة دلوقتي. جرّب تاني بعد شوية.');
    }
    trace.start('decode', 'تجهيز عرض الرد');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
      List<String> asStrings(dynamic value) {
        if (value is! List) return const [];
        return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }

      final rawIntensity = data['intensity'];
      final intensity = rawIntensity is num ? rawIntensity.round().clamp(1, 10).toInt() : 5;

      trace.complete();
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
        conversationSummary: (data['conversationSummary'] ?? '').toString(),
      );
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
