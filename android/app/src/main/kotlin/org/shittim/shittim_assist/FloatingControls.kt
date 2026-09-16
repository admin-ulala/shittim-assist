package org.shittim.shittim_assist

import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/** Non-focusable accessibility overlay: tapping controls never opens the Activity. */
class FloatingControls(private val service: GestureService) {
    private val wm = service.getSystemService(WindowManager::class.java)
    private val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.LEFT; x = dp(12); y = dp(80) }
    private var root: LinearLayout? = null
    private var panel: LinearLayout? = null
    private var status: TextView? = null
    private var start: Button? = null
    private var pause: Button? = null
    private var stop: Button? = null
    private var state = "idle"
    private var message = "切到 B 服后点击开始"
    private var hidden = 0
    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).toInt()
    private fun command(action: String) = (service.application as ShittimApplication).command(action)

    fun show() {
        if (root != null) return
        hidden = 0
        val container = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = GradientDrawable().apply {
                setColor(Color.rgb(240, 249, 255)); cornerRadius = dp(20).toFloat()
                setStroke(dp(2), Color.rgb(0, 143, 204))
            }
            elevation = dp(8).toFloat()
        }
        root = container
        val bubble = TextView(service).apply {
            text = "什亭"; textSize = 16f; gravity = Gravity.CENTER
            setTextColor(Color.rgb(0, 113, 175)); contentDescription = "什亭悬浮球，点击展开，拖动移动"
            minWidth = dp(48); minHeight = dp(48)
        }
        container.addView(bubble)
        val controls = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL; visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(dp(224), LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        panel = controls
        status = TextView(service).apply {
            textSize = 12f; setTextColor(Color.rgb(34, 60, 80)); maxLines = 3
            setPadding(dp(6), dp(4), dp(6), dp(4))
        }.also { controls.addView(it) }
        fun button(label: String, action: () -> Unit): Button = Button(service).apply {
            text = label; textSize = 13f; isAllCaps = false; minHeight = dp(44)
            setOnClickListener { action() }; controls.addView(this)
        }
        start = button("开始只读诊断") { command("start") }
        pause = button("暂停") { command(if (state == "paused") "resume" else "pause") }
        stop = button("停止任务") { command("cancel") }
        button("关闭悬浮球") { command("cancel"); close() }
        container.addView(controls)
        bubble.setOnClickListener {
            controls.visibility = if (controls.visibility == View.GONE) View.VISIBLE else View.GONE
            container.post { clamp() }
        }
        var downX = 0f; var downY = 0f; var originX = 0; var originY = 0; var dragged = false
        val slop = ViewConfiguration.get(service).scaledTouchSlop
        bubble.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX; downY = event.rawY
                    originX = params.x; originY = params.y; dragged = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX; val dy = event.rawY - downY
                    if (abs(dx) > slop || abs(dy) > slop) dragged = true
                    if (dragged) { params.x = originX + dx.toInt(); params.y = originY + dy.toInt(); clamp() }
                }
                MotionEvent.ACTION_UP -> if (!dragged) view.performClick()
            }
            true
        }
        try { wm.addView(container, params) } catch (e: Exception) { root = null; throw e }
        update(state, message)
        container.post { clamp() }
    }

    fun update(next: String, detail: String) {
        state = next; message = detail
        status?.text = "只读诊断 · $detail"
        val busy = next in listOf("running", "paused", "stopping")
        start?.isEnabled = !busy
        pause?.isEnabled = next == "running" || next == "paused"
        pause?.text = if (next == "paused") "继续" else "暂停"
        stop?.isEnabled = busy && next != "stopping"
    }

    fun clamp() {
        val view = root ?: return
        val bounds = wm.currentWindowMetrics.bounds
        params.x = params.x.coerceIn(0, (bounds.width() - view.width).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (bounds.height() - view.height).coerceAtLeast(0))
        wm.updateViewLayout(view, params)
    }

    fun hideForCapture(): Long {
        if (root == null) return 0L
        hidden++
        // Require a producer frame newer than removal, never return the cached overlay image.
        val after = System.nanoTime()
        root?.visibility = View.INVISIBLE
        return after
    }
    fun restoreAfterCapture() {
        hidden = (hidden - 1).coerceAtLeast(0)
        if (hidden == 0) root?.visibility = View.VISIBLE
    }
    fun close() {
        root?.let { wm.removeView(it) }
        root = null; panel = null; status = null; start = null; pause = null; stop = null
        hidden = 0
    }
}
