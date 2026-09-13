package dev.fluttercommunity.workmanager

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

class SharedPreferenceHelper(
    private val context: Context,
    private val dispatcherHandleListener: DispatcherHandleListener,
) {
    // при смене сохранённого обработчика сообщаем плагину
    interface DispatcherHandleListener {
        fun onDispatcherHandleChanged(handle: Long)
    }

    companion object {
        private const val SHARED_PREFS_FILE_NAME = "flutter_workmanager_plugin"
        private const val CALLBACK_DISPATCHER_HANDLE_KEY =
            "dev.fluttercommunity.workmanager.CALLBACK_DISPATCHER_HANDLE_KEY"

        fun getCallbackHandle(context: Context): Long {
            val preferences = context.getSharedPreferences(SHARED_PREFS_FILE_NAME, Context.MODE_PRIVATE)
            return preferences.getLong(CALLBACK_DISPATCHER_HANDLE_KEY, -1L)
        }
    }

    private val preferences: SharedPreferences
        get() = context.getSharedPreferences(SHARED_PREFS_FILE_NAME, Context.MODE_PRIVATE)

    private val preferenceListener: (sharedPreferences: SharedPreferences, key: String?) -> Unit =
        { preferences, key ->
            if (key == CALLBACK_DISPATCHER_HANDLE_KEY) {
                dispatcherHandleListener.onDispatcherHandleChanged(
                    preferences.getLong(CALLBACK_DISPATCHER_HANDLE_KEY, -1L),
                )
            }
        }

    init {
        preferences.registerOnSharedPreferenceChangeListener(preferenceListener)

        val currentHandle = preferences.getLong(CALLBACK_DISPATCHER_HANDLE_KEY, -1L)
        if (currentHandle != -1L) {
            dispatcherHandleListener.onDispatcherHandleChanged(currentHandle)
        }
    }

    fun saveCallbackDispatcherHandleKey(callbackHandle: Long) {
        preferences.edit {
            putLong(CALLBACK_DISPATCHER_HANDLE_KEY, callbackHandle)
        }
    }
}
