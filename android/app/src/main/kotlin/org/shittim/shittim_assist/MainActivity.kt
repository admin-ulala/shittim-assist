package org.shittim.shittim_assist

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val owner get() = application as ShittimApplication
    override fun provideFlutterEngine(context: Context): FlutterEngine = owner.engine
    override fun shouldDestroyEngineWithHost() = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        owner.bridge.activity = this
    }
    @Deprecated("Activity result bridge required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        owner.bridge.onActivityResult(requestCode, resultCode, data)
    }
    override fun onDestroy() {
        owner.bridge.detach(this)
        super.onDestroy()
    }
}
