import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How the app presents itself on the phone: its name under the icon, and the
/// icon itself.
///
/// Worth pinning because both are **generated, checked-in artefacts** that no
/// other test touches. `android:label` is a hand edit to a scaffold-owned file,
/// and the mipmaps come from `dart run flutter_launcher_icons` — so a revert, a
/// merge, or a regenerated scaffold could quietly restore
/// `whatsapp_sticker_studio` and the blue Flutter default, and nothing else in
/// the suite would notice. The failure is only visible on a real home screen.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('the launcher name is the product name, not the package name', () {
    expect(
      manifest.readAsStringSync(),
      contains('android:label="Sticker Studio"'),
    );
  });

  test('the adaptive icon is generated, with our background', () {
    // Adaptive icons are two layers plus a flat colour; a launcher masks the
    // foreground to whatever shape it likes, so the background must exist as a
    // real resource rather than being baked into the artwork.
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    );
    expect(adaptive.existsSync(), isTrue);
    expect(adaptive.readAsStringSync(), contains('ic_launcher_foreground'));

    final colours = File('android/app/src/main/res/values/colors.xml');
    expect(colours.existsSync(), isTrue);
    expect(colours.readAsStringSync().toLowerCase(), contains('#1a1c28'));
  });

  test('the icon sources are committed, so the icon is reproducible', () {
    // `tool/make_app_icon.py` regenerates these; keeping the PNGs in the tree
    // means a checkout builds the right icon without running Python.
    expect(File('assets/icon/icon.png').existsSync(), isTrue);
    expect(File('assets/icon/icon_foreground.png').existsSync(), isTrue);
  });
}
