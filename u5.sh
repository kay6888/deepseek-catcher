#!/bin/bash

PKG_DIR="app/src/main/java/com/example/deepseekcatcher"
RES_XML="app/src/main/res/xml"

echo "Deploying Deep Scanner and Project Management features..."

# 1. Update Accessibility Config to catch "Copied" Toasts
cat << 'EOF' > "$RES_XML/accessibility_service_config.xml"
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowContentChanged|typeWindowStateChanged|typeViewClicked|typeNotificationStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagRetrieveInteractiveWindows|flagIncludeNotImportantViews"
    android:canRetrieveWindowContent="true"
    android:description="@string/accessibility_description"
    android:notificationTimeout="300" />
EOF

# 2. Re-engineer the Service (Deep Scanner, Trees First, Toast Intercepts)
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
    private var lastDetectedFilename = "snippet.txt"
    private var lastDetectedCode = ""

    override fun onServiceConnected() { settings = SettingsManager(this) }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // COPY-COLLECT: Detect "Copied" Toasts or "Copy" button clicks
        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED || event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val eventText = event.text.joinToString(" ").lowercase()
            val nodeText = event.source?.text?.toString()?.lowercase() ?: event.source?.contentDescription?.toString()?.lowercase() ?: ""
            
            if (eventText.contains("copied") || eventText.contains("copy") || nodeText.contains("copy")) {
                if (settings.copyCollect && lastDetectedCode.isNotEmpty()) {
                    triggerCollection(lastDetectedFilename, lastDetectedCode, isAuto = false, isCopy = true)
                }
            }
        }

        // DEEP SCAN: Only process window content changes
        val rootNode = rootInActiveWindow ?: return
        val allTextNodes = mutableListOf<String>()
        extractAllText(rootNode, allTextNodes)

        // PASS 1: Project Structures MUST be processed FIRST
        for (text in allTextNodes) {
            val textHash = text.hashCode()
            if (!processedContent.contains(textHash) && (text.contains("├──") || text.contains("└──"))) {
                processedContent.add(textHash)
                handleCapture("project", "Project Scaffold", text)
            }
        }

        // PASS 2: Code snippets
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

    private fun extractAllText(node: AccessibilityNodeInfo?, output: MutableList<String>) {
        if (node == null) return
        // Some apps hide text in content descriptions, we must check both
        val t = node.text?.toString()
        val c = node.contentDescription?.toString()
        
        if (!t.isNullOrBlank()) output.add(t)
        else if (!c.isNullOrBlank()) output.add(c)
        
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
            putExtra(extraKey, if (type == "project") content else name) // Pass actual tree content for scaffold
        }
        sendBroadcast(intent)
        
        if (settings.notificationsEnabled) {
            val source = if (isCopy) "via Copy-Collect" else "Auto-Collected"
            showToastNotification(name, source)
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

# 3. Completely revamp MainActivity (App Check, Create, Edit, Delete)
cat << 'EOF' > "$PKG_DIR/MainActivity.kt"
package com.example.deepseekcatcher

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.io.File

// BIOLUMINESCENT COLOR PALETTE
val AbyssalBlack = Color(0xFF0A0E17); val TrenchBlue = Color(0xFF151C2B); val GlowingCyan = Color(0xFF00E5FF)
val NeonCoral = Color(0xFFFF3366); val SeafoamWhite = Color(0xFFE0F7FA)

val DarkSeaColors = darkColorScheme(primary = GlowingCyan, onPrimary = AbyssalBlack, secondary = NeonCoral, background = AbyssalBlack, surface = TrenchBlue, onSurface = SeafoamWhite, surfaceVariant = Color(0xFF1E293B), onSurfaceVariant = Color(0xFF94A3B8))
val LightSeaColors = lightColorScheme(primary = Color(0xFF005B94), onPrimary = Color.White, secondary = NeonCoral, background = Color(0xFFF0F4F8), surface = Color.White, onSurface = Color(0xFF0A192F), surfaceVariant = Color(0xFFE2E8F0), onSurfaceVariant = Color(0xFF475569))

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settingsManager = SettingsManager(this)
        
        // Check if DeepSeek is actually installed
        val isDeepSeekInstalled = packageManager.getInstalledPackages(0).any { it.packageName.contains("deepseek", true) }

        setContent {
            var isDark by remember { mutableStateOf(settingsManager.isDarkMode) }
            MaterialTheme(colorScheme = if (isDark) DarkSeaColors else LightSeaColors) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    DeepSeekApp(settingsManager, isDeepSeekInstalled) { isDark = it }
                }
            }
        }
    }
}

