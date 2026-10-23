import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'auth_service.dart';

// Every local key and remote path is bound to the UID captured at construction.
// The local outbox is retained until the exact revision is acknowledged.
class ConversationService {
  final String uid;
  ConversationService() : uid = AuthService().currentUser?.uid ?? 'local';
  static final _changes = StreamController<void>.broadcast();
  static final Map<String, Future<void>> _queues = {};
  Stream<void> get changes => _changes.stream;
  bool get current => (AuthService().currentUser?.uid ?? 'local') == uid;
  CollectionReference<Map<String, dynamic>> get _collection =>
    FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'maalish')
      .collection('users').doc(uid).collection('conversations');
  String get _indexKey => '$uid:conversation_index_v1';
  String _key(String id) => '$uid:conversation_v1:$id';
  String _dirty(String id) => '$uid:conversation_dirty:$id';
  String _revision(String id) => '$uid:conversation_revision:$id';
  String newId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(24, (_) => chars[random.nextInt(chars.length)]).join();
  }
  Future<Conversation?> local(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(id));
    return raw == null ? null : Conversation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
  Future<List<Conversation>> listLocal() async {
    final p = await SharedPreferences.getInstance();
    final result = <Conversation>[];
    for (final id in p.getStringList(_indexKey) ?? <String>[]) {
      final item = await local(id);
      if (item != null && !item.deleted) result.add(item.copyWith(messages: []));
    }
    result.sort((a,b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return result;
  }
  Future<void> save(Conversation value) async {
    if (!current) throw StateError('Account changed');
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(value.id), jsonEncode(value.toJson()));
    final ids = p.getStringList(_indexKey) ?? <String>[];
    if (!ids.contains(value.id)) { ids.add(value.id); await p.setStringList(_indexKey, ids); }
    await p.setInt(_revision(value.id), (p.getInt(_revision(value.id)) ?? 0) + 1);
    await p.setBool(_dirty(value.id), true);
    _changes.add(null);
    unawaited(_sync(value.id));
  }
  Future<void> retryPending() async {
    final p = await SharedPreferences.getInstance();
    for (final id in p.getStringList(_indexKey) ?? <String>[]) {
      if (p.getBool(_dirty(id)) == true) unawaited(_sync(id));
    }
  }
  Future<void> _sync(String id) async {
    if (uid == 'local' || !current) return;
    final queueKey = '$uid/$id';
    final previous = _queues[queueKey] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      if (!current) return;
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_dirty(id)) != true) return;
      final revision = p.getInt(_revision(id));
      final value = await local(id);
      if (value == null) return;
      final ref = _collection.doc(id);
      try {
        final metadata = {'ownerId': uid, 'title': value.title, 'preview': value.preview,
          'mood': value.mood, 'summary': value.summary, 'closed': value.closed, 'deleted': value.deleted,
          'createdAt': Timestamp.fromDate(value.createdAt),
          'lastMessageAt': Timestamp.fromDate(value.lastMessageAt),
          'updatedAt': FieldValue.serverTimestamp()};
        // Metadata must exist before child messages; a tombstone prevents resurrection.
        await ref.set(metadata).timeout(const Duration(seconds: 8));
        if (value.deleted) {
          while (true) {
            final page = await ref.collection('messages').limit(300).get();
            if (page.docs.isEmpty) break;
            final batch = ref.firestore.batch();
            for (final doc in page.docs) { batch.delete(doc.reference); }
            await batch.commit().timeout(const Duration(seconds: 8));
          }
        } else {
          final pending = p.getStringList('$uid:pending_messages:$id') ?? <String>[];
          for (var start = 0; start < pending.length; start += 300) {
            final ids = pending.skip(start).take(300).toSet();
            final batch = ref.firestore.batch();
            for (final item in value.messages.where((m) => ids.contains(m.id))) {
              batch.set(ref.collection('messages').doc(item.id), {
                'ownerId': uid, 'text': item.message.text, 'fromUser': item.message.fromUser,
                'sentAt': Timestamp.fromDate(item.message.createdAt),
                'updatedAt': FieldValue.serverTimestamp()});
            }
            await batch.commit().timeout(const Duration(seconds: 8));
          }
          // Remove only IDs acknowledged by this revision, preserving later edits.
          final latest = p.getStringList('$uid:pending_messages:$id') ?? <String>[];
          await p.setStringList('$uid:pending_messages:$id', latest.where((e) => !pending.contains(e)).toList());
        }
        if (p.getInt(_revision(id)) == revision) await p.setBool(_dirty(id), false);
        _changes.add(null);
      } catch (_) { /* Persisted local outbox retries on resume/history refresh. */ }
    });
    _queues[queueKey] = next;
    await next;
    if (identical(_queues[queueKey], next)) _queues.remove(queueKey);
  }
  Future<void> store(Conversation value, List<SavedMessage> added) async {
    if (!current) throw StateError('Account changed');
    final p = await SharedPreferences.getInstance();
    final key = '$uid:pending_messages:${value.id}';
    final ids = {...?p.getStringList(key), ...added.map((m) => m.id)};
    await p.setStringList(key, ids.toList());
    await save(value);
  }
  Future<bool> pending(String id) async =>
    (await SharedPreferences.getInstance()).getBool(_dirty(id)) == true;
  Future<void> refresh() async {
    if (uid == 'local' || !current) return;
    await retryPending();
    final snapshot = await _collection.get().timeout(const Duration(seconds: 8));
    final p = await SharedPreferences.getInstance();
    final ids = p.getStringList(_indexKey) ?? <String>[];
    for (final doc in snapshot.docs) {
      if (p.getBool(_dirty(doc.id)) == true) continue;
      final d = doc.data(); final cached = await local(doc.id);
      final value = Conversation(id: doc.id, title: d['title'] as String,
        preview: d['preview'] as String, summary: d['summary'] as String? ?? '', mood: d['mood'] as String,
        closed: d['closed'] == true, deleted: d['deleted'] == true,
        createdAt: (d['createdAt'] as Timestamp).toDate(),
        lastMessageAt: (d['lastMessageAt'] as Timestamp).toDate(),
        messages: d['deleted'] == true ? [] : cached?.messages ?? []);
      await p.setString(_key(doc.id), jsonEncode(value.toJson()));
      if (!ids.contains(doc.id)) ids.add(doc.id);
    }
    if (!current) return;
    await p.setStringList(_indexKey, ids);
    _changes.add(null);
  }
  Future<Conversation> open(String id) async {
    var value = await local(id);
    if (uid != 'local') {
      final ref = _collection.doc(id);
      try {
        final meta = await ref.get().timeout(const Duration(seconds: 8));
        if (meta.data()?['deleted'] == true) throw StateError('Conversation deleted');
        final remote = await ref.collection('messages').get().timeout(const Duration(seconds: 8));
        final merged = <String, SavedMessage>{for (final m in value?.messages ?? <SavedMessage>[]) m.id: m};
        for (final doc in remote.docs) {
          final d = doc.data();
          merged.putIfAbsent(doc.id, () => SavedMessage(doc.id, ChatMessage(
            text: d['text'] as String, fromUser: d['fromUser'] as bool,
            createdAt: (d['sentAt'] as Timestamp).toDate())));
        }
        final messages = merged.values.toList()..sort((a,b) {
          final order = a.message.createdAt.compareTo(b.message.createdAt);
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
        if (value != null) {
          value = value.copyWith(messages: messages);
          await (await SharedPreferences.getInstance()).setString(_key(id), jsonEncode(value.toJson()));
        }
      } on StateError { rethrow; }
      catch (_) { if (value == null || value.messages.isEmpty) rethrow; }
    }
    if (!current || value == null || value.deleted) throw StateError('Conversation unavailable');
    return value;
  }
  Future<void> delete(Conversation value) async => save(value.copyWith(
    deleted: true, title: '', preview: '', mood: '', summary: '', messages: []));
}
