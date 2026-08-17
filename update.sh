#!/bin/bash

# Define paths
PKG_DIR="app/src/main/java/com/example/deepseekcatcher"
RES_XML_DIR="app/src/main/res/xml"
RES_VAL_DIR="app/src/main/res/values"
WORKFLOW_DIR=".github/workflows"

echo "Creating necessary project directories..."
mkdir -p "$PKG_DIR"
mkdir -p "$RES_XML_DIR"
mkdir -p "$RES_VAL_DIR"
mkdir -p "$WORKFLOW_DIR"

# 1. GitHub Actions Pipeline (v4 + Gradle 8.2 + Java 17)
cat << 'EOF' > "$WORKFLOW_DIR/build.yml"
name: Build Android APK
on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.2'
      - name: Build Debug APK
        run: gradle assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

# 2. Gradle Properties
cat << 'EOF' > gradle.properties
android.useAndroidX=true
android.enableJetifier=true
EOF

# 3. App Build Gradle
cat << 'EOF' > app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.deepseekcatcher"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.deepseekcatcher"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.1"
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2023.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.0")
    implementation("androidx.core:core-ktx:1.10.0")
}
EOF

# 4. XML Resources
cat << 'EOF' > "$RES_VAL_DIR/strings.xml"
<resources>
    <string name="app_name">DeepSeek Workspace</string>
    <string name="accessibility_description">Monitors DeepSeek screen output for code snippets and project trees.</string>
</resources>
EOF

cat << 'EOF' > "$RES_XML_DIR/accessibility_service_config.xml"
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowContentChanged|typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagDefault|flagRetrieveInteractiveWindows"
    android:canRetrieveWindowContent="true"
    android:description="@string/accessibility_description"
    android:notificationTimeout="500" />
EOF

# 5. Android Manifest
cat << 'EOF' > app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />

    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".DeepSeekCatcherService"
            android:exported="false"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config" />
        </service>

        <receiver 
            android:name=".CodeActionReceiver" 
            android:exported="false">
            <intent-filter>
                <action android:name="ACTION_COLLECT" />
                <action android:name="ACTION_SCAFFOLD_PROJECT" />
            </intent-filter>
        </receiver>

    </application>
</manifest>
EOF

# 6. Kotlin Source Files

cat << 'EOF' > "$PKG_DIR/WorkspaceSession.kt"
package com.example.deepseekcatcher

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class SavedFile(val filename: String, val timestamp: Long)

object WorkspaceSession {
    private val _savedFiles = MutableStateFlow<List<SavedFile>>(emptyList())
    val savedFiles: StateFlow<List<SavedFile>> = _savedFiles.asStateFlow()

    fun addFile(filename: String) {
        val currentList = _savedFiles.value.toMutableList()
        currentList.add(0, SavedFile(filename, System.currentTimeMillis())) 
        _savedFiles.value = currentList
    }
}
EOF

cat << 'EOF' > "$PKG_DIR/AsciiTreeParser.kt"
package com.example.deepseekcatcher

data class ProjectNode(val relativePath: String, val isDirectory: Boolean)

object AsciiTreeParser {
    fun parse(asciiTreeText: String): List<ProjectNode> {
        val lines = asciiTreeText.lines().filter { it.isNotBlank() }
        val nodes = mutableListOf<ProjectNode>()
        val pathStack = mutableListOf<Pair<Int, String>>()

        for (line in lines) {
            val nameStartIndex = line.indexOfFirst { it.isLetterOrDigit() || it == '.' || it == '_' }
            if (nameStartIndex == -1) continue

            val rawName = line.substring(nameStartIndex).trim()
            val isDir = rawName.endsWith("/") || (!rawName.contains(".") && !rawName.startsWith("."))
            val cleanName = rawName.removeSuffix("/")
            val depth = nameStartIndex / 4

            while (pathStack.isNotEmpty() && pathStack.last().first >= depth) {
                pathStack.removeAt(pathStack.size - 1)
            }
            pathStack.add(depth to cleanName)
            nodes.add(ProjectNode(relativePath = pathStack.joinToString("/") { it.second }, isDirectory = isDir))
        }
        return nodes
    }
}
EOF

cat << 'EOF' > "$PKG_DIR/ProjectScaffolder.kt"
package com.example.deepseekcatcher

import android.content.Context
import android.os.Environment
import android.widget.Toast
import java.io.File

