import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class MemoryProfile {
  final String nickname;
  final String style;
  final bool humor;
  final bool memoryEnabled;
  final bool adviceOnlyWhenAsked;
  final List<String> memories;
  final String backendUrl;
  const MemoryProfile({this.nickname = '', this.style = 'متوازن', this.humor = true, this.memoryEnabled = true, this.adviceOnlyWhenAsked = true, this.memories = const [], this.backendUrl = ''});
  MemoryProfile copyWith({String? nickname, String? style, bool? humor, bool? memoryEnabled, bool? adviceOnlyWhenAsked, List<String>? memories, String? backendUrl}) => MemoryProfile(nickname: nickname ?? this.nickname, style: style ?? this.style, humor: humor ?? this.humor, memoryEnabled: memoryEnabled ?? this.memoryEnabled, adviceOnlyWhenAsked: adviceOnlyWhenAsked ?? this.adviceOnlyWhenAsked, memories: memories ?? this.memories, backendUrl: backendUrl ?? this.backendUrl);
}

class MemoryService {
  static const _nickname = 'nickname', _style = 'style', _humor = 'humor', _memory = 'memory_enabled', _advice = 'advice_only_when_asked', _memories = 'memories_json', _sessions = 'sessions_json', _backend = 'backend_url';
  Future<MemoryProfile> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_memories);
    final list = raw == null ? <String>[] : List<String>.from(jsonDecode(raw));
    return MemoryProfile(nickname: p.getString(_nickname) ?? '', style: p.getString(_style) ?? 'متوازن', humor: p.getBool(_humor) ?? true, memoryEnabled: p.getBool(_memory) ?? true, adviceOnlyWhenAsked: p.getBool(_advice) ?? true, memories: list, backendUrl: p.getString(_backend) ?? '');
  }
  Future<void> save(MemoryProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nickname, profile.nickname); await p.setString(_style, profile.style); await p.setBool(_humor, profile.humor); await p.setBool(_memory, profile.memoryEnabled); await p.setBool(_advice, profile.adviceOnlyWhenAsked); await p.setString(_memories, jsonEncode(profile.memories)); await p.setString(_backend, profile.backendUrl);
  }
  Future<void> addMemory(String value) async {
    final profile = await load(); if (!profile.memoryEnabled || value.trim().isEmpty) return;
    final list = [...profile.memories]; if (!list.contains(value.trim())) list.add(value.trim()); if (list.length > 30) list.removeAt(0); await save(profile.copyWith(memories: list));
  }
  Future<void> clearMemories() async { final profile = await load(); await save(profile.copyWith(memories: [])); }
  Future<List<VentSession>> loadSessions() async {
    final p = await SharedPreferences.getInstance(); final raw = p.getString(_sessions); if (raw == null) return [];
    try { return (jsonDecode(raw) as List).map((e) => VentSession.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) { return []; }
  }
  Future<void> addSession(VentSession session) async {
    final p = await SharedPreferences.getInstance(); final sessions = await loadSessions(); sessions.insert(0, session); if (sessions.length > 50) sessions.removeRange(50, sessions.length); await p.setString(_sessions, jsonEncode(sessions.map((e) => e.toJson()).toList()));
  }
  Future<void> clearSessions() async { final p = await SharedPreferences.getInstance(); await p.remove(_sessions); }
}
