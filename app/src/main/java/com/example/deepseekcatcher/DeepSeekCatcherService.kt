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
    private var lastDetectedFilename = "snippet.txt"
    private var lastDetectedCode = ""

    override fun onServiceConnected() { settings = SettingsManager(this) }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED || event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val eventText = event.text.joinToString(" ").lowercase()
            val nodeText = event.source?.text?.toString()?.lowercase() ?: event.source?.contentDescription?.toString()?.lowercase() ?: ""
            
            if (eventText.contains("copied") || eventText.contains("copy") || nodeText.contains("copy")) {
                if (settings.copyCollect && lastDetectedCode.isNotEmpty()) {
                    triggerCollection(lastDetectedFilename, lastDetectedCode, isAuto = false, isCopy = true)
                }
            }
        }

        val rootNode = rootInActiveWindow ?: return
        val allTextNodes = mutableListOf<String>()
        extractAllText(rootNode, allTextNodes)

        // Pass 1: Project Trees
        for (text in allTextNodes) {
            val textHash = text.hashCode()
            if (!processedContent.contains(textHash) && (text.contains("├──") || text.contains("└──"))) {
                processedContent.add(textHash)
                handleCapture("project", "Project Scaffold", text)
            }
        }

        // Pass 2: Code blocks
        for (text in allTextNodes) {
            val textHash = text.hashCode()
            if (!processedContent.contains(textHash)) {
                if ((text.contains("fun ") && text.contains("{")) || 
                    (text.contains("class ") && text.contains("{")) || 
                    text.startsWith("import ") || 
                    text.contains("```") ||
                    (text.contains("const ") && text.contains("="))) {
                    
                    processedContent.add(textHash)
                    var filename = "snippet_${System.currentTimeMillis()}.txt"
                    val match = Regex("(?:file|name)[\\s:]*([a-zA-Z0-9_\\-\\.\\/]+)", RegexOption.IGNORE_CASE).find(text.lines().firstOrNull() ?: "")
                    if (match != null) filename = match.groupValues[1]
                    
                    lastDetectedFilename = filename
                    lastDetectedCode = text
                    handleCapture("code", filename, text)
                }
            }
        }
    }

    // ENHANCED: Digs into text, contentDescription, hintText, and tooltipText
    private fun extractAllText(node: AccessibilityNodeInfo?, output: MutableList<String>) {
        if (node == null) return
        
        val t = node.text?.toString()
        val c = node.contentDescription?.toString()
        val tt = node.tooltipText?.toString()
        
        if (!t.isNullOrBlank()) output.add(t)
        if (!c.isNullOrBlank() && c != t) output.add(c)
        if (!tt.isNullOrBlank() && tt != t && tt != c) output.add(tt)
        
        for (i in 0 until node.childCount) extractAllText(node.getChild(i), output)
    }

    private fun handleCapture(type: String, name: String, content: String) {
        if (type == "code") CodeCache.pendingSaves[name] = content
        
        if (settings.autoCollect) {
            triggerCollection(name, content, isAuto = true, isCopy = false, type = type)
        } else if (settings.notificationsEnabled) {
            triggerInteractiveNotification(if (type == "project") "ACTION_SCAFFOLD_PROJECT" else "ACTION_COLLECT", 
                if (type == "project") "TREE_CONTENT" else "FILENAME", name)
        }
    }

    private fun triggerCollection(name: String, content: String, isAuto: Boolean, isCopy: Boolean, type: String = "code") {
        val actionType = if (type == "project") "ACTION_SCAFFOLD_PROJECT" else "ACTION_COLLECT"
        val extraKey = if (type == "project") "TREE_CONTENT" else "FILENAME"
        
        val intent = Intent(this, CodeActionReceiver::class.java).apply {
            action = actionType
            putExtra(extraKey, if (type == "project") content else name)
        }
        sendBroadcast(intent)
        
        if (settings.notificationsEnabled) {
            showToastNotification(name, if (isCopy) "via Copy-Collect" else "Auto-Collected")
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