object ProjectScaffolder {
    fun buildProjectStructure(context: Context, asciiTreeText: String) {
        try {
            val nodes = AsciiTreeParser.parse(asciiTreeText)
            if (nodes.isEmpty()) return

            val workspaceDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeepSeekWorkspace")
            var createdDirsCount = 0
            var createdFilesCount = 0

            for (node in nodes) {
                val targetFile = File(workspaceDir, node.relativePath)
                if (node.isDirectory) {
                    if (targetFile.mkdirs() || targetFile.exists()) createdDirsCount++
                } else {
                    targetFile.parentFile?.mkdirs()
                    val preSavedFlatFile = File(workspaceDir, targetFile.name)
                    
                    if (preSavedFlatFile.exists() && preSavedFlatFile.isFile && preSavedFlatFile.absolutePath != targetFile.absolutePath) {
                        preSavedFlatFile.copyTo(targetFile, overwrite = true)
                        preSavedFlatFile.delete()
                        createdFilesCount++
                    } else if (targetFile.createNewFile() || targetFile.exists()) {
                        createdFilesCount++
                    }
                }
            }
            val rootName = nodes.firstOrNull()?.relativePath?.substringBefore("/") ?: "Project"
            WorkspaceSession.addFile("📁 Scaffolded $rootName")
            Toast.makeText(context, "Scaffolded $rootName", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) { e.printStackTrace() }
    }
}
EOF

cat << 'EOF' > "$PKG_DIR/CodeActionReceiver.kt"
package com.example.deepseekcatcher

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.widget.Toast
import java.io.File
import java.io.FileOutputStream

object CodeCache {
    val pendingSaves = mutableMapOf<String, String>()
}

class CodeActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (action == "ACTION_COLLECT") {
            val filename = intent.getStringExtra("FILENAME") ?: return
            val codeContent = CodeCache.pendingSaves[filename] ?: return
            saveToDownloads(context, filename, codeContent)
            CodeCache.pendingSaves.remove(filename)
            notificationManager.cancel(filename.hashCode())
        } else if (action == "ACTION_SCAFFOLD_PROJECT") {
            val treeContent = intent.getStringExtra("TREE_CONTENT") ?: return
            ProjectScaffolder.buildProjectStructure(context, treeContent)
            notificationManager.cancel(treeContent.hashCode())
        }
    }

    private fun saveToDownloads(context: Context, filename: String, content: String) {
        try {
            val workspaceDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "DeepSeekWorkspace")
            if (!workspaceDir.exists()) workspaceDir.mkdirs()

            val existingNestedFile = workspaceDir.walkTopDown().find { it.isFile && it.name.equals(filename, ignoreCase = true) }
            val targetFile = existingNestedFile ?: File(workspaceDir, filename)

            FileOutputStream(targetFile).use { it.write(content.toByteArray()) }
            val path = targetFile.absolutePath.substringAfter("DeepSeekWorkspace/")
            WorkspaceSession.addFile("📄 $path")
            Toast.makeText(context, "Saved $filename", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) { e.printStackTrace() }
    }
}
EOF

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
EOF

cat << 'EOF' > "$PKG_DIR/MainActivity.kt"
package com.example.deepseekcatcher

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val savedFiles by WorkspaceSession.savedFiles.collectAsState()
                
                Surface(modifier = Modifier.fillMaxSize()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("DeepSeek Workspace Monitor", style = MaterialTheme.typography.headlineMedium)
                        Spacer(modifier = Modifier.height(8.dp))
                        
                        Button(
                            onClick = { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("1. Enable Background Service")
                        }
                        
                        Spacer(modifier = Modifier.height(24.dp))
                        Text("Collected Workspace Files:", style = MaterialTheme.typography.titleMedium)
                        Spacer(modifier = Modifier.height(8.dp))

                        if (savedFiles.isEmpty()) {
                            Text("No files captured yet. Enable the service, then use the official DeepSeek app!", style = MaterialTheme.typography.bodyMedium)
                        } else {
                            LazyColumn {
                                items(savedFiles) { file ->
                                    val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(file.timestamp))
                                    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                                        Column(modifier = Modifier.padding(12.dp)) {
                                            Text(file.filename, color = MaterialTheme.colorScheme.primary)
                                            Text("Saved at $time", style = MaterialTheme.typography.bodySmall)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
EOF

echo "All files generated successfully!"
