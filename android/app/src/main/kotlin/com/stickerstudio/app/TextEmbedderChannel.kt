package com.stickerstudio.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Turns text into an embedding vector for semantic search (Task 10 Step 4).
 *
 * Uses MediaPipe's TextEmbedder rather than driving the .tflite file directly: the Universal
 * Sentence Encoder needs **SentencePiece tokenisation** to turn text into token ids, and a raw
 * TFLite interpreter only exposes tensors — we would have to reimplement that tokeniser in Dart.
 * MediaPipe does it natively from the model's own metadata.
 *
 * Only the vector is returned; cosine similarity and ranking stay in Dart, where they are testable
 * without a device.
 */
class TextEmbedderChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.stickerstudio.app/text_embedder"

        /** Bundled uncompressed in src/main/assets; see noCompress in build.gradle.kts. */
        private const val MODEL = "universal_sentence_encoder.tflite"
    }

    // Loading the model costs real time, so it is created once on first use and kept.
    private var embedder: TextEmbedder? = null

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "embed") {
            result.notImplemented()
            return
        }

        val text = call.argument<String>("text")
        if (text == null) {
            result.error("bad_args", "embed requires text", null)
            return
        }

        // Inference off the platform thread; replies posted back to it, because
        // MethodChannel.Result is not thread-safe.
        worker.execute {
            try {
                val vector = embed(text)
                main.post { result.success(vector) }
            } catch (e: Throwable) {
                main.post {
                    result.error("embed_failed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun embed(text: String): List<Double> {
        val active = embedder ?: TextEmbedder.createFromOptions(
            context,
            TextEmbedder.TextEmbedderOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(MODEL).build())
                // Float embeddings, not quantised: cosine similarity on quantised
                // vectors loses enough precision to reorder near-ties, and the
                // vectors are small enough that the space saving is irrelevant.
                .setQuantize(false)
                .build(),
        ).also { embedder = it }

        val embeddings = active.embed(text).embeddingResult().embeddings()
        if (embeddings.isEmpty()) throw IllegalStateException("no embedding produced")

        // Kotlin FloatArray does not survive the Flutter codec; Double does.
        return embeddings[0].floatEmbedding().map { it.toDouble() }
    }
}
