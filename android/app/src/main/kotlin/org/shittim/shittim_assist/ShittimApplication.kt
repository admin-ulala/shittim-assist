package org.shittim.shittim_assist

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** Keep the task isolate alive when the workbench Activity is detached. */
class ShittimApplication : Application() {
    lateinit var bridge: DeviceBridge
        private set
    val engine: FlutterEngine by lazy {
        FlutterEngine(this).also {
            bridge = DeviceBridge(this, it)
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
    }
    fun command(action: String) {
        // A restarted accessibility service must never restart a previous task.
        if (::bridge.isInitialized) bridge.command(action)
    }
}
