import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Turns text into a vector whose direction encodes meaning, so that "puppy"
/// lands near "dog" even though they share no letters.
///
/// Injected and nullable throughout search: if the model is missing or the
/// platform cannot supply it, search must degrade to keyword-only rather than
/// break. Semantic matching is an enhancement, never a dependency.
abstract class TextEmbedder {
  /// Returns the embedding, or `null` if this text cannot be embedded.
  Future<List<double>?> embed(String text);
}

/// [TextEmbedder] over MediaPipe's Universal Sentence Encoder, on the Kotlin
/// side. Only usable on a device.
class NativeTextEmbedder implements TextEmbedder {
  NativeTextEmbedder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must stay in sync with `TextEmbedderChannel.CHANNEL` (Kotlin).
  static const String channelName =
      'com.arjun.whatsapp_sticker_studio/text_embedder';

  final MethodChannel _channel;

  @override
  Future<List<double>?> embed(String text) async {
    if (text.trim().isEmpty) return null;
    try {
      final reply = await _channel.invokeMethod<List<Object?>>('embed', {
        'text': text,
      });
      if (reply == null || reply.isEmpty) return null;
      return reply.cast<double>();
    } on PlatformException {
      // A failed embedding degrades search to keyword-only; it must never take
      // the whole query down with it.
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Cosine similarity of two equal-length vectors, in [-1, 1].
///
/// Compares *direction*, not magnitude, which is what makes it the right
/// measure here: two phrases about dogs point the same way regardless of how
/// long either phrase is.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;

  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  // A zero vector has no direction, so similarity is undefined — report 0
  // rather than dividing by zero and producing NaN, which would poison sorting.
  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
