package org.shittim.shittim_assist

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var captureResult: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.shittim.assist/device")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dataDirectory" -> result.success(filesDir.absolutePath)
                        "capabilities" -> result.success(mapOf(
                            "accessibility" to (GestureService.instance != null),
                            "capture" to CaptureService.active))
                        "openAccessibility" -> {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success(null)
                        }
                        "requestCapture" -> {
                            if (captureResult != null) {
                                result.error("BUSY", "已有屏幕授权请求", null)
                            } else if (CaptureService.active) {
                                result.success(null)
                            } else {
                                captureResult = result
                                val manager = getSystemService(MediaProjectionManager::class.java)
                                val intent = if (Build.VERSION.SDK_INT >= 34) {
                                    manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
                                } else manager.createScreenCaptureIntent()
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, 1101)
                            }
                        }
                        "stopCapture" -> {
                            stopService(Intent(this, CaptureService::class.java))
                            result.success(null)
                        }
                        "screenshot" -> {
                            val service = CaptureService.instance
                            if (service == null) result.error("CAPTURE_OFF", "请先授权屏幕采集", null)
                            else service.screenshot { bytes, error ->
                                handler.post {
                                    if (bytes != null) result.success(bytes)
                                    else result.error("CAPTURE_FAILED", error, null)
                                }
                            }
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
                    result.error("PLATFORM_ERROR", e.message, null)
                }
            }
    }

    @Deprecated("Activity result bridge required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1101) return
        val result = captureResult
        captureResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.error("CAPTURE_DENIED", "屏幕采集未获授权", null)
            return
        }
        try {
            startForegroundService(Intent(this, CaptureService::class.java)
                .putExtra("resultCode", resultCode).putExtra("data", data))
            result?.success(null)
        } catch (e: Exception) { result?.error("CAPTURE_START_FAILED", e.message, null) }
    }

    override fun onDestroy() {
        captureResult?.error("ACTIVITY_DESTROYED", "授权页面已关闭", null)
        captureResult = null
        super.onDestroy()
    }
}
