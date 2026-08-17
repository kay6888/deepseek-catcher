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
