from pathlib import Path
manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text(encoding='utf-8')
marker='<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if 'android.permission.RECORD_AUDIO' not in s:
 s=s.replace(marker,marker+'\n    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <uses-permission android:name="android.permission.INTERNET" />')
s=s.replace('android:label="maalish_app"','android:label="معلش تجربة"')
manifest.write_text(s,encoding='utf-8')
gradle=Path('android/app/build.gradle.kts')
g=gradle.read_text(encoding='utf-8').replace('minSdk = flutter.minSdkVersion','minSdk = 24')
g=g.replace('applicationId = "com.maalish.app.maalish_app"','applicationId = "com.maalish.app.maalish_app.preview"')
assert 'applicationId = "com.maalish.app.maalish_app.preview"' in g
signing='''    signingConfigs.getByName("debug") {
        storeFile = file(System.getenv("MAALISH_SIGNING_STORE"))
        storePassword = "android"
        keyAlias = "androiddebugkey"
        keyPassword = "android"
    }

'''
g=g.replace('    buildTypes {',signing+'    buildTypes {')
assert 'MAALISH_SIGNING_STORE' in g
gradle.write_text(g,encoding='utf-8')

# Crashlytics config is public app metadata; collection starts disabled.
import shutil
shutil.copyfile('../config/google-services.preview.json','android/app/google-services.json')
settings=Path('android/settings.gradle.kts')
t=settings.read_text(encoding='utf-8')
t=t.replace('id("dev.flutter.flutter-plugin-loader") version "1.0.0"', 'id("dev.flutter.flutter-plugin-loader") version "1.0.0"\n    id("com.google.gms.google-services") version "4.5.0" apply false\n    id("com.google.firebase.crashlytics") version "3.0.8" apply false')
settings.write_text(t,encoding='utf-8')
g=gradle.read_text(encoding='utf-8').replace('plugins {','plugins {\n    id("com.google.gms.google-services")\n    id("com.google.firebase.crashlytics")',1)
gradle.write_text(g,encoding='utf-8')
m=manifest.read_text(encoding='utf-8').replace('<activity', '<meta-data android:name="firebase_crashlytics_collection_enabled" android:value="false" />\n        <activity',1)
manifest.write_text(m,encoding='utf-8')
