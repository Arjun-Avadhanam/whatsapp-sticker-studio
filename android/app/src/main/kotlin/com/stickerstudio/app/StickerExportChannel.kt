package com.stickerstudio.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Fires WhatsApp's `ENABLE_STICKER_PACK` intent and reports back what WhatsApp said.
 *
 * The pack must already be staged on disk and served by [StickerContentProvider] before this runs —
 * WhatsApp queries the provider while handling the intent.
 */
class StickerExportChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.stickerstudio.app/sticker_export"
        const val REQUEST_CODE = 2001

        private const val ACTION = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
        private const val EXTRA_ID = "sticker_pack_id"
        private const val EXTRA_AUTHORITY = "sticker_pack_authority"
        private const val EXTRA_NAME = "sticker_pack_name"

        /** WhatsApp's only diagnostic when it refuses a pack. */
        private const val EXTRA_VALIDATION_ERROR = "validation_error"
    }

    /** Held while WhatsApp is in the foreground; answered from [onActivityResult]. */
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "enableStickerPack") {
            result.notImplemented()
            return
        }

        if (pending != null) {
            result.error("already_exporting", "An export is already awaiting WhatsApp", null)
            return
        }

        val identifier = call.argument<String>("identifier")
        val authority = call.argument<String>("authority")
        val name = call.argument<String>("name")
        if (identifier == null || authority == null || name == null) {
            result.error("bad_args", "enableStickerPack needs identifier, authority, name", null)
            return
        }

        val intent = Intent(ACTION).apply {
            putExtra(EXTRA_ID, identifier)
            putExtra(EXTRA_AUTHORITY, authority)
            putExtra(EXTRA_NAME, name)
        }

        try {
            pending = result
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            // No WhatsApp (or a build too old to advertise the sticker API).
            pending = null
            result.error("whatsapp_unavailable", "WhatsApp is not installed", null)
        }
    }

    /**
     * Forwarded from the activity. Returns true if this was our request.
     *
     * Reports **two** facts rather than one nullable error: a user who backs out of WhatsApp's
     * confirmation produces no `validation_error`, and collapsing that into "no error" would let
     * the app record a pack as exported when the user actually declined.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false

        val result = pending ?: return true
        pending = null

        result.success(
            mapOf(
                "added" to (resultCode == Activity.RESULT_OK),
                "validationError" to data?.getStringExtra(EXTRA_VALIDATION_ERROR),
            ),
        )
        return true
    }
}
