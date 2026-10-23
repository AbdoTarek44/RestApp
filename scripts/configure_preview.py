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
