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

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
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
                    triggerProjectNotification(text)
                } else if ((text.contains("fun ") && text.contains("val ")) || 
                           (text.contains("class ") && text.contains("{")) ||
                           (text.contains("const ") && text.contains("=")) ||
                           text.startsWith("import ")) {
                    
                    processedContent.add(textHash)
                    var filename = "snippet_${System.currentTimeMillis()}.txt"
                    val firstLine = text.lines().firstOrNull() ?: ""
                    val match = Regex("(?:file|name)[\\s:]*([a-zA-Z0-9_\\-\\.\\/]+)", RegexOption.IGNORE_CASE).find(firstLine)
                    if (match != null) filename = match.groupValues[1]

                    triggerCodeNotification(filename, text)
                }
            }
        }

        for (i in 0 until node.childCount) {
            scanNodes(node.getChild(i))
        }
    }

    private fun triggerCodeNotification(filename: String, code: String) {
        CodeCache.pendingSaves[filename] = code
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("code_alerts", "Code Alerts", NotificationManager.IMPORTANCE_HIGH))

        val intent = Intent(this, CodeActionReceiver::class.java).apply {
            action = "ACTION_COLLECT"
            putExtra("FILENAME", filename)
        }
        val pIntent = PendingIntent.getBroadcast(this, filename.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(this, "code_alerts")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("DeepSeek Code Detected")
            .setContentText("Save $filename?")
            .addAction(android.R.drawable.ic_menu_save, "Collect", pIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(filename.hashCode(), notification)
    }

    private fun triggerProjectNotification(treeContent: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("code_alerts", "Code Alerts", NotificationManager.IMPORTANCE_HIGH))

        val intent = Intent(this, CodeActionReceiver::class.java).apply {
            action = "ACTION_SCAFFOLD_PROJECT"
            putExtra("TREE_CONTENT", treeContent)
        }
        val pIntent = PendingIntent.getBroadcast(this, treeContent.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notification = NotificationCompat.Builder(this, "code_alerts")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Project Structure Detected")
            .setContentText("Scaffold this project directory?")
            .addAction(android.R.drawable.ic_menu_save, "Scaffold", pIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(treeContent.hashCode(), notification)
    }

    override fun onInterrupt() {}
}
