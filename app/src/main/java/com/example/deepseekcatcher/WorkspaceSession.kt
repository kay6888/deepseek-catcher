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
