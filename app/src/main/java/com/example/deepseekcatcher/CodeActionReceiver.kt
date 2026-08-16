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
            WorkspaceSession.addFile(targetFile.absolutePath.substringAfter("DeepSeekWorkspace/"))
            Toast.makeText(context, "Saved $filename", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) { e.printStackTrace() }
    }
}
