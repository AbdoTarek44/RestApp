from pathlib import Path

manifest=Path('android/app/src/main/AndroidManifest.xml')
s=manifest.read_text(encoding='utf-8')
s=s.replace('<application', '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <application',1)
s=s.replace('<activity', '''<meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="maalish_updates" />
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat_maalish" />
        <activity''',1)
manifest.write_text(s,encoding='utf-8')
icon=Path('android/app/src/main/res/drawable/ic_stat_maalish.xml')
icon.parent.mkdir(parents=True,exist_ok=True)
icon.write_text('''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
<path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" android:pathData="M12,2a10,10 0,1 0,0 20a10,10 0,1 0,0 -20M8,7a1.5,1.5 0,1 0,0 3a1.5,1.5 0,1 0,0 -3M16,7a1.5,1.5 0,1 0,0 3a1.5,1.5 0,1 0,0 -3M6,13Q12,21 18,13L16,13Q12,18 8,13Z"/>
</vector>''',encoding='utf-8')
activity=Path('android/app/src/main/kotlin/com/maalish/app/maalish_app/MainActivity.kt')
activity.parent.mkdir(parents=True,exist_ok=True)
activity.write_text('''package com.maalish.app.maalish_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private fun notificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel("maalish_updates", "إشعارات معلش", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "رسائل عامة وتحديثات معلش"
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            manager.createNotificationChannel(channel)
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maalish/notifications")
            .setMethodCallHandler { call, result ->
                when(call.method) {
                    "channel" -> { notificationChannel(); result.success(null) }
                    "privacy" -> { startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://maalish-ai.maalish-abdotarek44.workers.dev/privacy"))); result.success(null) }
                "settings" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        } else {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + packageName)))
                        }
                        result.success(null)
                    }
                    "show" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                            result.success(null)
                        } else {
                            val title = (call.argument<String>("title") ?: "معلش").take(70)
                            val body = (call.argument<String>("body") ?: "").take(180)
                            val id = (call.argument<String>("id") ?: "maalish").hashCode()
                            val intent = packageManager.getLaunchIntentForPackage(packageName)!!
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            val pending = PendingIntent.getActivity(this, id, intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "maalish_updates") else Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
                            val notification = builder
                                .setSmallIcon(R.drawable.ic_stat_maalish)
                                .setContentTitle(title).setContentText(body)
                                .setStyle(Notification.BigTextStyle().bigText(body))
                                .setVisibility(Notification.VISIBILITY_PRIVATE)
                                .setContentIntent(pending).setAutoCancel(true).build()
                            getSystemService(NotificationManager::class.java).notify(id, notification)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
''',encoding='utf-8')
