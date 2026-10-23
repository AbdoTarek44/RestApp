import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'ai_service.dart';

class NotificationService {
  static const _native=MethodChannel('maalish/notifications');
  static bool _initialized=false;
  static int _generation=0;
  static String? _owner;
  static Future<void> _queue=Future<void>.value();
  static String _key(String uid)=>'$uid:push_enabled_v11';
  static String? get _uid=>AuthService().currentUser?.uid;
  static Future<void> initialize() async {
    if(_initialized || !AuthService.ready)return;
    _initialized=true;
    _owner=(await SharedPreferences.getInstance()).getString('push_registration_owner_v11');
    try{await _native.invokeMethod<void>('channel');}catch(_){}
    FirebaseMessaging.onMessage.listen((message) async {
      if(!await enabled())return;
      final notification=message.notification;if(notification==null)return;
      try{await _native.invokeMethod<void>('show',{'title':notification.title ?? 'معلش',
        'body':notification.body ?? '', 'id':message.data['campaignId'] ?? message.messageId ?? 'maalish'});}catch(_){}
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((_)=>refresh());
    AuthService().authStateChanges.listen((_)=>refresh());
    unawaited(refresh());
  }
  static Future<bool> enabled() async {
    final uid=_uid;if(uid==null)return false;
    return (await SharedPreferences.getInstance()).getBool(_key(uid)) ?? false;
  }
  static Future<void> _register(String uid,String registration,bool value) async {
    if(_uid!=uid)throw StateError('Account changed');
    final token=await AuthService().idToken().timeout(const Duration(seconds:6));
    if(_uid!=uid)throw StateError('Account changed');
    final client=http.Client();
    try{
      final result=await client.post(Uri.parse(AiService.buildApiUrl).replace(path:'/push/register'),
        headers:{'Content-Type':'application/json','Authorization':'Bearer $token'},
        body:jsonEncode({'registration':registration,'enabled':value})).timeout(const Duration(seconds:10));
      if(result.statusCode!=200)throw StateError('تسجيل الإشعارات لسه ما اكتملش. جرّب تاني مع اتصال بالإنترنت.');
    }finally{client.close();}
  }
  static Future<void> setEnabled(bool value) async {
    final uid=_uid;if(uid==null)throw StateError('سجّل الدخول الأول.');
    if(value){
      final permission=await FirebaseMessaging.instance.requestPermission();
      if(permission.authorizationStatus!=AuthorizationStatus.authorized && permission.authorizationStatus!=AuthorizationStatus.provisional)
        throw StateError('اسمح بالإشعارات من إعدادات الجهاز عشان تقدر تستقبلها.');
    }
    await (await SharedPreferences.getInstance()).setBool(_key(uid),value);
    if(value){await FirebaseMessaging.instance.setAutoInitEnabled(true);await _enable(uid);}
    else {await detach();}
  }
  static Future<void> _enable(String uid) async {
    final generation=_generation;
    if(_uid!=uid || !await enabled())return;
    final token=await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds:10));
    if(token==null)throw StateError('تعذّر تسجيل الجهاز للإشعارات.');
    if(_uid!=uid || generation!=_generation || !await enabled())return;
    await _register(uid,token,true);
    if(_uid!=uid || generation!=_generation || !await enabled()) {
      if(_uid==uid) {try{await _register(uid,token,false);}catch(_){}}
      return;
    }
    _owner=uid;
    await (await SharedPreferences.getInstance()).setString('push_registration_v11',token);
    await (await SharedPreferences.getInstance()).setString('push_registration_owner_v11',uid);
  }
  static Future<void> detach() async {
    _generation++;
    final p=await SharedPreferences.getInstance();
    final token=p.getString('push_registration_v11');final uid=_uid;
    try{if(token!=null&&uid!=null)await _register(uid,token,false);}catch(_){}
    await FirebaseMessaging.instance.deleteToken();
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await p.remove('push_registration_v11');await p.remove('push_registration_owner_v11');_owner=null;
  }
  static Future<void> refresh(){
    _queue=_queue.catchError((_){}).then((_) async {
      try{
        final uid=_uid;
        if(_owner!=null && _owner!=uid){await FirebaseMessaging.instance.deleteToken();await FirebaseMessaging.instance.setAutoInitEnabled(false);_owner=null;}
        if(uid==null || !await enabled())return;
        final settings=await FirebaseMessaging.instance.getNotificationSettings();
        if(settings.authorizationStatus!=AuthorizationStatus.authorized&&settings.authorizationStatus!=AuthorizationStatus.provisional){await detach();return;}
        await FirebaseMessaging.instance.setAutoInitEnabled(true);await _enable(uid);
      }catch(_) { /* Registration retries on foreground/resume; never blocks chat. */ }
    });
    return _queue;
  }
  static Future<void> openSettings()=>_native.invokeMethod<void>('settings');
}
