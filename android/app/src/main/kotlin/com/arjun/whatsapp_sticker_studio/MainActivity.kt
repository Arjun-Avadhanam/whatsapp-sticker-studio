package com.arjun.whatsapp_sticker_studio

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var stickerExport: StickerExportChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WebpEncoderChannel.CHANNEL)
            .setMethodCallHandler(WebpEncoderChannel())

        val export = StickerExportChannel(this)
        stickerExport = export
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, StickerExportChannel.CHANNEL)
            .setMethodCallHandler(export)
    }

    // WhatsApp's answer to ENABLE_STICKER_PACK arrives here; the channel is holding a
    // pending Dart result waiting for it.
    @Deprecated("onActivityResult is how the sticker API reports back")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (stickerExport?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
