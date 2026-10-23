import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'ai_service.dart';

class InsightsService {
  final String uid;
  InsightsService() : uid = AuthService().currentUser?.uid ?? 'local';
  static final Map<String,Future<void>> _jobs = {};
  String get _consent => '$uid:insights_consent_v11';
  String get _dirty => '$uid:insights_consent_dirty_v11';
  String get _outbox => '$uid:insights_outbox_v11';
  bool get _current => uid != 'local' && AuthService().currentUser?.uid == uid;
  Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_consent) ?? false;
  Future<void> setEnabled(bool enabled) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_consent,enabled); await p.setBool(_dirty,true);
    if (!enabled) await p.remove(_outbox);
    unawaited(flush());
  }
  Future<void> report({required String runId, required String phase, required String beforeMood,
    String afterMood = 'skip', List<String> categories = const []}) async {
    if (!_current || !await enabled()) return;
    final p=await SharedPreferences.getInstance();
    final pending=jsonDecode(p.getString(_outbox) ?? '{}') as Map<String,dynamic>;
    final old=pending[runId] as Map<String,dynamic>?;
    final prior=List<String>.from(old?['categories'] ?? []);
    pending[runId]={'runId':runId,'phase':old?['phase']=='finish'?'finish':phase,
      'beforeMood':old?['beforeMood'] ?? beforeMood,
      'afterMood':phase=='finish'?afterMood:old?['afterMood'] ?? 'skip',
      'categories':{...prior,...categories}.take(6).toList()};
    await p.setString(_outbox,jsonEncode(pending));
    unawaited(flush());
  }
  Future<void> _post(String path,Map<String,dynamic> body) async {
    if (!_current) throw StateError('Account changed');
    final token=await AuthService().idToken().timeout(const Duration(seconds:6));
    if (!_current) throw StateError('Account changed');
    final client=http.Client();
    try {
      final result=await client.post(Uri.parse(AiService.buildApiUrl).replace(path:path),
        headers:{'Content-Type':'application/json','Authorization':'Bearer $token'},body:jsonEncode(body))
        .timeout(const Duration(seconds:8));
      if(result.statusCode!=200) throw StateError('Insights sync pending');
    } finally { client.close(); }
  }
  Future<void> flush() {
    final previous=_jobs[uid] ?? Future<void>.value();
    final next=previous.catchError((_){}).then((_) async {
      if (!_current) return;
      final p=await SharedPreferences.getInstance();
      try {
        if (p.getBool(_dirty)==true) {
          final consent=p.getBool(_consent) ?? false;
          await _post('/insights/consent',{'enabled':consent});
          if(p.getBool(_consent)==consent) await p.setBool(_dirty,false);
        }
        if(!await enabled() || p.getBool(_dirty)==true) return;
        final snapshot=jsonDecode(p.getString(_outbox) ?? '{}') as Map<String,dynamic>;
        for (final entry in snapshot.entries) {
          if(!_current || !await enabled()) return;
          await _post('/insights/session',Map<String,dynamic>.from(entry.value as Map));
          final latest=jsonDecode(p.getString(_outbox) ?? '{}') as Map<String,dynamic>;
          if(jsonEncode(latest[entry.key])==jsonEncode(entry.value)) latest.remove(entry.key);
          await p.setString(_outbox,jsonEncode(latest));
        }
      } catch (_) { /* Optional events remain local for the next startup/resume. */ }
    });
    _jobs[uid]=next;
    return next.whenComplete(() {if(identical(_jobs[uid],next))_jobs.remove(uid);});
  }
}
