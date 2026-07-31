package com.arjun.whatsapp_sticker_studio

import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Native half of the Dart `WebpEncoder` interface: compresses an RGBA bitmap to
 * static WebP under a byte ceiling, stepping quality down until it fits.
 *
 * Android's own encoder is used rather than ffmpeg/libwebp. It is built into the
 * platform (no dependency, no extra APK weight), and it compresses **in memory**
 * — the quality ladder re-encodes up to six times, and doing that through ffmpeg
 * would mean six process invocations and six temp-file round-trips every time the
 * Maker refreshes its live size/quality readout.
 *
 * Animated WebP is *not* handled here: Android has no built-in animated-WebP
 * encoder at any API level. That path goes through ffmpeg's libwebp (Task 6).
 */
class WebpEncoderChannel : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.arjun.whatsapp_sticker_studio/webp"

        /** Tried in order; the first result at or under the ceiling wins. */
        private val QUALITY_LADDER = intArrayOf(100, 90, 80, 70, 60, 50)
    }

    // Compressing a 512² bitmap up to six times takes long enough to drop frames
    // if it runs on the platform thread. Results must still be delivered on the
    // main thread — MethodChannel.Result is not thread-safe.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "encodeStatic") {
            result.notImplemented()
            return
        }

        val rgba = call.argument<ByteArray>("rgba")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val maxBytes = call.argument<Int>("maxBytes")

        if (rgba == null || width == null || height == null || maxBytes == null) {
            result.error("bad_args", "encodeStatic requires rgba, width, height, maxBytes", null)
            return
        }
        if (rgba.size != width * height * 4) {
            result.error(
                "bad_args",
                "rgba is ${rgba.size} bytes, expected ${width * height * 4} for ${width}x$height",
                null,
            )
            return
        }

        worker.execute {
            try {
                val encoded = encode(rgba, width, height, maxBytes)
                main.post { result.success(encoded) }
            } catch (e: Throwable) {
                main.post { result.error("encode_failed", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun encode(rgba: ByteArray, width: Int, height: Int, maxBytes: Int): Map<String, Any> {
        val bitmap = toBitmap(rgba, width, height)
        try {
            var smallest: ByteArray? = null
            var smallestQuality = 0

            for (quality in QUALITY_LADDER) {
                val bytes = compress(bitmap, quality)
                if (bytes.size <= maxBytes) {
                    return mapOf("bytes" to bytes, "quality" to quality)
                }
                if (smallest == null || bytes.size < smallest.size) {
                    smallest = bytes
                    smallestQuality = quality
                }
            }

            // Never return an oversize sticker — WhatsApp would reject it, and a
            // silent overshoot here surfaces as an opaque failure at export time.
            throw IllegalStateException(
                "cannot fit $maxBytes bytes: smallest was ${smallest?.size} " +
                    "at quality $smallestQuality",
            )
        } finally {
            bitmap.recycle()
        }
    }

    private fun compress(bitmap: Bitmap, quality: Int): ByteArray {
        // WEBP_LOSSY/WEBP_LOSSLESS only exist from API 30; below that the
        // deprecated WEBP constant is the lossy encoder. minSdk is 24.
        @Suppress("DEPRECATION")
        val format =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSY
            } else {
                Bitmap.CompressFormat.WEBP
            }

        val out = ByteArrayOutputStream()
        if (!bitmap.compress(format, quality, out)) {
            throw IllegalStateException("Bitmap.compress failed at quality $quality")
        }
        return out.toByteArray()
    }

    /**
     * Packs RGBA bytes into an ARGB_8888 bitmap.
     *
     * Deliberately uses [Bitmap.setPixels] with explicitly packed 0xAARRGGBB
     * ints rather than the faster `copyPixelsFromBuffer`. The latter copies raw
     * bytes with no conversion, so it silently depends on ARGB_8888's in-memory
     * byte order — which is not RGBA on every platform, and gets the red and
     * blue channels swapped when it is wrong. Stickers must keep their alpha
     * (letterbox padding is transparent), so channel order is load-bearing.
     */
    private fun toBitmap(rgba: ByteArray, width: Int, height: Int): Bitmap {
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val o = i * 4
            val r = rgba[o].toInt() and 0xFF
            val g = rgba[o + 1].toInt() and 0xFF
            val b = rgba[o + 2].toInt() and 0xFF
            val a = rgba[o + 3].toInt() and 0xFF
            pixels[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }
}
