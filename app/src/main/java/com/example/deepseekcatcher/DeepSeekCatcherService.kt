package com.example.deepseekcatcher

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat

class DeepSeekCatcherService : AccessibilityService() {
    private val processedContent = mutableSetOf<Int>()
    private lateinit var settings: SettingsManager
    private var lastDetectedFilename = ""

    override fun onServiceConnected() { settings = SettingsManager(this) }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // COPY-COLLECT LOGIC: Detect if the user clicked a "Copy" button
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val nodeText = event.source?.text?.toString()?.lowercase() ?: event.source?.contentDescription?.toString()?.lowercase() ?: ""
            if ((nodeText.contains("copy") || nodeText.contains("copied")) && settings.copyCollect) {
                if (lastDetectedFilename.isNotEmpty()) {
                    val intent = Intent(this, CodeActionReceiver::class.java).apply {
                        action = "ACTION_COLLECT"
                        putExtra("FILENAME", lastDetectedFilename)
                    }
                    sendBroadcast(intent)
                    if (settings.notificationsEnabled) {
                        showToastNotification(lastDetectedFilename, "Saved via Copy-Collect!")
                    }
                }
            }
        }

        val rootNode = rootInActiveWindow ?: return
        scanNodes(rootNode)
    }

    private fun scanNodes(node: AccessibilityNodeInfo?) {
        if (node == null) return
        if (node.text != null) {
            val text = node.text.toString()
            val textHash = text.hashCode()

            if (!processedContent.contains(textHash)) {
                if (text.contains("├──") || text.contains("└──")) {
                    processedContent.add(textHash)
                    handleCapture("project", "Scaffold", text)
                } else if ((text.contains("fun ") && text.contains("val ")) || (text.contains("class ") && text.contains("{")) || text.startsWith("import ") || (text.contains("const ") && text.contains("="))) {
                    processedContent.add(textHash)
                    var filename = "snippet_${System.currentTimeMillis()}.txt"
                    val match = Regex("(?:file|name)[\\s:]*([a-zA-Z0-9_\\-\\.\\/]+)", RegexOption.IGNORE_CASE).find(text.lines().firstOrNull() ?: "")
                    if (match != null) filename = match.groupValues[1]
                    
                    lastDetectedFilename = filename // Store for Copy-Collect feature
                    handleCapture("code", filename, text)
                }
            }
        }
        for (i in 0 until node.childCount) scanNodes(node.getChild(i))
    }

    private fun handleCapture(type: String, name: String, content: String) {
        val actionType = if (type == "project") "ACTION_SCAFFOLD_PROJECT" else "ACTION_COLLECT"
        val extraKey = if (type == "project") "TREE_CONTENT" else "FILENAME"
        if (type == "code") CodeCache.pendingSaves[name] = content

        if (settings.autoCollect) {
            val intent = Intent(this, CodeActionReceiver::class.java).apply {
                action = actionType
                putExtra(extraKey, name)
            }
            sendBroadcast(intent)
            if (settings.notificationsEnabled) showToastNotification(name, "Auto-Collected")
        } else if (settings.notificationsEnabled) {
            triggerInteractiveNotification(actionType, extraKey, name)
        }
    }

    private fun triggerInteractiveNotification(action: String, extraKey: String, name: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("deep_seek_alerts", "DeepSeek Alerts", NotificationManager.IMPORTANCE_HIGH))
        val intent = Intent(this, CodeActionReceiver::class.java).apply { this.action = action; putExtra(extraKey, name) }
        val pIntent = PendingIntent.getBroadcast(this, name.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notif = NotificationCompat.Builder(this, "deep_seek_alerts")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(if (action == "ACTION_COLLECT") "Code Detected" else "Project Detected")
            .setContentText("Save $name?")
            .addAction(android.R.drawable.ic_menu_save, "Collect", pIntent)
            .setAutoCancel(true).build()
        manager.notify(name.hashCode(), notif)
    }

    private fun showToastNotification(title: String, msg: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("deep_seek_silent", "Auto Alerts", NotificationManager.IMPORTANCE_LOW))
        val notif = NotificationCompat.Builder(this, "deep_seek_silent")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(msg).setAutoCancel(true).build()
        manager.notify(title.hashCode(), notif)
    }
    override fun onInterrupt() {}
}