enum class Screen { FileManager, Editor, Settings }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeepSeekApp(settings: SettingsManager, isDeepSeekInstalled: Boolean, onThemeChange: (Boolean) -> Unit) {
    var currentScreen by remember { mutableStateOf(Screen.FileManager) }
    var currentFile by remember { mutableStateOf<File?>(null) }
    
    val baseDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeepSeekWorkspace")
    if (!baseDir.exists()) baseDir.mkdirs()
    var currentDir by remember { mutableStateOf(baseDir) }

    // Dialog States
    var showCreateDialog by remember { mutableStateOf(false) }
    var fileToEdit by remember { mutableStateOf<File?>(null) }
    var fileToDelete by remember { mutableStateOf<File?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(when(currentScreen) { Screen.FileManager -> if (currentDir == baseDir) "DeepSeek Collector" else currentDir.name; Screen.Editor -> currentFile?.name ?: "Terminal"; Screen.Settings -> "System Preferences" }, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                navigationIcon = {
                    if (currentScreen != Screen.FileManager || currentDir != baseDir) {
                        IconButton(onClick = { if (currentScreen == Screen.Editor || currentScreen == Screen.Settings) currentScreen = Screen.FileManager else if (currentDir.parentFile != null) currentDir = currentDir.parentFile!! }) { Icon(Icons.Default.ArrowBack, "Back", tint = MaterialTheme.colorScheme.primary) }
                    }
                },
                actions = {
                    if (currentScreen == Screen.FileManager) {
                        IconButton(onClick = { currentScreen = Screen.Settings }) { Icon(Icons.Default.Settings, "Settings", tint = MaterialTheme.colorScheme.primary) }
                    }
                }
            )
        },
        floatingActionButton = {
            if (currentScreen == Screen.FileManager) {
                FloatingActionButton(onClick = { showCreateDialog = true }, containerColor = MaterialTheme.colorScheme.primary) { Icon(Icons.Default.Add, "Create Project", tint = MaterialTheme.colorScheme.onPrimary) }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
            when (currentScreen) {
                Screen.FileManager -> {
                    Column {
                        if (!isDeepSeekInstalled) {
                            Card(modifier = Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondary)) {
                                Text("⚠️ DeepSeek app not detected on this device. The collector monitors active windows, so you must have it open!", modifier = Modifier.padding(16.dp), color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }
                        FileManagerScreen(currentDir, onFolderClick = { currentDir = it }, onFileClick = { currentFile = it; currentScreen = Screen.Editor }, onEdit = { fileToEdit = it }, onDelete = { fileToDelete = it })
                    }
                }
                Screen.Editor -> currentFile?.let { EditorScreen(it) { currentScreen = Screen.FileManager } }
                Screen.Settings -> SettingsScreen(settings, onThemeChange)
            }
        }

        // CREATE DIALOG
        if (showCreateDialog) {
            var newName by remember { mutableStateOf("") }
            AlertDialog(onDismissRequest = { showCreateDialog = false }, title = { Text("Create New Project / Folder") }, text = { OutlinedTextField(value = newName, onValueChange = { newName = it }, singleLine = true) }, confirmButton = { Button(onClick = { File(currentDir, newName).mkdirs(); showCreateDialog = false }) { Text("Create") } }, dismissButton = { TextButton(onClick = { showCreateDialog = false }) { Text("Cancel") } })
        }

        // EDIT DIALOG
        if (fileToEdit != null) {
            var editName by remember { mutableStateOf(fileToEdit!!.name) }
            AlertDialog(onDismissRequest = { fileToEdit = null }, title = { Text("Rename") }, text = { OutlinedTextField(value = editName, onValueChange = { editName = it }, singleLine = true) }, confirmButton = { Button(onClick = { fileToEdit!!.renameTo(File(fileToEdit!!.parentFile, editName)); fileToEdit = null }) { Text("Save") } }, dismissButton = { TextButton(onClick = { fileToEdit = null }) { Text("Cancel") } })
        }

        // DELETE DIALOG
        if (fileToDelete != null) {
            AlertDialog(onDismissRequest = { fileToDelete = null }, title = { Text("Delete Project?") }, text = { Text("Are you sure you want to delete ${fileToDelete!!.name}? This cannot be undone.") }, confirmButton = { Button(onClick = { fileToDelete!!.deleteRecursively(); fileToDelete = null }, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)) { Text("Delete") } }, dismissButton = { TextButton(onClick = { fileToDelete = null }) { Text("Cancel") } })
        }
    }
}

