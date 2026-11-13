import 'dart:convert';

import '../models/motion.dart';
import '../models/study_element.dart';
import 'element_editor.dart';

/// Construit le prompt envoyé à l'IA, avec la bibliothèque de mouvements.
String buildSegmentationPrompt({
  required List<Motion> library,
  String operation = '',
  String machine = '',
}) {
  final lines = library
      .map((m) => '${m.code} | ${m.label} | ${m.motionClass.label} | VA=${m.valueAdded ? 'oui' : 'non'}'
          '${m.description.isEmpty ? '' : ' | ${m.description}'}')
      .join('\n');
  final classes = MotionClass.values.map((c) => c.label).join(', ');
  return '''
Tu es un ingénieur méthodes en confection (habillement). La vidéo montre une opératrice
qui réalise une opération de couture${operation.isNotEmpty ? ' : « $operation »' : ''}${machine.isNotEmpty ? ' sur « $machine »' : ''}.

Tâche : découper la vidéo en ÉLÉMENTS DE TRAVAIL successifs (analyse du travail / chronométrage).
1. Repère les CYCLES (une pièce ou un paquet traité du début à la fin). S'il n'y a qu'un cycle, renvoie-en un seul.
2. Dans chaque cycle, découpe en éléments contigus, chacun correspondant à UN mouvement de la bibliothèque ci-dessous.
3. Utilise UNIQUEMENT les codes de la bibliothèque. Si aucun ne convient, utilise le code "$kOtherCode" et décris le geste dans "libelle".
4. Les temps sont en secondes depuis le début de la vidéo (décimales autorisées, précision 0,1 s visée).
   Les éléments ne doivent pas se chevaucher et doivent être dans l'ordre chronologique.
5. "confiance" entre 0 et 1 selon ta certitude.

Bibliothèque (CODE | libellé | classe | valeur ajoutée) :
$lines

Classes possibles : $classes.

Réponds UNIQUEMENT avec un JSON strict, sans texte autour, de la forme :
{"cycles":[{"cycle":1,"start_s":0.0,"end_s":12.4,"elements":[
  {"start_s":0.0,"end_s":1.2,"code":"P1","libelle":"Prendre pièce (1 main)","classe":"Prise","valeur_ajoutee":false,"confiance":0.8}
]}]}
''';
}

class NormalizedSegmentation {
  NormalizedSegmentation(this.elements, this.warnings);
  final List<StudyElement> elements;
  final List<String> warnings;
}

class AiFormatException implements Exception {
  AiFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Extrait l'objet JSON d'une réponse (supporte les blocs ```json …```).
Object? extractJson(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  try {
    return jsonDecode(s);
  } catch (_) {
    // Dernier recours : du premier { ou [ au dernier } ou ].
    final a = s.indexOf(RegExp(r'[\{\[]'));
    final b = s.lastIndexOf(RegExp(r'[\}\]]'));
    if (a >= 0 && b > a) {
      try {
        return jsonDecode(s.substring(a, b + 1));
      } catch (_) {}
    }
  }
  throw AiFormatException("La réponse de l'IA n'est pas un JSON valide.");
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim().replaceAll(',', '.');
    // Accepte « mm:ss.s »
    final mm = RegExp(r'^(\d+):(\d+(?:\.\d+)?)$').firstMatch(s);
    if (mm != null) return int.parse(mm.group(1)!) * 60 + double.parse(mm.group(2)!);
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  }
  return null;
}

bool? _bool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (['oui', 'yes', 'true', 'vrai', 'va', '1'].contains(s)) return true;
    if (['non', 'no', 'false', 'faux', 'nva', '0'].contains(s)) return false;
  }
  return null;
}

