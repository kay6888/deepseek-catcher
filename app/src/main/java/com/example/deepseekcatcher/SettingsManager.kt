package com.example.deepseekcatcher

import android.content.Context
import android.content.SharedPreferences

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("DeepSeekPrefs", Context.MODE_PRIVATE)

    var isDarkMode: Boolean
        get() = prefs.getBoolean("dark_mode", true)
        set(value) = prefs.edit().putBoolean("dark_mode", value).apply()

    var autoCollect: Boolean
        get() = prefs.getBoolean("auto_collect", false)
        set(value) = prefs.edit().putBoolean("auto_collect", value).apply()
        
    var copyCollect: Boolean
        get() = prefs.getBoolean("copy_collect", true)
        set(value) = prefs.edit().putBoolean("copy_collect", value).apply()

    var notificationsEnabled: Boolean
        get() = prefs.getBoolean("notifications_enabled", true)
        set(value) = prefs.edit().putBoolean("notifications_enabled", value).apply()

    var floatingButtonEnabled: Boolean
        get() = prefs.getBoolean("floating_button_enabled", false)
        set(value) = prefs.edit().putBoolean("floating_button_enabled", value).apply()
}
