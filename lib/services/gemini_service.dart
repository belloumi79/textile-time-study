import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Erreur IA avec message en français, affichable tel quel.
class GeminiException implements Exception {
  GeminiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

typedef ProgressCallback = void Function(String step);

/// Appel minimal de l'API Gemini (REST, clé gratuite AI Studio).
class GeminiService {
  GeminiService({
    required this.apiKey,
    required this.model,
    this.fps = 2,
    http.Client? client,
    this.inlineLimitBytes = 15 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  static const base = 'https://generativelanguage.googleapis.com';
  final String apiKey;
  final String model;

  /// Images analysées par seconde de vidéo (1 par défaut côté Google).
  final double fps;
  final int inlineLimitBytes;
  final http.Client _client;

  Map<String, String> get _auth => {'x-goog-api-key': apiKey};

  static String mimeFor(String path) => switch (p.extension(path).toLowerCase()) {
        '.mov' => 'video/quicktime',
        '.webm' => 'video/webm',
        '.3gp' => 'video/3gpp',
        '.avi' => 'video/avi',
        '.wmv' => 'video/wmv',
        '.mpg' || '.mpeg' => 'video/mpeg',
        _ => 'video/mp4',
      };

  /// Envoie la vidéo + le prompt, renvoie le texte de la réponse (JSON attendu).
  Future<String> analyzeVideo(File video, String prompt, {ProgressCallback? onProgress}) async {
    if (apiKey.trim().isEmpty) {
      throw GeminiException('Aucune clé API Gemini. Ajoutez-la dans Réglages.');
    }
    final size = await video.length();
    final mime = mimeFor(video.path);
    Map<String, dynamic> videoPart;
    String? uploadedName;
    if (size <= inlineLimitBytes) {
      onProgress?.call('Préparation de la vidéo…');
      final b64 = base64Encode(await video.readAsBytes());
      videoPart = {
        'inline_data': {'mime_type': mime, 'data': b64},
      };
    } else {
      onProgress?.call('Envoi de la vidéo (${(size / 1048576).toStringAsFixed(1)} Mo)…');
      final file = await _uploadResumable(video, size, mime);
      uploadedName = file['name'] as String?;
      onProgress?.call('Traitement de la vidéo par Google…');
      final active = await _waitActive(file);
      videoPart = {
        'file_data': {'mime_type': mime, 'file_uri': active['uri']},
      };
    }
    videoPart['video_metadata'] = {'fps': fps};

    onProgress?.call('Analyse IA en cours…');
    try {
      return await _generate(videoPart, prompt);
    } finally {
      if (uploadedName != null) {
        // Suppression best-effort (sinon expiration automatique après 48 h).
        unawaited(_client
            .delete(Uri.parse('$base/v1beta/$uploadedName'), headers: _auth)
            .then((_) {}, onError: (_) {}));
      }
    }
  }

  Future<String> _generate(Map<String, dynamic> videoPart, String prompt) async {
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            videoPart,
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      },
    };
    final res = await _send(() => _client
        .post(
          Uri.parse('$base/v1beta/models/${Uri.encodeComponent(model)}:generateContent'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 5)));
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return extractText(j);
  }

  /// Texte d'une réponse generateContent (ignore les parties « thought »).
  static String extractText(Map<String, dynamic> j) {
    final cands = j['candidates'] as List?;
    if (cands == null || cands.isEmpty) {
      final reason = (j['promptFeedback'] as Map?)?['blockReason'];
      throw GeminiException(reason != null
          ? "Requête refusée par l'IA (motif : $reason)."
          : "Réponse vide de l'IA.");
    }
    final c = cands.first as Map;
    final parts = ((c['content'] as Map?)?['parts'] as List?) ?? [];
    final text = parts
        .whereType<Map>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) {
      throw GeminiException("Réponse vide de l'IA (motif : ${c['finishReason'] ?? 'inconnu'}).");
    }
    return text;
  }

