#!/bin/bash

PKG_DIR="app/src/main/java/com/example/deepseekcatcher"

echo "Applying Bioluminescent UI Overhaul..."

cat << 'EOF' > "$PKG_DIR/MainActivity.kt"
package com.example.deepseekcatcher

import android.content.Intent
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
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
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Folder
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

// --- BIOLUMINESCENT COLOR PALETTE ---
val AbyssalBlack = Color(0xFF0A0E17)
val TrenchBlue = Color(0xFF151C2B)
val GlowingCyan = Color(0xFF00E5FF)
val CyanDim = Color(0xFF00838F)
val NeonCoral = Color(0xFFFF3366)
val SeafoamWhite = Color(0xFFE0F7FA)

val DarkSeaColors = darkColorScheme(
    primary = GlowingCyan,
    onPrimary = AbyssalBlack,
    secondary = NeonCoral,
    background = AbyssalBlack,
    surface = TrenchBlue,
    onSurface = SeafoamWhite,
    surfaceVariant = Color(0xFF1E293B),
    onSurfaceVariant = Color(0xFF94A3B8)
)

val LightSeaColors = lightColorScheme(
    primary = Color(0xFF005B94),
    onPrimary = Color.White,
    secondary = NeonCoral,
    background = Color(0xFFF0F4F8),
    surface = Color.White,
    onSurface = Color(0xFF0A192F),
    surfaceVariant = Color(0xFFE2E8F0),
    onSurfaceVariant = Color(0xFF475569)
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settingsManager = SettingsManager(this)
        setContent {
            var isDark by remember { mutableStateOf(settingsManager.isDarkMode) }
            MaterialTheme(
                colorScheme = if (isDark) DarkSeaColors else LightSeaColors,
                typography = Typography()
            ) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
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
                title = { 
                    Text(
                        text = when(currentScreen) {
                            Screen.FileManager -> if (currentDir == baseDir) "DeepSeek Collector" else currentDir.name
                            Screen.Editor -> currentFile?.name ?: "Terminal"
                            Screen.Settings -> "System Preferences"
                        },
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary
                    ) 
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.primary
                ),
                navigationIcon = {
                    if (currentScreen != Screen.FileManager || currentDir != baseDir) {
                        IconButton(onClick = {
                            if (currentScreen == Screen.Editor) currentScreen = Screen.FileManager
                            else if (currentScreen == Screen.Settings) currentScreen = Screen.FileManager
                            else if (currentDir.parentFile != null) currentDir = currentDir.parentFile!!
                        }) { Icon(Icons.Default.ArrowBack, "Back", tint = MaterialTheme.colorScheme.primary) }
                    }
                },
                actions = {
                    if (currentScreen == Screen.FileManager) {
                        IconButton(onClick = { currentScreen = Screen.Settings }) { 
                            Icon(Icons.Default.Settings, "Settings", tint = MaterialTheme.colorScheme.primary) 
                        }
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding).fillMaxSize()) {
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
    
    if (items.isEmpty()) {
        Column(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Rounded.Folder, contentDescription = null, modifier = Modifier.size(72.dp), tint = MaterialTheme.colorScheme.surfaceVariant)
            Spacer(modifier = Modifier.height(16.dp))
            Text("Awaiting Data...", color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Medium)
        }
    } else {
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items(items) { file ->
                Card(
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).clickable { 
                        if (file.isDirectory) onFolderClick(file) else onFileClick(file) 
                    },
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                ) {
                    Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.background),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = if (file.isDirectory) Icons.Rounded.Folder else Icons.Rounded.Description, 
                                contentDescription = null, 
                                tint = if (file.isDirectory) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary
                            )
                        }
                        Spacer(modifier = Modifier.width(16.dp))
                        Column {
                            Text(file.name, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                            Text(if (file.isDirectory) "Directory" else "Raw Code", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
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
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier.weight(1f).fillMaxWidth(),
            textStyle = androidx.compose.ui.text.TextStyle(
                fontFamily = FontFamily.Monospace, 
                color = MaterialTheme.colorScheme.primary
            ),
            colors = TextFieldDefaults.outlinedTextFieldColors(
                containerColor = Color(0xFF05070A), // Extra dark terminal background
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            shape = RoundedCornerShape(12.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(
            onClick = { file.writeText(text); onSave() }, 
            modifier = Modifier.fillMaxWidth().height(56.dp),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary)
        ) {
            Text("Deploy Save", fontWeight = FontWeight.Bold)
        }
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
            SettingsCard("Heads-up Displays", "Enable floating alerts for captured data.", notifs) { notifs = it; settings.notificationsEnabled = it }
            Spacer(modifier = Modifier.height(12.dp))
            SettingsCard("Abyssal Theme", "Engage Bioluminescent Dark Mode.", isDark) { isDark = it; settings.isDarkMode = it; onThemeChange(it) }
        }
    }
}

@Composable
fun SettingsCard(title: String, subtitle: String, isChecked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Switch(
                checked = isChecked, 
                onCheckedChange = onCheckedChange,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.onPrimary,
                    checkedTrackColor = MaterialTheme.colorScheme.primary,
                    uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    uncheckedTrackColor = MaterialTheme.colorScheme.background
                )
            )
        }
    }
}
EOF

echo "UI Override Complete!"
