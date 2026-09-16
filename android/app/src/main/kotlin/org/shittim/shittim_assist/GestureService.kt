package org.shittim.shittim_assist

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.content.res.Configuration
import android.view.accessibility.AccessibilityWindowInfo
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import java.util.concurrent.atomic.AtomicBoolean

class GestureService : AccessibilityService() {
    companion object { @Volatile var instance: GestureService? = null; private set }
    val overlay by lazy { FloatingControls(this) }
    val foregroundPackage: String
        get() {
            // Overlay focus/events are not evidence that the game is foreground.
            // Query the focused application window each time; unknown => fail closed.
            if (getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked) return ""
            val window = windows.firstOrNull { it.isFocused && it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                ?: return ""
            val node = window.root ?: return ""
            return try { node.packageName?.toString() ?: "" } finally {
                @Suppress("DEPRECATION")
                node.recycle()
            }
        }
    private val busy = AtomicBoolean(false)
    private val handler = Handler(Looper.getMainLooper())
    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { (application as ShittimApplication).command("cancel") }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        handler.post { overlay.clamp() }
    }
    override fun onDestroy() {
        (application as ShittimApplication).command("cancel")
        overlay.close(); instance = null; super.onDestroy()
    }
    fun goBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)

    fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, duration: Long, callback: (Boolean) -> Unit) {
        val bounds = getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
        if (!listOf(x1, y1, x2, y2).all { it.isFinite() } ||
            x1 < 0 || x2 < 0 || y1 < 0 || y2 < 0 ||
            x1 >= bounds.width() || x2 >= bounds.width() ||
            y1 >= bounds.height() || y2 >= bounds.height() || !busy.compareAndSet(false, true)) {
            callback(false); return
        }
        val done = AtomicBoolean(false)
        fun finish(ok: Boolean) { if (done.compareAndSet(false, true)) { busy.set(false); callback(ok) } }
        val timeout = Runnable { finish(false) }
        handler.postDelayed(timeout, duration.coerceIn(1, 5000) + 2000)
        val path = Path().apply { moveTo(x1, y1); if (x1 != x2 || y1 != y2) lineTo(x2, y2) }
        val gesture = GestureDescription.Builder().addStroke(
            GestureDescription.StrokeDescription(path, 0, duration.coerceIn(1, 5000))).build()
        val sent = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                handler.removeCallbacks(timeout); finish(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                handler.removeCallbacks(timeout); finish(false)
            }
        }, handler)
        if (!sent) { handler.removeCallbacks(timeout); finish(false) }
    }
}
