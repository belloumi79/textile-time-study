import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textile_time_study/services/gemini_service.dart';

void main() {
  test('messages d\'erreur en français', () {
    expect(GeminiService.errorFor(429, '{"error":{"status":"RESOURCE_EXHAUSTED","message":"quota"}}').message,
        contains('Quota'));
    expect(GeminiService.errorFor(400, '{"error":{"message":"API key not valid"}}').message, contains('Clé API'));
    expect(GeminiService.errorFor(404, '').message, contains('Modèle'));
    expect(GeminiService.errorFor(503, 'x').message, contains('indisponible'));
  });

  test('extrait le texte en ignorant les « thoughts »', () {
    final t = GeminiService.extractText({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'je réfléchis', 'thought': true},
              {'text': '{"elements":[]}'},
            ]
          }
        }
      ]
    });
    expect(t, '{"elements":[]}');
    expect(() => GeminiService.extractText({'candidates': []}), throwsA(isA<GeminiException>()));
  });

  test('petite vidéo envoyée en ligne (inline_data + fps)', () async {
    final dir = await Directory.systemTemp.createTemp('tts');
    final f = File('${dir.path}/v.mp4')..writeAsBytesSync(List.filled(100, 1));
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      expect(req.url.path, contains('models/gemini-test:generateContent'));
      expect(req.headers['x-goog-api-key'], 'K');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '{"elements":[]}'}
                  ]
                }
              }
            ]
          }),
          200);
    });
    final svc = GeminiService(apiKey: 'K', model: 'gemini-test', fps: 3, client: client);
    final out = await svc.analyzeVideo(f, 'prompt');
    expect(out, '{"elements":[]}');
    final part = (sent['contents'] as List).first['parts'][0] as Map;
    expect(part['inline_data']['mime_type'], 'video/mp4');
    expect(part['video_metadata']['fps'], 3);
    expect(sent['generationConfig']['responseMimeType'], 'application/json');
    await dir.delete(recursive: true);
  });

  test('quota atteint -> GeminiException', () async {
    final dir = await Directory.systemTemp.createTemp('tts');
    final f = File('${dir.path}/v.mp4')..writeAsBytesSync([1, 2, 3]);
    final client = MockClient((_) async => http.Response('{"error":{"status":"RESOURCE_EXHAUSTED"}}', 429));
    final svc = GeminiService(apiKey: 'K', model: 'm', client: client);
    await expectLater(svc.analyzeVideo(f, 'p'), throwsA(isA<GeminiException>().having((e) => e.statusCode, 'code', 429)));
    await dir.delete(recursive: true);
  });

  test('clé absente -> message clair', () async {
    final svc = GeminiService(apiKey: '', model: 'm');
    await expectLater(svc.analyzeVideo(File('x'), 'p'), throwsA(isA<GeminiException>()));
  });

  test('grosse vidéo : envoi resumable (Files API) puis generateContent', () async {
    final dir = await Directory.systemTemp.createTemp('tts');
    final f = File('${dir.path}/v.mov')..writeAsBytesSync(List.filled(64, 7));
    final calls = <String>[];
    final client = MockClient.streaming((req, body) async {
      final bytes = await body.toBytes();
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/upload/v1beta/files') {
        expect(req.headers['X-Goog-Upload-Command'] ?? req.headers['x-goog-upload-command'], 'start');
        return http.StreamedResponse(const Stream.empty(), 200,
            headers: {'x-goog-upload-url': 'https://upload.example/u1'});
      }
      if (req.url.host == 'upload.example') {
        expect(bytes.length, 64);
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'file': {'name': 'files/abc', 'uri': 'https://g/files/abc', 'state': 'PROCESSING'}
            }))),
            200);
      }
      if (req.method == 'GET' && req.url.path == '/v1beta/files/abc') {
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'name': 'files/abc', 'uri': 'https://g/files/abc', 'state': 'ACTIVE'}))), 200);
      }
      if (req.url.path.endsWith(':generateContent')) {
        final j = jsonDecode(utf8.decode(bytes)) as Map;
        final part = (j['contents'] as List).first['parts'][0] as Map;
        expect(part['file_data']['file_uri'], 'https://g/files/abc');
        expect(part['file_data']['mime_type'], 'video/quicktime');
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '[]'}
                    ]
                  }
                }
              ]
            }))),
            200);
      }
      return http.StreamedResponse(const Stream.empty(), 200);
    });
    final svc = GeminiService(apiKey: 'K', model: 'm', client: client, inlineLimitBytes: 10);
    final out = await svc.analyzeVideo(f, 'p');
    expect(out, '[]');
    expect(calls.first, 'POST /upload/v1beta/files');
    expect(calls.any((c) => c.startsWith('GET /v1beta/files/abc')), isTrue);
    await dir.delete(recursive: true);
  });
}