/// Valide et normalise la réponse de l'IA :
/// - accepte {"cycles":[{elements:[…]}]}, {"elements":[…]} ou une liste ;
/// - temps numériques, croissants, sans chevauchement, bornés à la durée ;
/// - codes inconnus remplacés par « Autre » ; classe/VA pris dans la bibliothèque ;
/// - cycles renumérotés 1..n.
NormalizedSegmentation normalizeAiSegmentation(
  Object? json, {
  required List<Motion> library,
  double? videoDuration,
}) {
  final warnings = <String>[];
  final byCode = {for (final m in library) m.code.toUpperCase(): m};
  final other = byCode[kOtherCode] ??
      Motion(code: kOtherCode, label: 'Autre', motionClass: MotionClass.autre, valueAdded: false);

  // 1. Mise à plat : liste de (cycle, map élément).
  final raw = <(int, Map)>[];
  void addElements(List list, int cycle) {
    for (final e in list) {
      if (e is Map) {
        final c = (_num(e['cycle']) ?? cycle.toDouble()).round();
        raw.add((c, e));
      }
    }
  }

  if (json is Map && json['cycles'] is List) {
    var n = 0;
    for (final c in json['cycles'] as List) {
      n++;
      if (c is Map && c['elements'] is List) {
        addElements(c['elements'] as List, (_num(c['cycle']) ?? n.toDouble()).round());
      }
    }
  } else if (json is Map && json['elements'] is List) {
    addElements(json['elements'] as List, 1);
  } else if (json is List) {
    addElements(json, 1);
  } else {
    throw AiFormatException("Structure JSON inattendue (ni « cycles » ni « elements »).");
  }

  // 2. Conversion + filtrage.
  var elements = <StudyElement>[];
  var dropped = 0, unknown = 0, clamped = 0;
  for (final (cycle, m) in raw) {
    var s = _num(m['start_s'] ?? m['start'] ?? m['debut']);
    var e = _num(m['end_s'] ?? m['end'] ?? m['fin']);
    if (s == null || e == null || s.isNaN || e.isNaN) {
      dropped++;
      continue;
    }
    if (s < 0) s = 0;
    if (videoDuration != null && videoDuration > 0) {
      if (s >= videoDuration) {
        dropped++;
        continue;
      }
      if (e > videoDuration) {
        e = videoDuration;
        clamped++;
      }
    }
    if (e - s < ElementEditor.minDuration) {
      dropped++;
      continue;
    }
    final codeRaw = (m['code'] ?? '').toString().trim().toUpperCase();
    var motion = byCode[codeRaw];
    if (motion == null) {
      unknown++;
      motion = other;
    }
    final aiLabel = (m['libelle'] ?? m['label'] ?? m['nom'] ?? '').toString().trim();
    final conf = _num(m['confiance'] ?? m['confidence']);
    final known = motion.code != kOtherCode;
    elements.add(StudyElement(
      cycle: cycle < 1 ? 1 : cycle,
      start: s,
      end: e,
      code: motion.code,
      // Code connu : libellé de la bibliothèque ; sinon on garde la description IA.
      label: known ? motion.label : (aiLabel.isEmpty ? motion.label : aiLabel),
      motionClass: known ? motion.motionClass : MotionClass.parse(m['classe'] ?? m['class']),
      valueAdded: known ? motion.valueAdded : (_bool(m['valeur_ajoutee'] ?? m['va']) ?? false),
      confidence: conf?.clamp(0.0, 1.0).toDouble(),
      fromAi: true,
    ));
  }

  // 3. Tri + suppression des chevauchements.
  elements.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));
  final out = <StudyElement>[];
  var overlaps = 0;
  for (final el in elements) {
    if (out.isNotEmpty) {
      final prev = out.last;
      if (el.start < prev.end) {
        overlaps++;
        el.start = prev.end;
        if (el.end - el.start < ElementEditor.minDuration) {
          dropped++;
          continue;
        }
      }
      // Un cycle ne peut pas revenir en arrière dans le temps.
      if (el.cycle < prev.cycle) el.cycle = prev.cycle;
    }
    out.add(el);
  }
  elements = ElementEditor.renumberCycles(out);

  if (elements.isEmpty) {
    throw AiFormatException("L'IA n'a renvoyé aucun élément exploitable.");
  }
  if (unknown > 0) warnings.add('$unknown code(s) inconnu(s) remplacé(s) par « Autre ».');
  if (overlaps > 0) warnings.add('$overlaps chevauchement(s) corrigé(s).');
  if (dropped > 0) warnings.add('$dropped élément(s) invalide(s) ignoré(s).');
  if (clamped > 0) warnings.add('$clamped fin(s) ramenée(s) à la durée de la vidéo.');
  return NormalizedSegmentation(elements, warnings);
}
