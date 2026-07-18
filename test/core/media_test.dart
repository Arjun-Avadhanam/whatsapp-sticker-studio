import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';

void main() {
  test('MediaHandle carries its bytes, kind and mime type', () {
    final handle = MediaHandle(
      bytes: Uint8List.fromList([1, 2, 3]),
      kind: MediaKind.video,
      mimeType: 'video/mp4',
    );

    expect(handle.bytes, [1, 2, 3]);
    expect(handle.kind, MediaKind.video);
    expect(handle.mimeType, 'video/mp4');
  });

  test('MediaHandle mime type is optional', () {
    final handle = MediaHandle(bytes: Uint8List(0), kind: MediaKind.image);

    expect(handle.mimeType, isNull);
  });

  test('every MediaKind maps to the sticker kind it produces', () {
    expect(MediaKind.image.producesStickerKind, StickerKind.staticImage);
    expect(MediaKind.gif.producesStickerKind, StickerKind.animated);
    expect(MediaKind.video.producesStickerKind, StickerKind.animated);
  });
}
