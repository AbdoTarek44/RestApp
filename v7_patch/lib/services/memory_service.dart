import 'dart:convert';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_core/firebase_core.dart';

import 'auth_service.dart';

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

  static final Map<String, Future<void>> _hydrations = {};

  static Future<void> _writes = Future.value();

  static const _cloudKeys = [_nickname, _style, _humor, _memory, _advice, _memories];

  static String? get _uid => AuthService().currentUser?.uid;

  static String _key(String scope, String value) => '$scope:$value';

  static DocumentReference<Map<String, dynamic>> _document(String uid) =>

      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'maalish')

          .collection('users').doc(uid).collection('state').doc('current');



  Future<void> _hydrate(SharedPreferences p) async {

    final uid = _uid;

    if (uid == null) return;

    await _hydrations.putIfAbsent(uid, () async {

      // Assign legacy local data to one account only, never subsequent accounts.

      if (!p.containsKey('maalish_legacy_owner')) {

        await p.setString('maalish_legacy_owner', uid);

        for (final name in [..._cloudKeys, _sessions, _backend]) {

          final value = p.get('local:$name') ?? p.get(name);

          if ([_humor, _memory, _advice].contains(name)) {

            if (value is bool) await p.setBool('$uid:$name', value);

          } else if (value is String) {

            await p.setString('$uid:$name', value);

          }

        }

      }

      try {

        if (p.getBool('$uid:cloud_dirty') == true) {

          _enqueue(p, uid);

          return;

        }

        final snapshot = await _document(uid).get().timeout(const Duration(seconds: 4));

        final data = snapshot.data();

        if (data == null) { _enqueue(p, uid); return; }

        final profile = jsonDecode(data['profileJson'] as String) as Map<String, dynamic>;

        final sessions = jsonDecode(data['sessionsJson'] as String);

        if (sessions is! List) return;

        for (final name in _cloudKeys) {

          final value = profile[name];

          if ([_humor, _memory, _advice].contains(name)) {

            if (value is bool) await p.setBool('$uid:$name', value);

          } else if (value is String) {

            await p.setString('$uid:$name', value);

          }

        }

        await p.setString('$uid:$_sessions', jsonEncode(sessions));

      } catch (_) {

        // Keep local data available offline; retry hydration on the next load.

        scheduleMicrotask(() => _hydrations.remove(uid));

      }

    });

  }



  void _enqueue(SharedPreferences p, String uid) {

    _writes = _writes.catchError((_) {}).then((_) async {

      final revision = p.getInt('$uid:cloud_revision') ?? 0;

      final profile = {for (final name in _cloudKeys) name: p.get('$uid:$name')};

      try {

        await _document(uid).set({

          'ownerId': uid,

          'profileJson': jsonEncode(profile),

          'sessionsJson': p.getString('$uid:$_sessions') ?? '[]',

          'updatedAt': FieldValue.serverTimestamp(),

        }).timeout(const Duration(seconds: 5));

        if ((p.getInt('$uid:cloud_revision') ?? 0) == revision) {

          await p.setBool('$uid:cloud_dirty', false);

        }

      } catch (_) { /* Local edits remain dirty for a future retry. */ }

    });

  }



  Future<void> _changed(SharedPreferences p, String? uid) async {

    if (uid == null) return;

    await p.setBool('$uid:cloud_dirty', true);

    await p.setInt('$uid:cloud_revision', (p.getInt('$uid:cloud_revision') ?? 0) + 1);

    _enqueue(p, uid);

  }

  Future<MemoryProfile> load({bool waitForCloud = true}) async {

    final scope = _uid ?? 'local';

    final p = await SharedPreferences.getInstance();

    if (waitForCloud) {
      await _hydrate(p);
    } else {
      unawaited(_hydrate(p).catchError((_) {}));
    }

    if ((_uid ?? 'local') != scope) throw StateError('Account changed');

    final raw = p.getString(_key(scope, _memories));

    var list = <String>[];

    try {

      final decoded = raw == null ? [] : jsonDecode(raw);

      if (decoded is List) list = decoded.whereType<String>().take(30).map((v) => v.length <= 250 ? v : v.substring(0, 250)).toList();

    } catch (_) {}

    final savedStyle = p.getString(_key(scope, _style)) ?? 'متوازن';

    final safeStyle = ['متوازن', 'هادي', 'صاحبي', 'ساخر'].contains(savedStyle) ? savedStyle : 'متوازن';

    return MemoryProfile(nickname: p.getString(_key(scope, _nickname)) ?? '', style: safeStyle, humor: p.getBool(_key(scope, _humor)) ?? true, memoryEnabled: p.getBool(_key(scope, _memory)) ?? true, adviceOnlyWhenAsked: p.getBool(_key(scope, _advice)) ?? true, memories: list, backendUrl: p.getString(_key(scope, _backend)) ?? '');

  }

  Future<void> save(MemoryProfile profile) async {

    final scope = _uid ?? 'local';

    final p = await SharedPreferences.getInstance();

    await _hydrate(p);

    if ((_uid ?? 'local') != scope) throw StateError('Account changed');

    await p.setString(_key(scope, _nickname), profile.nickname.length <= 80 ? profile.nickname : profile.nickname.substring(0, 80)); await p.setString(_key(scope, _style), profile.style); await p.setBool(_key(scope, _humor), profile.humor); await p.setBool(_key(scope, _memory), profile.memoryEnabled); await p.setBool(_key(scope, _advice), profile.adviceOnlyWhenAsked); await p.setString(_key(scope, _memories), jsonEncode(profile.memories.take(30).map((v) => v.length <= 250 ? v : v.substring(0, 250)).toList())); await p.setString(_key(scope, _backend), profile.backendUrl); await _changed(p, scope == 'local' ? null : scope);

  }

  Future<void> addMemory(String value) async {

    final startingUid = _uid;

    final profile = await load(); if (_uid != startingUid) return; if (!profile.memoryEnabled || value.trim().isEmpty) return;

    final list = [...profile.memories]; if (!list.contains(value.trim())) list.add(value.trim()); if (list.length > 30) list.removeAt(0); await save(profile.copyWith(memories: list));

  }

  Future<void> clearMemories() async { final startingUid = _uid; final profile = await load(); if (_uid != startingUid) return; await save(profile.copyWith(memories: [])); }

  Future<List<VentSession>> loadSessions() async {

    final scope = _uid ?? 'local';

    final p = await SharedPreferences.getInstance();

    await _hydrate(p);

    if ((_uid ?? 'local') != scope) throw StateError('Account changed'); final raw = p.getString(_key(scope, _sessions)); if (raw == null) return [];

    try { return (jsonDecode(raw) as List).map((e) => VentSession.fromJson(Map<String, dynamic>.from(e))).toList(); } catch (_) { return []; }

  }

  Future<void> addSession(VentSession session) async {

    final scope = _uid ?? 'local';

    final p = await SharedPreferences.getInstance();

    await _hydrate(p);

    if ((_uid ?? 'local') != scope) throw StateError('Account changed'); final sessions = await loadSessions(); if ((_uid ?? 'local') != scope) return; sessions.insert(0, session); if (sessions.length > 50) sessions.removeRange(50, sessions.length); await p.setString(_key(scope, _sessions), jsonEncode(sessions.map((e) => e.toJson()).toList())); await _changed(p, scope == 'local' ? null : scope);

  }

  Future<void> deleteSession(String id) async {
    final scope = _uid ?? 'local';
    final sessions = await loadSessions();
    if ((_uid ?? 'local') != scope) throw StateError('Account changed');
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(scope, _sessions), jsonEncode(sessions.where((s) => s.id != id).map((s) => s.toJson()).toList()));
    await _changed(p, scope == 'local' ? null : scope);
  }

  Future<void> clearSessions() async { final scope = _uid ?? 'local';

    final p = await SharedPreferences.getInstance(); await _hydrate(p); if ((_uid ?? 'local') != scope) return; await p.remove(_key(scope, _sessions)); await _changed(p, scope == 'local' ? null : scope); }

}