@Composable
fun FileManagerScreen(dir: File, onFolderClick: (File) -> Unit, onFileClick: (File) -> Unit, onEdit: (File) -> Unit, onDelete: (File) -> Unit) {
    val items = dir.listFiles()?.sortedWith(compareBy({ !it.isDirectory }, { it.name })) ?: emptyList()
    if (items.isEmpty()) {
        Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.Folder, null, modifier = Modifier.size(72.dp), tint = MaterialTheme.colorScheme.surfaceVariant); Spacer(modifier = Modifier.height(16.dp)); Text("Awaiting Data...", color = MaterialTheme.colorScheme.onSurfaceVariant) }
    } else {
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(items) { file ->
                Card(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).clickable { if (file.isDirectory) onFolderClick(file) else onFileClick(file) }, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)) {
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.background), contentAlignment = Alignment.Center) { Icon(imageVector = if (file.isDirectory) Icons.Rounded.Folder else Icons.Rounded.Description, contentDescription = null, tint = if (file.isDirectory) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary) }
                        Spacer(modifier = Modifier.width(16.dp))
                        Column(modifier = Modifier.weight(1f)) { Text(file.name, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface); Text(if (file.isDirectory) "Directory" else "Raw Code", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        IconButton(onClick = { onEdit(file) }) { Icon(Icons.Default.Edit, "Edit", tint = MaterialTheme.colorScheme.primary) }
                        IconButton(onClick = { onDelete(file) }) { Icon(Icons.Default.Delete, "Delete", tint = MaterialTheme.colorScheme.secondary) }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(file: File, onSave: () -> Unit) {
    var text by remember { mutableStateOf(if (file.exists()) file.readText() else "") }
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(value = text, onValueChange = { text = it }, modifier = Modifier.weight(1f).fillMaxWidth(), textStyle = androidx.compose.ui.text.TextStyle(fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.primary), colors = TextFieldDefaults.outlinedTextFieldColors(containerColor = Color(0xFF05070A), focusedBorderColor = MaterialTheme.colorScheme.primary, unfocusedBorderColor = MaterialTheme.colorScheme.surfaceVariant), shape = RoundedCornerShape(12.dp))
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = { file.writeText(text); onSave() }, modifier = Modifier.fillMaxWidth().height(56.dp), shape = RoundedCornerShape(16.dp)) { Text("Deploy Save", fontWeight = FontWeight.Bold) }
    }
}

@Composable
fun SettingsScreen(settings: SettingsManager, onThemeChange: (Boolean) -> Unit) {
    var autoCollect by remember { mutableStateOf(settings.autoCollect) }
    var copyCollect by remember { mutableStateOf(settings.copyCollect) }
    var notifs by remember { mutableStateOf(settings.notificationsEnabled) }
    var isDark by remember { mutableStateOf(settings.isDarkMode) }

    LazyColumn(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        item {
            Text("Collection Protocol", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.secondary, modifier = Modifier.padding(vertical = 16.dp))
            SettingsCard("Auto-Collect", "Instantly intercept incoming code streams.", autoCollect) { autoCollect = it; settings.autoCollect = it }
            Spacer(modifier = Modifier.height(12.dp))
            SettingsCard("Copy-Collect", "Trigger capture via manual clipboard copy.", copyCollect) { copyCollect = it; settings.copyCollect = it }
            
            Divider(modifier = Modifier.padding(vertical = 24.dp), color = MaterialTheme.colorScheme.surfaceVariant)
            
            Text("System Preferences", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.secondary, modifier = Modifier.padding(bottom = 16.dp))
            SettingsCard("Heads-up Displays", if(notifs) "Notifications: ON" else "Notifications: OFF (Silent Mode)", notifs) { notifs = it; settings.notificationsEnabled = it }
            Spacer(modifier = Modifier.height(12.dp))
            SettingsCard("Abyssal Theme", "Engage Bioluminescent Dark Mode.", isDark) { isDark = it; settings.isDarkMode = it; onThemeChange(it) }
        }
    }
}

@Composable
fun SettingsCard(title: String, subtitle: String, isChecked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) { Text(title, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface); Text(subtitle, style = MaterialTheme.typography.bodySmall, color = if(isChecked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
            Switch(checked = isChecked, onCheckedChange = onCheckedChange, colors = SwitchDefaults.colors(checkedThumbColor = MaterialTheme.colorScheme.onPrimary, checkedTrackColor = MaterialTheme.colorScheme.primary))
        }
    }
}
EOF

echo "Upgrade Complete!"
