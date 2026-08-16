package com.example.deepseekcatcher

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.List
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val savedFiles by WorkspaceSession.savedFiles.collectAsState()
                WorkspaceOverlay(savedFiles = savedFiles) { DeepSeekWebView(this) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceOverlay(savedFiles: List<SavedFile>, content: @Composable () -> Unit) {
    var showSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = { showSheet = true }) { Icon(Icons.Default.List, "Workspace") }
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) { content() }
        if (showSheet) {
            ModalBottomSheet(onDismissRequest = { showSheet = false }, sheetState = sheetState) {
                Column(modifier = Modifier.padding(16.dp).fillMaxWidth()) {
                    Text("Session Workspace", style = MaterialTheme.typography.titleLarge)
                    Spacer(modifier = Modifier.height(16.dp))
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
                    Spacer(modifier = Modifier.height(48.dp))
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun DeepSeekWebView(context: android.content.Context) {
    AndroidView(factory = {
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            addJavascriptInterface(DeepSeekJSInterface(context), "Android")
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    val js = """
                        const processedNodes = new WeakSet();
                        new MutationObserver(m => m.forEach(mu => mu.addedNodes.forEach(n => {
                            if (n.nodeType === 1) {
                                n.querySelectorAll('pre code').forEach(c => {
                                    if (!processedNodes.has(c)) {
                                        processedNodes.add(c);
                                        let f = "snippet_" + Date.now() + ".txt";
                                        let match = c.innerText.split('\n')[0].match(/(?:file|name)[\s:]*([a-zA-Z0-9_\-\.\/]+)/i);
                                        if (match) f = match[1];
                                        window.Android.onCodeDetected(window.location.pathname, f, c.innerText);
                                    }
                                });
                            }
                        }))).observe(document.body, { childList: true, subtree: true });
                    """.trimIndent()
                    view?.evaluateJavascript(js, null)
                }
            }
            loadUrl("https://chat.deepseek.com")
        }
    }, modifier = Modifier.fillMaxSize())
}
