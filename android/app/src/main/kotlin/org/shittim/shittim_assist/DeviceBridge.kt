package org.shittim.shittim_assist

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class DeviceBridge(private val context: Context, engine: FlutterEngine) {
    var activity: MainActivity? = null
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "org.shittim.assist/device")
    fun request(method: String, arguments: Any?, callback: (Any?, String?) -> Unit) {
        channel.invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) { callback(result, null) }
            override fun error(code: String, message: String?, details: Any?) { callback(null, message ?: "操作失败") }
            override fun notImplemented() { callback(null, "请先打开助手完成初始化") }
        })
    }
    fun command(action: String) {
        channel.invokeMethod("overlayCommand", action, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) {
                GestureService.instance?.overlay?.update("failed", message ?: "控制失败")
            }
            override fun notImplemented() {
                GestureService.instance?.overlay?.update("failed", "请先打开助手完成初始化")
            }
        })
    }
    private var captureResult: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dataDirectory" -> result.success(context.filesDir.absolutePath)
                        "capabilities" -> result.success(mapOf(
                            "accessibility" to (GestureService.instance != null),
                            "capture" to CaptureService.active))
                        "openAccessibility" -> {
                            requireActivity().startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success(null)
                        }
                        "requestCapture" -> {
                            if (captureResult != null) {
                                result.error("BUSY", "已有屏幕授权请求", null)
                            } else if (CaptureService.active) {
                                result.success(null)
                            } else {
                                captureResult = result
                                val manager = context.getSystemService(MediaProjectionManager::class.java)
                                val intent = if (Build.VERSION.SDK_INT >= 34) {
                                    manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
                                } else manager.createScreenCaptureIntent()
                                @Suppress("DEPRECATION")
                                requireActivity().startActivityForResult(intent, 1101)
                            }
                        }
                        "stopCapture" -> {
                            command("cancel")
                            context.stopService(Intent(context, CaptureService::class.java))
                            result.success(null)
                        }
                        "screenshot" -> {
                            val service = CaptureService.instance
                            if (service == null) result.error("CAPTURE_OFF", "请先授权屏幕采集", null)
                            else {
                                val overlay = GestureService.instance?.overlay
                                val hiddenAt = overlay?.hideForCapture() ?: 0L
                                // Window removal and the virtual-display producer are asynchronous.
                                // Let the compositor settle, then require a NEW producer frame.
                                // A timestamp taken before removal can accept a still-visible frame.
                                handler.postDelayed({
                                    val after = if (hiddenAt == 0L) 0L else System.nanoTime()
                                    service.screenshot(after) { bytes, error ->
                                        handler.post {
                                            overlay?.restoreAfterCapture()
                                            if (bytes != null) result.success(bytes)
                                            else result.error("CAPTURE_FAILED", error, null)
                                        }
                                    }
                                }, if (hiddenAt == 0L) 0L else 200L)
                            }
                        }
                        "showOverlay" -> {
                            val service = GestureService.instance ?: error("请先开启无障碍服务")
                            check(CaptureService.active) { "请先授权屏幕采集，等待采集就绪后重试" }
                            service.overlay.show()
                            result.success(null)
                        }
                        "overlaySnapshot" -> {
                            GestureService.instance?.overlay?.sync(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                            result.success(null)
                        }
                        "overlayState" -> {
                            GestureService.instance?.overlay?.update(
                                call.argument<String>("state") ?: "idle",
                                call.argument<String>("message") ?: "只读诊断")
                            result.success(null)
                        }
                        "foregroundPackage" -> result.success(GestureService.instance?.foregroundPackage ?: "")
                        "tap", "swipe", "back" -> {
                            val service = GestureService.instance
                            if (service == null) {
                                result.error("ACCESSIBILITY_OFF", "请先开启无障碍服务", null)
                            } else if (call.method == "back") {
                                if (service.goBack()) result.success(null)
                                else result.error("INPUT_FAILED", "返回操作未执行", null)
                            } else {
                                fun n(key: String) = (call.argument<Number>(key)
                                    ?: throw IllegalArgumentException("缺少参数 $key")).toFloat()
                                val tap = call.method == "tap"
                                val x1 = n(if (tap) "x" else "x1")
                                val y1 = n(if (tap) "y" else "y1")
                                val x2 = if (tap) x1 else n("x2")
                                val y2 = if (tap) y1 else n("y2")
                                val duration = if (tap) 80L else (call.argument<Number>("duration")?.toLong() ?: 300L)
                                service.gesture(x1, y1, x2, y2, duration) { ok ->
                                    if (ok) result.success(null)
                                    else result.error("INPUT_FAILED", "手势取消、超时或坐标无效", null)
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    if (captureResult === result) captureResult = null
                    result.error("PLATFORM_ERROR", e.message, null)
                }
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 1101) return
        val result = captureResult
        captureResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.error("CAPTURE_DENIED", "屏幕采集未获授权", null)
            return
        }
        try {
            context.startForegroundService(Intent(context, CaptureService::class.java)
                .putExtra("resultCode", resultCode).putExtra("data", data))
            val deadline = android.os.SystemClock.elapsedRealtime() + 5000
            fun awaitReady() {
                if (CaptureService.active) result?.success(null)
                else if (android.os.SystemClock.elapsedRealtime() >= deadline)
                    result?.error("CAPTURE_START_FAILED", "屏幕采集未就绪，请重新授权", null)
                else handler.postDelayed({ awaitReady() }, 50)
            }
            awaitReady()
        } catch (e: Exception) { result?.error("CAPTURE_START_FAILED", e.message, null) }
    }

    private fun requireActivity(): MainActivity = activity ?: error("请在助手界面请求授权")
    fun detach(host: MainActivity) {
        if (activity !== host) return
        captureResult?.error("ACTIVITY_DESTROYED", "授权页面已关闭", null)
        captureResult = null
        activity = null
    }
}
