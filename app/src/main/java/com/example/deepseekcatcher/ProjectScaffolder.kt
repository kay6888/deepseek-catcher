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
