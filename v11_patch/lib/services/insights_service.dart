import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'ai_service.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

class InsightsService {
  final String uid;
  InsightsService() : uid = AuthService().currentUser?.uid ?? 'local';
  static final Map<String,Future<void>> _jobs = {};
  static final Map<String,Future<void>> _edits = {};
  static final Map<String,int> _revisions = {};
  String get _consent => '$uid:insights_consent_v12';
  String get _dirty => '$uid:insights_consent_dirty_v12';
  String get _outbox => '$uid:insights_outbox_v12';
  bool get _current => uid != 'local' && AuthService().currentUser?.uid == uid;
  Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_consent) ?? false;
  Future<bool> requireDisclosure(BuildContext context) async {
    if(await enabled())return true;
    if(!context.mounted)return false;
    final accepted=await showDialog<bool>(context:context,barrierDismissible:false,
      builder:(dialog)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('قبل ما نبدأ نحكي'),scrollable:true,
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('معلش تطبيق تابع لشركة Increase. رسائلك بتتعالج عبر خدمات ذكاء اصطناعي خارجية لتوليد الرد، وبتتحفظ في حسابك عشان تقدر ترجع وتكمّل.'),
        const SizedBox(height:12),const Text('ضمن تشغيل الخدمة، بنسجّل تصنيفات عامة للموضوع وشعورك لو اخترته قبل وبعد الفضفضة، عشان نفهم الاحتياجات ونقيّم تجربة التطبيق. السجلات مرتبطة بمعرّف حسابك للحذف وعدّ المستخدمين؛ الإدارة بتشوف أرقامًا مجمّعة من غير نصوص الرسائل أو عناوين الفضفضات. ده تصنيف تلقائي ممكن يخطئ، ومش تقييمًا طبيًا.'),
        const SizedBox(height:12),const Text('تقدر تتخطّى اختيار الشعور، وتحذف حسابك وبياناته من «أنا ومعلش». الموافقة دي تخص بيانات الخدمة، والإشعارات وتقارير الأعطال ليهم اختيارات مستقلة.'),
        TextButton(onPressed:NotificationService.openPrivacy,child:const Text('اقرأ سياسة الخصوصية كاملة')),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('أرجع')),
        FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('موافق وأكمل'))])));
    if(accepted!=true || !_current)return false;
    await setEnabled(true);return true;
  }
  Future<void> refreshConsent() async {
    if(!_current)return;
    final revision=_revisions[uid]??0;
    final p=await SharedPreferences.getInstance();if(p.getBool(_dirty)==true)return;
    final client=http.Client();
    try{
      final token=await AuthService().idToken().timeout(const Duration(seconds:4));
      if(!_current)return;
      final result=await client.get(Uri.parse(AiService.buildApiUrl).replace(path:'/insights/consent'),
        headers:{'Authorization':'Bearer $token'}).timeout(const Duration(seconds:4));
      if(result.statusCode==200&&p.getBool(_dirty)!=true&&_current&&revision==(_revisions[uid]??0)){
        final data=jsonDecode(result.body) as Map<String,dynamic>;
        final consent=data['enabled']==true && data['policyVersion']==12;
        await p.setBool(_consent,consent);if(!consent)await p.remove(_outbox);
      }
    }catch(_){}finally{client.close();}
  }
  Future<void> _edit(Future<void> Function() work) {
    final previous=_edits[uid] ?? Future<void>.value();
    final next=previous.catchError((_){}).then((_)=>work());
    _edits[uid]=next;
    return next.whenComplete((){if(identical(_edits[uid],next))_edits.remove(uid);});
  }
  Future<void> setEnabled(bool enabled) {
    _revisions[uid]=(_revisions[uid]??0)+1;
    return _edit(() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_consent,enabled); await p.setBool(_dirty,true);
    if (!enabled) await p.remove(_outbox);
    unawaited(flush());
    });
  }
  Future<void> report({required String runId, required String phase, required String beforeMood,
    String afterMood = 'skip', List<String> categories = const []}) => _edit(() async {
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
  });
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
          await _post('/insights/consent',{'enabled':consent,'policyVersion':12});
          if(p.getBool(_consent)==consent) await p.setBool(_dirty,false);
        }
        if(!await enabled() || p.getBool(_dirty)==true) return;
        final snapshot=jsonDecode(p.getString(_outbox) ?? '{}') as Map<String,dynamic>;
        for (final entry in snapshot.entries) {
          if(!_current || !await enabled()) return;
          await _post('/insights/session',Map<String,dynamic>.from(entry.value as Map));
          await _edit(() async {
            final latest=jsonDecode(p.getString(_outbox) ?? '{}') as Map<String,dynamic>;
            if(jsonEncode(latest[entry.key])==jsonEncode(entry.value)) latest.remove(entry.key);
            await p.setString(_outbox,jsonEncode(latest));
          });
        }
      } catch (_) { /* Pending events remain local for the next startup/resume. */ }
    });
    _jobs[uid]=next;
    return next.whenComplete(() {if(identical(_jobs[uid],next))_jobs.remove(uid);});
  }
}
