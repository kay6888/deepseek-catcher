package com.example.deepseekcatcher

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

class DeepSeekCatcherService : AccessibilityService() {
    private val processedContent = mutableSetOf<Int>()
    private lateinit var settings: SettingsManager
    private var lastDetectedFilename = "snippet.txt"
    private var lastDetectedCode = ""

    private var windowManager: WindowManager? = null
    private var floatingOverlay: LinearLayout? = null
    private var isOverlayAdded = false
    private var isMenuExpanded = false

    private var currentPackage: String = ""
    private var dsPackageName: String? = null

    override fun onServiceConnected() {
        settings = SettingsManager(this)
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        findDeepSeekPackage()
    }

    private fun findDeepSeekPackage() {
        val installedPackages = packageManager.getInstalledPackages(0)
        val deepSeekApp = installedPackages.find { it.packageName.contains("deepseek", true) }
        dsPackageName = deepSeekApp?.packageName
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: ""
        if (pkg.isNotEmpty()) {
            currentPackage = pkg
            updateFloatingOverlayVisibility()
        }

        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED || event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val eventText = event.text.joinToString(" ").lowercase()
            val nodeText = event.source?.text?.toString()?.lowercase() ?: event.source?.contentDescription?.toString()?.lowercase() ?: ""
            
            if (eventText.contains("copied") || eventText.contains("copy") || nodeText.contains("copy")) {
                if (settings.copyCollect && lastDetectedCode.isNotEmpty()) {
                    triggerCollection(lastDetectedFilename, lastDetectedCode, isAuto = false, isCopy = true)
                }
            }
        }

        runDeepScan()
    }

    fun runDeepScan() {
        val rootNode = rootInActiveWindow ?: return
        val allTextNodes = mutableListOf<String>()
        extractAllText(rootNode, allTextNodes)

        for (text in allTextNodes) {
            val textHash = text.hashCode()
            if (!processedContent.contains(textHash) && (text.contains("├──") || text.contains("└──"))) {
                processedContent.add(textHash)
                handleCapture("project", "Project Structure", text)
            }
        }

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
                    
                    val firstLine = text.lines().firstOrNull() ?: ""
                    val match = Regex("(?:file|name|path)[\\s:]*([a-zA-Z0-9_\\-\\.\\/]+)", RegexOption.IGNORE_CASE).find(firstLine)
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
        val t = node.text?.toString()
        val c = node.contentDescription?.toString()
        val tt = node.tooltipText?.toString()
        
        if (!t.isNullOrBlank()) output.add(t)
        if (!c.isNullOrBlank() && c != t) output.add(c)
        if (!tt.isNullOrBlank() && tt != t && tt != c) output.add(tt)
        
        for (i in 0 until node.childCount) extractAllText(node.getChild(i), output)
    }

    private fun updateFloatingOverlayVisibility() {
        if (dsPackageName == null) findDeepSeekPackage()
        val isTargetApp = currentPackage.contains("deepseek", ignoreCase = true) || currentPackage == packageName

        if (settings.floatingButtonEnabled && isTargetApp) {
            showFloatingOverlay()
        } else {
            removeFloatingOverlay()
        }
    }

    private fun showFloatingOverlay() {
        if (isOverlayAdded) return

        try {
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = 30
                y = 350
            }

            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.END
            }

            val mainButton = TextView(this).apply {
                text = "🐳"
                textSize = 22f
                setPadding(28, 28, 28, 28)
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#00E5FF"))
                    cornerRadius = 60f
                }

                var initialX = 0; var initialY = 0
                var initialTouchX = 0f; var initialTouchY = 0f
                var isMove = false

                setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = params.x; initialY = params.y
                            initialTouchX = event.rawX; initialTouchY = event.rawY
                            isMove = false
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = (event.rawX - initialTouchX).toInt()
                            val dy = (event.rawY - initialTouchY).toInt()
                            if (Math.abs(dx) > 10 || Math.abs(dy) > 10) isMove = true
                            params.x = initialX - dx; params.y = initialY + dy
                            windowManager?.updateViewLayout(container, params)
                            true
                        }
                        MotionEvent.ACTION_UP -> {
                            if (!isMove) {
                                isMenuExpanded = !isMenuExpanded
                                toggleSubMenu(container)
                            }
                            true
                        }
                        else -> false
                    }
                }
            }

            container.addView(mainButton)
            floatingOverlay = container
            windowManager?.addView(container, params)
            isOverlayAdded = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun toggleSubMenu(container: LinearLayout) {
        if (container.childCount > 1) {
            container.removeViews(1, container.childCount - 1)
        }

        if (isMenuExpanded) {
            val swapBtn = createMenuOption("🔄 Swap") { performSwap() }
            val refreshBtn = createMenuOption("⚡ Refresh") { 
                runDeepScan()
                showToastNotification("Scanner", "Screen Re-scanned!")
            }
            val settingsBtn = createMenuOption("⚙️ Settings") { openSettings() }

            container.addView(swapBtn, 0)
            container.addView(refreshBtn, 0)
            container.addView(settingsBtn, 0)
        }
    }

    private fun createMenuOption(label: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(Color.WHITE)
            setPadding(20, 16, 20, 16)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#151C2B"))
                cornerRadius = 30f
                setStroke(2, Color.parseColor("#00E5FF"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, 8, 0, 8) }

            setOnClickListener {
                onClick()
                isMenuExpanded = false
                floatingOverlay?.let { toggleSubMenu(it) }
            }
        }
    }

    private fun removeFloatingOverlay() {
        if (isOverlayAdded && floatingOverlay != null) {
            try { windowManager?.removeView(floatingOverlay) } catch (e: Exception) { e.printStackTrace() }
            isOverlayAdded = false
            floatingOverlay = null
            isMenuExpanded = false
        }
    }

    private fun performSwap() {
        if (dsPackageName == null) findDeepSeekPackage()

        val isInCollector = currentPackage == packageName
        if (isInCollector) {
            dsPackageName?.let { pkg ->
                val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launchIntent)
                }
            }
        } else {
            val collectorIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(collectorIntent)
        }
    }

    private fun openSettings() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("NAVIGATE_TO", "SETTINGS")
        }
        startActivity(intent)
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
            .setContentTitle(if (action == "ACTION_COLLECT") "Code Detected" else "Project Structure Detected")
            .setContentText("Save $name?")
            .addAction(android.R.drawable.ic_menu_save, "Collect / Scaffold", pIntent)
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

    override fun onDestroy() {
        removeFloatingOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() {}
}
