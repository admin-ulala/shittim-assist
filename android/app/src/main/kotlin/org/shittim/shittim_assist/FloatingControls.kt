package org.shittim.shittim_assist

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.*
import kotlin.math.abs

/** Native overlay never takes focus from the game. Dart owns all configuration. */
class FloatingControls(private val service: GestureService) {
    private val wm = service.getSystemService(WindowManager::class.java)
    private val blue = Color.rgb(0, 143, 204)
    private val ink = Color.rgb(35, 63, 83)
    private val muted = Color.rgb(102, 128, 148)
    private val pale = Color.rgb(236, 247, 255)
    private val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.LEFT; x = dp(12); y = dp(80) }
    private var root: LinearLayout? = null
    private var body: LinearLayout? = null
    private var scroller: ScrollView? = null
    private var footer: TextView? = null
    private var expanded = false
    private var tab = 0
    private var state = "idle"
    private var message = "待机"
    private var locked = false
    private var pending = false
    private var hidden = 0
    private var config: Map<String, Any?> = emptyMap()
    private var logs: List<Map<*, *>> = emptyList()
    private var notice = "与主界面同步 · 修改自动保存"
    private val editable get() = !locked && !pending && config.isNotEmpty()
    private fun dp(value: Int) = (value * service.resources.displayMetrics.density).toInt()
    private fun drawable(color: Int, radius: Int = 16, border: Boolean = false) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat()
        if (border) setStroke(dp(1), Color.rgb(194, 224, 241))
    }
    private fun column() = LinearLayout(service).apply { orientation = LinearLayout.VERTICAL }
    private fun row() = LinearLayout(service).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun text(value: String, size: Float = 13f, color: Int = ink, bold: Boolean = false) = TextView(service).apply {
        text = value; textSize = size; setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }
    private fun button(label: String, primary: Boolean = false, enabled: Boolean = true, action: () -> Unit) = Button(service).apply {
        text = label; textSize = 13f; isAllCaps = false; minHeight = dp(44); minimumWidth = 0
        setPadding(dp(10), dp(2), dp(10), dp(2))
        background = drawable(if (primary) blue else pale, 12)
        setTextColor(if (primary) Color.WHITE else blue)
        isEnabled = enabled; alpha = if (enabled) 1f else .4f
        setOnClickListener { action() }
    }
    private fun icon() = ImageView(service).apply {
        // Same resource as the launcher, including any future icon replacement.
        setImageDrawable(service.packageManager.getApplicationIcon(service.packageName))
        scaleType = ImageView.ScaleType.FIT_CENTER
        setPadding(dp(8), dp(8), dp(8), dp(8))
        contentDescription = "什亭助手应用图标"
    }
    private fun command(action: String) = (service.application as ShittimApplication).command(action)
    private fun request(method: String, args: Any? = null, done: (Any?, String?) -> Unit) {
        (service.application as ShittimApplication).bridge.request(method, args, done)
    }
    private fun refreshSnapshot() {
        request("overlaySnapshot") { data, error ->
            if (error != null) { notice = error; renderBody() }
            else sync(data as? Map<*, *> ?: emptyMap<Any, Any>())
        }
    }
    fun sync(snapshot: Map<*, *>) {
        (snapshot["config"] as? Map<*, *>)?.let { values ->
            config = values.entries.associate { it.key.toString() to it.value }
        }
        state = snapshot["state"] as? String ?: state
        message = snapshot["message"] as? String ?: message
        locked = snapshot["locked"] as? Boolean ?: locked
        logs = (snapshot["logs"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: logs
        renderBody()
    }
    private fun patch(key: String, value: Any) {
        if (!editable) return
        pending = true; notice = "正在保存…"; renderBody()
        request("overlayPatch", mapOf(key to value)) { data, error ->
            pending = false
            notice = error ?: "已同步到主界面并保存"
            if (error == null) sync(data as? Map<*, *> ?: emptyMap<Any, Any>())
            else { renderBody(); refreshSnapshot() }
        }
    }
    fun show() {
        if (root != null) { refreshSnapshot(); return }
        hidden = 0
        root = column().apply { elevation = dp(10).toFloat() }
        renderShell()
        try { wm.addView(root, params) } catch (e: Exception) { root = null; throw e }
        root?.post { clamp() }
        refreshSnapshot()
    }
    private fun renderShell() {
        val container = root ?: return
        container.removeAllViews()
        container.background = drawable(Color.rgb(246, 251, 255), if (expanded) 22 else 28, true)
        params.width = if (expanded) minOf(dp(360), wm.currentWindowMetrics.bounds.width() - dp(24)) else dp(56)
        params.height = WindowManager.LayoutParams.WRAP_CONTENT
        if (!expanded) {
            body = null; scroller = null; footer = null
            val bubble = icon().apply {
                contentDescription = "什亭悬浮球，点击展开，拖动移动"
                setOnClickListener { expanded = true; renderShell(); refreshSnapshot() }
            }
            container.addView(bubble, LinearLayout.LayoutParams(dp(56), dp(56)))
            draggable(bubble)
        } else {
            val header = row().apply { setPadding(dp(10), dp(6), dp(8), dp(4)) }
            header.addView(icon(), LinearLayout.LayoutParams(dp(42), dp(42)))
            header.addView(column().apply {
                addView(text("什亭助手", 17f, ink, true))
                addView(text("SHITTIM ASSIST", 9f, muted))
            }, LinearLayout.LayoutParams(0, dp(44), 1f))
            header.addView(button("—") { expanded = false; renderShell() }, LinearLayout.LayoutParams(dp(44), dp(44)))
            header.addView(button("×") { command("cancel"); close() }, LinearLayout.LayoutParams(dp(44), dp(44)))
            container.addView(header)
            draggable(header)
            val tabs = row().apply { setPadding(dp(12), dp(4), dp(12), dp(8)) }
            listOf("运行", "任务", "配置").forEachIndexed { index, label ->
                tabs.addView(button(label, tab == index) {
                    tab = index; renderShell(); refreshSnapshot()
                }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { setMargins(dp(2), 0, dp(2), 0) })
            }
            container.addView(tabs)
            body = column().apply { setPadding(dp(14), 0, dp(14), dp(8)) }
            scroller = ScrollView(service).apply { isFillViewport = false; addView(body) }
            val height = minOf(dp(330), wm.currentWindowMetrics.bounds.height() - dp(172)).coerceAtLeast(dp(100))
            container.addView(scroller, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, height))
            footer = text(notice, 11f, muted).apply { setPadding(dp(16), dp(8), dp(16), dp(12)); maxLines = 2 }
            container.addView(footer)
            renderBody()
        }
        if (container.isAttachedToWindow) wm.updateViewLayout(container, params)
        container.post { clamp() }
    }
    private fun card(title: String): LinearLayout {
        val card = column().apply {
            setPadding(dp(12), dp(10), dp(12), dp(10)); background = drawable(Color.WHITE, 14, true)
        }
        body?.addView(card, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dp(10)
        })
        card.addView(text(title, 13f, ink, true).apply { setPadding(0, 0, 0, dp(8)) })
        return card
    }
    private fun renderBody() {
        val content = body ?: return
        val scrollY = scroller?.scrollY ?: 0
        content.removeAllViews()
        footer?.text = if (locked) "运行期间配置已锁定 · 停止后可调整" else notice
        when (tab) {
            0 -> {
                val overview = card("设备诊断")
                overview.addView(text(if (CaptureService.active) "● 无障碍已开启 · 屏幕采集已就绪" else "● 屏幕采集未开启，请回主界面授权", 11f, muted))
                overview.addView(text("国服 · ${if (config["channel"] == "official") "官服（待适配）" else "B 服"}", 12f, muted))
                overview.addView(text(message, 16f, if (state == "failed") Color.rgb(187, 64, 76) else blue, true).apply {
                    setPadding(0, dp(8), 0, dp(8)); maxLines = 3
                })
                overview.addView(text("检查前台应用与截图，不领取奖励、不消耗体力。", 12f, muted))
                overview.addView(button("开始只读诊断", true, !locked && !pending && config["channel"] == "bilibili") {
                    command("start")
                }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)).apply { topMargin = dp(12) })
                val actions = row()
                actions.addView(button(if (state == "paused") "继续" else "暂停", enabled = state == "running" || state == "paused") {
                    command(if (state == "paused") "resume" else "pause")
                }, LinearLayout.LayoutParams(0, dp(44), 1f).apply { rightMargin = dp(6) })
                actions.addView(button("停止任务", enabled = state == "running" || state == "paused") {
                    command("cancel")
                }, LinearLayout.LayoutParams(0, dp(44), 1f))
                overview.addView(actions, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)).apply { topMargin = dp(8) })
                val events = card("最近运行记录")
                if (logs.isEmpty()) events.addView(text("暂无记录", 12f, muted))
                logs.forEach { entry -> events.addView(text(entry["message"]?.toString() ?: "", 12f,
                    if (entry["level"] == "error") Color.rgb(187, 64, 76) else muted).apply { setPadding(0, dp(4), 0, dp(4)) }) }
            }
            1 -> {
                val tasks = card("日常任务计划")
                tasks.addView(text("以下为计划配置，流程待适配。当前仅可运行只读诊断。", 12f, muted))
                val selected = (config["selected"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                listOf("signin" to "签到", "mail" to "邮件奖励", "daily" to "日常奖励", "sweep" to "关卡扫荡").forEach { (id, label) ->
                    tasks.addView(CheckBox(service).apply {
                        text = "$label · 待适配"; textSize = 13f; setTextColor(ink)
                        buttonTintList = ColorStateList.valueOf(blue)
                        isChecked = id in selected; isEnabled = editable; minHeight = dp(44)
                        setOnCheckedChangeListener { _, checked ->
                            patch("selected", if (checked) (selected + id).distinct() else selected - id)
                        }
                    })
                }
                val budget = card("资源预算")
                stepper(budget, "计划次数", "maxRuns", 1, 999)
                stepper(budget, "保留体力", "staminaReserve", 0, 999)
                budget.addView(text("青辉石消费与付费操作关闭", 12f, muted))
            }
            2 -> {
                val runtime = card("运行设置")
                runtime.addView(Switch(service).apply {
                    text = "只识别，不点击"; textSize = 13f; setTextColor(ink)
                    isChecked = config["dryRun"] != false; isEnabled = editable; minHeight = dp(44)
                    setOnCheckedChangeListener { _, checked -> patch("dryRun", checked) }
                })
                runtime.addView(text("关闭也不会启用尚未适配的任务。", 11f, muted))
                stepper(runtime, "超时（秒）", "timeoutSeconds", 5, 300)
                runtime.addView(text("长按 ＋ / − 可调整 10；与主界面共用配置。", 11f, muted))
                val server = card("客户端")
                listOf("bilibili" to "国服 · B 服", "official" to "国服 · 官服（待适配）").forEach { (id, label) ->
                    server.addView(RadioButton(service).apply {
                        text = label; textSize = 13f; setTextColor(ink); minHeight = dp(44)
                        buttonTintList = ColorStateList.valueOf(blue)
                        isChecked = config["channel"] == id; isEnabled = editable
                        setOnClickListener { patch("channel", id) }
                    })
                }
                server.addView(text("其他区服后续加入。ADB、配置导入导出在主界面管理。", 11f, muted))
            }
        }
        scroller?.post { scroller?.scrollTo(0, scrollY) }
    }
    private fun stepper(parent: LinearLayout, label: String, key: String, min: Int, max: Int) {
        val value = (config[key] as? Number)?.toInt() ?: min
        val line = row()
        line.addView(text(label, 12f), LinearLayout.LayoutParams(0, dp(48), 1f).apply { gravity = Gravity.CENTER_VERTICAL })
        val minus = button("−", enabled = editable && value > min) { patch(key, value - 1) }
        minus.setOnLongClickListener { patch(key, (value - 10).coerceAtLeast(min)); true }
        line.addView(minus, LinearLayout.LayoutParams(dp(40), dp(40)))
        line.addView(text(value.toString(), 13f, blue, true).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(38), dp(40)))
        val plus = button("+", enabled = editable && value < max) { patch(key, value + 1) }
        plus.setOnLongClickListener { patch(key, (value + 10).coerceAtMost(max)); true }
        line.addView(plus, LinearLayout.LayoutParams(dp(40), dp(40)))
        parent.addView(line)
    }
    private fun draggable(view: View) {
        var downX = 0f; var downY = 0f; var originX = 0; var originY = 0; var dragged = false
        val slop = ViewConfiguration.get(service).scaledTouchSlop
        view.setOnTouchListener { target, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX; downY = event.rawY; originX = params.x; originY = params.y; dragged = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX; val dy = event.rawY - downY
                    if (abs(dx) > slop || abs(dy) > slop) dragged = true
                    if (dragged) { params.x = originX + dx.toInt(); params.y = originY + dy.toInt(); clamp() }
                }
                MotionEvent.ACTION_UP -> if (!dragged) target.performClick()
            }
            true
        }
    }
    fun update(next: String, detail: String) {
        state = next; message = detail; locked = next in listOf("running", "paused", "stopping"); renderBody()
    }
    fun clamp() {
        val view = root ?: return
        if (!view.isAttachedToWindow) return
        val bounds = wm.currentWindowMetrics.bounds
        params.x = params.x.coerceIn(0, (bounds.width() - view.width).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (bounds.height() - view.height).coerceAtLeast(0))
        wm.updateViewLayout(view, params)
    }
    fun resize() { if (root != null) renderShell() }
    fun hideForCapture(): Long {
        if (root == null) return 0L
        hidden++
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
        root = null; body = null; scroller = null; footer = null; hidden = 0
    }
}
