package org.shittim.shittim_assist

import android.app.*
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.view.WindowManager
import java.io.ByteArrayOutputStream

class CaptureService : Service() {
    companion object {
        @Volatile var instance: CaptureService? = null; private set
        @Volatile var active = false; private set
    }
    private val worker = HandlerThread("shittim-capture")
    private lateinit var handler: Handler
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var latest: ByteArray? = null
    private var capturedAt = 0L
    private var frameTimestamp = 0L
    private var pendingAfter = 0L
    private var pending: ((ByteArray?, String?) -> Unit)? = null
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { active = false; stopSelf() }
        override fun onCapturedContentResize(width: Int, height: Int) {
            if (width > 0 && height > 0 && active) resize(width, height)
        }
    }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate(); worker.start(); handler = Handler(worker.looper); instance = this
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") { stopSelf(); return START_NOT_STICKY }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("capture", "屏幕采集", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 1, Intent(this, CaptureService::class.java).setAction("STOP"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(101, Notification.Builder(this, "capture")
            .setContentTitle("什亭助手正在采集屏幕").setContentText("点击打开工作台；停止将结束屏幕采集")
            .setSmallIcon(android.R.drawable.ic_menu_view).setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "停止采集", stop).build())
            .setOngoing(true).build())
        if (active) return START_NOT_STICKY
        @Suppress("DEPRECATION")
        val data = intent?.getParcelableExtra<Intent>("data")
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        if (data == null || resultCode != Activity.RESULT_OK) { stopSelf(); return START_NOT_STICKY }
        handler.post {
            try {
                val manager = getSystemService(MediaProjectionManager::class.java)
                projection = manager.getMediaProjection(resultCode, data)
                projection!!.registerCallback(projectionCallback, handler)
                val bounds = getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
                reader = newReader(bounds.width(), bounds.height())
                display = projection!!.createVirtualDisplay("Shittim Capture", bounds.width(), bounds.height(),
                    resources.displayMetrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    reader!!.surface, null, handler)
                active = true
            } catch (_: Exception) { stopSelf() }
        }
        return START_NOT_STICKY
    }
    private fun newReader(width: Int, height: Int): ImageReader {
        return ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2).apply {
            setOnImageAvailableListener({ source ->
                val image = try { source.acquireLatestImage() } catch (_: Exception) { null }
                if (image != null) {
                    try {
                        // Throttle encoding. Always close images to avoid starving the producer.
                        if (pending != null || SystemClock.elapsedRealtime() - capturedAt > 250) {
                            val plane = image.planes[0]
                            val paddedWidth = plane.rowStride / plane.pixelStride
                            val padded = Bitmap.createBitmap(paddedWidth, image.height, Bitmap.Config.ARGB_8888)
                            padded.copyPixelsFromBuffer(plane.buffer)
                            val cropped = Bitmap.createBitmap(padded, 0, 0, image.width, image.height)
                            val stream = ByteArrayOutputStream()
                            cropped.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            latest = stream.toByteArray(); capturedAt = SystemClock.elapsedRealtime()
                            if (cropped !== padded) cropped.recycle()
                            padded.recycle()
                            frameTimestamp = image.timestamp
                            if (frameTimestamp > pendingAfter) { pending?.invoke(latest, null); pending = null }
                        }
                    } catch (_: Exception) {
                        latest = null; pending?.invoke(null, "截图编码失败"); pending = null
                    } finally { image.close() }
                }
            }, handler)
        }
    }
    private fun resize(width: Int, height: Int) {
        if (reader?.width == width && reader?.height == height) return
        latest = null
        val old = reader
        reader = newReader(width, height)
        display?.resize(width, height, resources.displayMetrics.densityDpi)
        display?.surface = reader!!.surface
        old?.close()
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT < 34) handler.post {
            if (active) {
                val b = getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
                resize(b.width(), b.height())
            }
        }
    }
    fun screenshot(afterNanos: Long = 0L, callback: (ByteArray?, String?) -> Unit) {
        val accepted = handler.post {
            if (!active) { callback(null, "采集服务未就绪"); return@post }
            if (pending != null) { callback(null, "已有截图请求"); return@post }
            val bytes = latest
            if (bytes != null && frameTimestamp > afterNanos && SystemClock.elapsedRealtime() - capturedAt < 750) {
                callback(bytes, null); return@post
            }
            pendingAfter = afterNanos
            pending = callback
            handler.postDelayed({
                if (pending === callback) { pending = null; callback(null, "截图超时或屏幕已锁定") }
            }, 3000)
        }
        // A stop can race the overlay's compositor delay. Never leave Dart
        // waiting on a callback posted to a worker that has already quit.
        if (!accepted) callback(null, "屏幕采集已停止，请重新授权")
    }
    override fun onDestroy() {
        active = false; instance = null
        (application as ShittimApplication).command("cancel")
        GestureService.instance?.overlay?.update("failed", "屏幕采集已停止，请回助手重新授权")
        handler.post {
            pending?.invoke(null, "屏幕采集已停止"); pending = null
            projection?.unregisterCallback(projectionCallback)
            display?.release(); reader?.close(); projection?.stop()
            latest = null; worker.quitSafely()
        }
        super.onDestroy()
    }
}
