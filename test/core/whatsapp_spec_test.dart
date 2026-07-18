import 'package:flutter_test/flutter_test.dart';
import 'package:whatsapp_sticker_studio/core/whatsapp_spec.dart';

void main() {
  test('spec constants match WhatsApp ceilings', () {
    expect(WhatsAppSpec.dimension, 512);
    expect(WhatsAppSpec.maxStaticBytes, 102400);
    expect(WhatsAppSpec.maxAnimatedBytes, 512000);
    expect(WhatsAppSpec.maxTrayBytes, 51200);
    expect(WhatsAppSpec.trayDimension, 96);
    expect(WhatsAppSpec.minStickersPerPack, 3);
    expect(WhatsAppSpec.maxStickersPerPack, 30);
    expect(WhatsAppSpec.maxAnimationMs, 10000);
    expect(WhatsAppSpec.minFrameMs, 8);
  });
}
