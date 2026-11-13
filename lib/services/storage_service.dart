import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/motion.dart';
import '../models/study.dart';

/// Stockage local en fichiers JSON (aucun natif SQLite : marche
/// à l'identique sur Android et Windows, sans hook de compilation).
class StorageService {
  StorageService([this._baseOverride]);
  final Directory? _baseOverride;
  Directory? _base;

  Future<Directory> base() async {
    if (_base != null) return _base!;
    final root = _baseOverride ?? Directory(p.join((await getApplicationDocumentsDirectory()).path, 'TextileTimeStudy'));
    await Directory(p.join(root.path, 'etudes')).create(recursive: true);
    await Directory(p.join(root.path, 'videos')).create(recursive: true);
    await Directory(p.join(root.path, 'exports')).create(recursive: true);
    return _base = root;
  }

  Future<Directory> sub(String name) async => Directory(p.join((await base()).path, name));

  Future<File> _studyFile(String id) async => File(p.join((await sub('etudes')).path, '$id.json'));

  Future<void> saveStudy(Study s) async {
    s.updatedAt = DateTime.now();
    final f = await _studyFile(s.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(s.toJson()));
    await tmp.rename(f.path);
  }

  Future<List<Study>> listStudies() async {
    final dir = await sub('etudes');
    final out = <Study>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          out.add(Study.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
        } catch (_) {/* fichier corrompu ignoré */}
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> deleteStudy(Study s) async {
    final f = await _studyFile(s.id);
    if (await f.exists()) await f.delete();
    final v = s.videoPath;
    if (v != null && p.isWithin((await sub('videos')).path, v)) {
      final vf = File(v);
      if (await vf.exists()) await vf.delete();
    }
  }

  /// Copie la vidéo dans le dossier de l'appli (le cache du sélecteur peut être vidé).
  Future<String> importVideo(String sourcePath, String studyId) async {
    final ext = p.extension(sourcePath).isEmpty ? '.mp4' : p.extension(sourcePath);
    final dest = p.join((await sub('videos')).path, '$studyId-${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<List<Motion>> loadLibrary() async {
    final f = File(p.join((await base()).path, 'bibliotheque.json'));
    if (await f.exists()) {
      try {
        final l = (jsonDecode(await f.readAsString()) as List)
            .map((e) => Motion.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (l.isNotEmpty) {
          if (!l.any((m) => m.code == kOtherCode)) {
            l.add(defaultMotionLibrary().firstWhere((m) => m.code == kOtherCode));
          }
          return l;
        }
      } catch (_) {}
    }
    return defaultMotionLibrary();
  }

  Future<void> saveLibrary(List<Motion> lib) async {
    final f = File(p.join((await base()).path, 'bibliotheque.json'));
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(lib.map((m) => m.toJson()).toList()));
  }
}
