import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whatsapp_sticker_studio/core/media.dart';
import 'package:whatsapp_sticker_studio/sources/extraction_client.dart';

ExtractionClient clientReturning(
  String body, {
  int status = 200,
  void Function(http.Request)? onRequest,
}) {
  final mock = MockClient((req) async {
    onRequest?.call(req);
    return http.Response(body, status);
  });
  return ExtractionClient(mock, Uri.parse('http://localhost:8000'));
}

void main() {
  test('parses mp4_url and kind from a 200 response', () async {
    final media = await clientReturning(
      '{"mp4_url":"https://video.twimg.com/x.mp4","kind":"video"}',
    ).extract('https://x.com/u/status/1');

    expect(media.mp4Url.toString(), endsWith('.mp4'));
    expect(media.kind, MediaKind.video);
  });

  test('POSTs the tweet url as JSON to /extract', () async {
    http.Request? captured;
    await clientReturning(
      '{"mp4_url":"https://v/x.mp4","kind":"video"}',
      onRequest: (req) => captured = req,
    ).extract('https://x.com/u/status/1');

    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/extract');
    expect(jsonDecode(captured!.body)['url'], 'https://x.com/u/status/1');
  });

  test('throws ExtractionException on a 422', () async {
    expect(
      () => clientReturning(
        '{"detail":{"error":"unavailable"}}',
        status: 422,
      ).extract('https://x.com/u/status/1'),
      throwsA(isA<ExtractionException>()),
    );
  });
}
