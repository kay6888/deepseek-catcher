#!/bin/bash

PKG_DIR="app/src/main/java/com/example/deepseekcatcher"
RES_XML_DIR="app/src/main/res/xml"

echo "Adding Copy-Collect feature..."

# 1. Update Accessibility Config to allow intercepting Clicks
cat << 'EOF' > "$RES_XML_DIR/accessibility_service_config.xml"
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowContentChanged|typeWindowStateChanged|typeViewClicked"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagRetrieveInteractiveWindows"
    android:canRetrieveWindowContent="true"
    android:description="@string/accessibility_description"
    android:notificationTimeout="500" />
EOF

# 2. Update Settings Manager to include Copy-Collect
cat << 'EOF' > "$PKG_DIR/SettingsManager.kt"
package com.example.deepseekcatcher

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("DeepSeekPrefs", Context.MODE_PRIVATE)

    var isDarkMode: Boolean
        get() = prefs.getBoolean("dark_mode", true)
        set(value) = prefs.edit().putBoolean("dark_mode", value).apply()

    var autoCollect: Boolean
        get() = prefs.getBoolean("auto_collect", false)
        set(value) = prefs.edit().putBoolean("auto_collect", value).apply()
        
    var copyCollect: Boolean
        get() = prefs.getBoolean("copy_collect", true)
        set(value) = prefs.edit().putBoolean("copy_collect", value).apply()

    var notificationsEnabled: Boolean
        get() = prefs.getBoolean("notifications_enabled", true)
        set(value) = prefs.edit().putBoolean("notifications_enabled", value).apply()
}
EOF

# 3. Update the Background Service to detect "Copy" clicks
cat << 'EOF' > "$PKG_DIR/DeepSeekCatcherService.kt"
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
EOF

# 4. Update the UI to show DeepSeek Collector and the new setting
cat << 'EOF' > "$PKG_DIR/MainActivity.kt"
package com.example.deepseekcatcher

import android.content.Intent
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settingsManager = SettingsManager(this)
        setContent {
            var isDark by remember { mutableStateOf(settingsManager.isDarkMode) }
            MaterialTheme(colorScheme = if (isDark) darkColorScheme() else lightColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    DeepSeekApp(settingsManager) { isDark = it }
                }
            }
        }
    }
}

enum class Screen { FileManager, Editor, Settings }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeepSeekApp(settings: SettingsManager, onThemeChange: (Boolean) -> Unit) {
    var currentScreen by remember { mutableStateOf(Screen.FileManager) }
    var currentFile by remember { mutableStateOf<File?>(null) }
    
    val baseDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeepSeekWorkspace")
    if (!baseDir.exists()) baseDir.mkdirs()
    var currentDir by remember { mutableStateOf(baseDir) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(when(currentScreen) {
                    Screen.FileManager -> if (currentDir == baseDir) "DeepSeek Collector" else currentDir.name
                    Screen.Editor -> currentFile?.name ?: "Editor"
                    Screen.Settings -> "Settings"
                }) },
                navigationIcon = {
                    if (currentScreen != Screen.FileManager || currentDir != baseDir) {
                        IconButton(onClick = {
                            if (currentScreen == Screen.Editor) currentScreen = Screen.FileManager
                            else if (currentScreen == Screen.Settings) currentScreen = Screen.FileManager
                            else if (currentDir.parentFile != null) currentDir = currentDir.parentFile!!
                        }) { Icon(Icons.Default.ArrowBack, "Back") }
                    }
                },
                actions = {
                    if (currentScreen == Screen.FileManager) {
                        IconButton(onClick = { currentScreen = Screen.Settings }) { Icon(Icons.Default.Settings, "Settings") }
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when (currentScreen) {
                Screen.FileManager -> FileManagerScreen(currentDir, 
                    onFolderClick = { currentDir = it },
                    onFileClick = { currentFile = it; currentScreen = Screen.Editor })
                Screen.Editor -> currentFile?.let { EditorScreen(it) { currentScreen = Screen.FileManager } }
                Screen.Settings -> SettingsScreen(settings, onThemeChange)
            }
        }
    }
}

@Composable
fun FileManagerScreen(dir: File, onFolderClick: (File) -> Unit, onFileClick: (File) -> Unit) {
    val items = dir.listFiles()?.sortedWith(compareBy({ !it.isDirectory }, { it.name })) ?: emptyList()
    Column {
        if (items.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No code collected here yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn {
                items(items) { file ->
                    ListItem(
                        headlineContent = { Text(file.name) },
                        leadingContent = { Icon(if (file.isDirectory) Icons.Default.Folder else Icons.Default.Description, null) },
                        modifier = Modifier.clickable { if (file.isDirectory) onFolderClick(file) else onFileClick(file) }
                    )
                    Divider()
                }
            }
        }
    }
}

@Composable
fun EditorScreen(file: File, onSave: () -> Unit) {
    var text by remember { mutableStateOf(if (file.exists()) file.readText() else "") }
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.weight(1f).fillMaxWidth(),
            textStyle = androidx.compose.ui.text.TextStyle(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = { file.writeText(text); onSave() }, modifier = Modifier.fillMaxWidth()) {
            Text("Save File")
        }
    }
}

@Composable
fun SettingsScreen(settings: SettingsManager, onThemeChange: (Boolean) -> Unit) {
    var autoCollect by remember { mutableStateOf(settings.autoCollect) }
    var copyCollect by remember { mutableStateOf(settings.copyCollect) }
    var notifs by remember { mutableStateOf(settings.notificationsEnabled) }
    var isDark by remember { mutableStateOf(settings.isDarkMode) }

    Column(modifier = Modifier.padding(16.dp)) {
        Text("Collection Modes", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        Spacer(modifier = Modifier.height(16.dp))

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Auto-Collect", modifier = Modifier.weight(1f))
            Switch(checked = autoCollect, onCheckedChange = { autoCollect = it; settings.autoCollect = it })
        }
        Text("Automatically saves files the moment DeepSeek finishes typing.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        
        Spacer(modifier = Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Copy-Collect", modifier = Modifier.weight(1f))
            Switch(checked = copyCollect, onCheckedChange = { copyCollect = it; settings.copyCollect = it })
        }
        Text("Saves a file automatically when you manually tap the 'Copy' button in DeepSeek.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        
        Divider(modifier = Modifier.padding(vertical = 16.dp))
        Text("App Preferences", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        Spacer(modifier = Modifier.height(16.dp))

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Show Notifications", modifier = Modifier.weight(1f))
            Switch(checked = notifs, onCheckedChange = { notifs = it; settings.notificationsEnabled = it })
        }
        
        Spacer(modifier = Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Dark Mode", modifier = Modifier.weight(1f))
            Switch(checked = isDark, onCheckedChange = { isDark = it; settings.isDarkMode = it; onThemeChange(it) })
        }
    }
}
EOF

echo "Done!"