  Future<Map<String, dynamic>> _uploadResumable(File video, int size, String mime) async {
    final start = await _send(() => _client.post(
          Uri.parse('$base/upload/v1beta/files'),
          headers: {
            ..._auth,
            'X-Goog-Upload-Protocol': 'resumable',
            'X-Goog-Upload-Command': 'start',
            'X-Goog-Upload-Header-Content-Length': '$size',
            'X-Goog-Upload-Header-Content-Type': mime,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'file': {'display_name': p.basename(video.path)}
          }),
        ));
    final uploadUrl = start.headers['x-goog-upload-url'];
    if (uploadUrl == null) {
      throw GeminiException("Envoi de la vidéo impossible (pas d'URL d'envoi).");
    }
    final req = http.StreamedRequest('POST', Uri.parse(uploadUrl))
      ..headers.addAll({
        'Content-Length': '$size',
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      })
      ..contentLength = size;
    video.openRead().listen(req.sink.add, onDone: req.sink.close, onError: req.sink.addError);
    final res = await _send(() async => http.Response.fromStream(
        await _client.send(req).timeout(const Duration(minutes: 10))));
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final file = j['file'] as Map<String, dynamic>?;
    if (file == null) throw GeminiException('Envoi de la vidéo : réponse inattendue.');
    return file;
  }

  Future<Map<String, dynamic>> _waitActive(Map<String, dynamic> file) async {
    var f = file;
    final name = f['name'] as String;
    for (var i = 0; i < 90; i++) {
      final state = f['state']?.toString() ?? 'ACTIVE';
      if (state == 'ACTIVE') return f;
      if (state == 'FAILED') throw GeminiException('Google n\'a pas pu traiter la vidéo (format non pris en charge ?).');
      await Future<void>.delayed(const Duration(seconds: 2));
      final res = await _send(() => _client.get(Uri.parse('$base/v1beta/$name'), headers: _auth));
      f = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    }
    throw GeminiException('Délai dépassé pendant le traitement de la vidéo par Google.');
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call();
    } on SocketException {
      throw GeminiException('Pas de connexion Internet. Le découpage manuel reste disponible.');
    } on TimeoutException {
      throw GeminiException("L'IA ne répond pas (délai dépassé). Réessayez avec une vidéo plus courte.");
    } on http.ClientException catch (e) {
      throw GeminiException('Erreur réseau : ${e.message}');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw errorFor(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  /// Traduit une erreur HTTP de l'API en message français.
  static GeminiException errorFor(int code, String body) {
    String apiMsg = '';
    String status = '';
    try {
      final e = (jsonDecode(body) as Map)['error'] as Map;
      apiMsg = e['message']?.toString() ?? '';
      status = e['status']?.toString() ?? '';
    } catch (_) {}
    final lower = apiMsg.toLowerCase();
    String msg;
    if (code == 429 || status == 'RESOURCE_EXHAUSTED') {
      msg = "Quota gratuit Gemini atteint (trop de requêtes ou de jetons). Patientez une minute ou réessayez demain ; "
          "en attendant, faites le découpage manuellement.";
    } else if (code == 400 && (lower.contains('api key') || lower.contains('api_key'))) {
      msg = 'Clé API Gemini invalide. Vérifiez-la dans Réglages.';
    } else if (code == 401 || code == 403) {
      msg = "Accès refusé par Gemini (clé invalide, API non activée ou région non autorisée).";
    } else if (code == 404) {
      msg = "Modèle IA introuvable. Choisissez un autre modèle dans Réglages.";
    } else if (code == 413) {
      msg = 'Vidéo trop volumineuse pour l\'IA. Filmez un extrait plus court.';
    } else if (code >= 500) {
      msg = "Le service Gemini est momentanément indisponible. Réessayez plus tard.";
    } else {
      msg = "Erreur de l'IA ($code).";
    }
    if (apiMsg.isNotEmpty && code != 429) msg = '$msg\nDétail : $apiMsg';
    return GeminiException(msg, statusCode: code);
  }
}
