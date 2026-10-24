package com.santiyeagi.app

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("santiye_updates", "İş ve teklif bildirimleri", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Teklif, anlaşma ve hesap bildirimleri"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
