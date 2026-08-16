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
