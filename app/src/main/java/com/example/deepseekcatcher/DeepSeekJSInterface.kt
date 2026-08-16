package com.example.deepseekcatcher

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.webkit.JavascriptInterface
import androidx.core.app.NotificationCompat

class DeepSeekJSInterface(private val context: Context) {
    @JavascriptInterface
    fun onCodeDetected(chatId: String, filename: String, code: String) {
        CodeCache.pendingSaves[filename] = code 
        triggerNotification(filename)
    }

    private fun triggerNotification(filename: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "deepseek_code_alerts"
        manager.createNotificationChannel(NotificationChannel(channelId, "Alerts", NotificationManager.IMPORTANCE_HIGH))

        val intent = Intent(context, CodeActionReceiver::class.java).apply {
            action = "ACTION_COLLECT"
            putExtra("FILENAME", filename)
        }
        val pIntent = PendingIntent.getBroadcast(context, filename.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Code Detected")
            .setContentText("Save $filename?")
            .addAction(android.R.drawable.ic_menu_save, "Collect", pIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(filename.hashCode(), notification)
    }
}
