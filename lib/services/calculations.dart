import 'dart:math' as math;

import '../models/motion.dart';
import '../models/study.dart';
import '../models/study_element.dart';

/// Ligne de résultat : un élément de la structure (position dans le cycle),
/// moyenné sur tous les cycles où il existe.
class ElementResult {
  ElementResult({
    required this.position,
    required this.code,
    required this.label,
    required this.motionClass,
    required this.valueAdded,
    required this.observed,
    required this.rating,
    required this.normal,
    required this.standard,
    required this.samples,
  });

  final int position; // 1..n
  final String code;
  final String label;
  final MotionClass motionClass;
  final bool valueAdded;

  /// Temps observé moyen (s).
  final double observed;

  /// Allure moyenne effective (%), = normal / observé × 100.
  final double rating;

  /// Temps normal moyen (s) = observé × allure / 100.
  final double normal;

  /// Temps standard (s) = normal × (1 + majoration).
  final double standard;

  /// Nombre de cycles ayant servi à la moyenne.
  final int samples;
}

class StudyResult {
  StudyResult({
    required this.elements,
    required this.cycleCount,
    required this.allowance,
    required this.efficiency,
    required this.cycleMismatch,
  });

  final List<ElementResult> elements;
  final int cycleCount;
  final double allowance;
  final double efficiency;

  /// Vrai si les cycles n'ont pas tous le même nombre d'éléments.
  final bool cycleMismatch;

  double get totalObserved => elements.fold(0.0, (s, e) => s + e.observed);
  double get totalNormal => elements.fold(0.0, (s, e) => s + e.normal);
  double get totalStandard => elements.fold(0.0, (s, e) => s + e.standard);

  /// SMV / SAM de l'opération en minutes, arrondi à 4 décimales.
  double get smv => round4(totalStandard / 60.0);

  /// Part du temps normal à valeur ajoutée (%).
  double get valueAddedPercent {
    final t = totalNormal;
    if (t <= 0) return 0;
    final va = elements.where((e) => e.valueAdded).fold(0.0, (s, e) => s + e.normal);
    return va / t * 100;
  }

  /// Production horaire théorique à 100 % (pièces / heure).
  double get piecesPerHour100 => smv > 0 ? 60.0 / smv : 0;

  /// Production horaire au rendement saisi.
  double get piecesPerHourAtEfficiency => piecesPerHour100 * efficiency / 100.0;
}

double round4(double v) => (v * 10000).roundToDouble() / 10000;

/// Temps normal d'un élément (s).
double normalTime(StudyElement e, int studyRating) => e.observed * (e.rating ?? studyRating) / 100.0;

/// Regroupe les éléments par cycle, triés par début.
Map<int, List<StudyElement>> elementsByCycle(List<StudyElement> elements) {
  final map = <int, List<StudyElement>>{};
  for (final e in elements) {
    map.putIfAbsent(e.cycle, () => []).add(e);
  }
  for (final l in map.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  final keys = map.keys.toList()..sort();
  return {for (final k in keys) k: map[k]!};
}

/// Calcule les temps de l'étude.
///
/// Si plusieurs cycles : la structure (codes, libellés) est celle du cycle le
/// plus long (en nombre d'éléments) et chaque élément est moyenné par position.
StudyResult computeStudy(Study study) {
  final cycles = elementsByCycle(study.elements);
  if (cycles.isEmpty) {
    return StudyResult(
        elements: [], cycleCount: 0, allowance: study.allowance, efficiency: study.efficiency, cycleMismatch: false);
  }
  final lists = cycles.values.toList();
  final maxLen = lists.map((l) => l.length).reduce(math.max);
  final reference = lists.firstWhere((l) => l.length == maxLen);
  final mismatch = lists.any((l) => l.length != maxLen);
  final k = 1 + study.allowance / 100.0;

  final results = <ElementResult>[];
  for (var i = 0; i < maxLen; i++) {
    final samples = [for (final l in lists) if (i < l.length) l[i]];
    final obs = samples.fold(0.0, (s, e) => s + e.observed) / samples.length;
    final norm = samples.fold(0.0, (s, e) => s + normalTime(e, study.rating)) / samples.length;
    final ref = reference[i];
    results.add(ElementResult(
      position: i + 1,
      code: ref.code,
      label: ref.label,
      motionClass: ref.motionClass,
      valueAdded: ref.valueAdded,
      observed: obs,
      rating: obs > 0 ? norm / obs * 100 : (ref.rating ?? study.rating).toDouble(),
      normal: norm,
      standard: norm * k,
      samples: samples.length,
    ));
  }
  return StudyResult(
    elements: results,
    cycleCount: lists.length,
    allowance: study.allowance,
    efficiency: study.efficiency,
    cycleMismatch: mismatch,
  );
}
