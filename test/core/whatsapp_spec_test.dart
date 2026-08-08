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

  test('the enforced floor is deliberately BELOW the documented minimum', () {
    // Not a mistake and not drift. Device-verified 2026-08-01 that WhatsApp
    // v2.26.27.85 installs 1- and 2-sticker packs despite documenting a
    // 3-minimum, and sending a single sticker is the common case. The documented
    // value stays honest so nothing in the codebase asserts something false about
    // WhatsApp's spec; the gate reads the enforced one.
    expect(WhatsAppSpec.enforcedMinStickersPerPack, 1);
    expect(
      WhatsAppSpec.enforcedMinStickersPerPack,
      lessThanOrEqualTo(WhatsAppSpec.minStickersPerPack),
      reason: 'enforcing MORE than WhatsApp documents would be a bug',
    );
  });
}
