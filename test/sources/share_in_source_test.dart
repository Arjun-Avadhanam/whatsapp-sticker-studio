import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/share_in_source.dart';

/// Stands in for the platform channel.
///
/// `ReceiveSharingIntent` is an abstract `PlatformInterface`, so extending it is
/// the supported way to substitute it — and it keeps the cold/warm split under
/// test identical to production.
class FakeIntent extends ReceiveSharingIntent {
  FakeIntent({this.initial = const [], this.warm = const []});

  List<SharedMediaFile> initial;
  final List<SharedMediaFile> warm;
  int resets = 0;

  @override
  Future<List<SharedMediaFile>> getInitialMedia() async => initial;

  @override
  Stream<List<SharedMediaFile>> getMediaStream() => Stream.value(warm);

  @override
  Future<void> reset() async => resets++;
}

SharedMediaFile fileOf(String path, {String? mimeType}) => SharedMediaFile(
  path: path,
  type: SharedMediaType.image,
  mimeType: mimeType,
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('share_in'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String writeImage(String name, {List<int>? bytes}) {
    final file = File('${dir.path}/$name')
      ..writeAsBytesSync(bytes ?? const [1, 2, 3, 4]);
    return file.path;
  }

  group('cold start', () {
    test('returns the media the app was launched by', () async {
      final path = writeImage('shared.png');
      final source = ShareInSource(intent: FakeIntent(initial: [fileOf(path)]));

      final media = await source.pick();

      expect(media, isNotNull);
      expect(media!.kind, MediaKind.image);
      expect(media.bytes, [1, 2, 3, 4]);
    });

    test('resets afterwards so the share is not replayed', () async {
      // Without reset() the same share comes back every time the app asks, so a
      // user who shared one image once would find it reappearing forever.
      final intent = FakeIntent(initial: [fileOf(writeImage('a.png'))]);
      final source = ShareInSource(intent: intent);

      await source.pick();

      expect(intent.resets, 1);
    });

    test('no share yields null and no reset', () async {
      final intent = FakeIntent();
      final source = ShareInSource(intent: intent);

      expect(await source.pick(), isNull);
      expect(intent.resets, 0, reason: 'nothing to clear');
    });
  });

  group('choosing among shared files', () {
    test('skips a file that does not exist', () async {
      final source = ShareInSource(
        intent: FakeIntent(
          initial: [
            fileOf('${dir.path}/ghost.png'),
            fileOf(writeImage('r.png')),
          ],
        ),
      );

      expect((await source.pick())!.bytes, [1, 2, 3, 4]);
    });

    test('skips a file it cannot READ, rather than crashing', () async {
      // Found on device 2026-08-13: a share can hand over a path this process
      // has no permission to open, and the unguarded read escaped as an
      // UNHANDLED exception — the app died on a share instead of moving on.
      // Existing and readable are different things.
      final locked = writeImage('locked.png');
      Process.runSync('chmod', ['000', locked]);
      addTearDown(() => Process.runSync('chmod', ['644', locked]));

      // Skipped when running as root, which can read anything.
      if (File(locked).statSync().modeString().startsWith('---') == false) {
        return;
      }

      final source = ShareInSource(
        intent: FakeIntent(
          initial: [fileOf(locked), fileOf(writeImage('good.png'))],
        ),
      );

      final media = await source.pick();
      expect(media?.bytes, [
        1,
        2,
        3,
        4,
      ], reason: 'the unreadable file must be skipped, not fatal');
    });

    test('skips an empty file', () async {
      final source = ShareInSource(
        intent: FakeIntent(
          initial: [
            fileOf(writeImage('empty.png', bytes: const [])),
            fileOf(writeImage('good.png')),
          ],
        ),
      );

      expect((await source.pick())!.bytes, [1, 2, 3, 4]);
    });

    test('skips a kind we cannot make a sticker from', () async {
      // ACTION_SEND_MULTIPLE can include documents. Failing the whole share
      // because item one was a PDF would be worse than taking item two.
      final source = ShareInSource(
        intent: FakeIntent(
          initial: [
            fileOf(writeImage('doc.pdf'), mimeType: 'application/pdf'),
            fileOf(writeImage('good.png')),
          ],
        ),
      );

      expect((await source.pick())!.bytes, [1, 2, 3, 4]);
    });

    test('nothing usable yields null', () async {
      final source = ShareInSource(
        intent: FakeIntent(
          initial: [fileOf(writeImage('doc.pdf'), mimeType: 'application/pdf')],
        ),
      );

      expect(await source.pick(), isNull);
    });
  });

  group('warm shares', () {
    test('the stream carries media arriving while the app runs', () async {
      // Handling only the cold case is the classic mistake: a share target is
      // usually already in memory when someone shares to it.
      final source = ShareInSource(
        intent: FakeIntent(warm: [fileOf(writeImage('warm.png'))]),
      );

      expect((await source.stream().first).bytes, [1, 2, 3, 4]);
    });

    test('an unusable warm share is dropped, not emitted as null', () async {
      final source = ShareInSource(
        intent: FakeIntent(
          initial: const [],
          warm: [fileOf(writeImage('x.pdf'), mimeType: 'application/pdf')],
        ),
      );

      expect(await source.stream().isEmpty, isTrue);
    });
  });
}
