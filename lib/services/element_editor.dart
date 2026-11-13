import '../models/motion.dart';
import '../models/study_element.dart';

/// Opérations pures d'édition du découpage (testables sans interface).
/// Toutes renvoient une NOUVELLE liste triée par début ; la liste d'entrée
/// n'est pas modifiée (les éléments touchés sont copiés).
class ElementEditor {
  static const double minDuration = 0.05; // s

  static List<StudyElement> sorted(List<StudyElement> l) =>
      [...l]..sort((a, b) => a.start.compareTo(b.start));

  static List<StudyElement> _clone(List<StudyElement> l) => sorted(l.map((e) => e.copyWith()).toList());

  /// Index de l'élément qui contient le temps [t] (début inclus, fin exclue).
  static int indexAt(List<StudyElement> l, double t) {
    for (var i = 0; i < l.length; i++) {
      if (t >= l[i].start && t < l[i].end) return i;
    }
    return -1;
  }

  /// Scinde l'élément qui contient [t] en deux à la position [t].
  /// Renvoie null si aucun élément ne contient t ou si un morceau serait trop court.
  static List<StudyElement>? splitAt(List<StudyElement> list, double t) {
    final l = _clone(list);
    final i = indexAt(l, t);
    if (i < 0) return null;
    final e = l[i];
    if (t - e.start < minDuration || e.end - t < minDuration) return null;
    final second = e.duplicate()
      ..start = t
      ..editedTime = null;
    e
      ..end = t
      ..editedTime = null;
    l.insert(i + 1, second);
    return l;
  }

  /// Fusionne l'élément [index] avec le suivant (même cycle obligatoire).
  static List<StudyElement>? mergeWithNext(List<StudyElement> list, int index) {
    final l = _clone(list);
    if (index < 0 || index >= l.length - 1) return null;
    final a = l[index], b = l[index + 1];
    if (a.cycle != b.cycle) return null;
    a
      ..end = b.end
      ..editedTime = null;
    l.removeAt(index + 1);
    return l;
  }

  /// Fixe le début de l'élément [index] à [t]. Le précédent (s'il chevauche
  /// ou était contigu) voit sa fin ajustée.
  static List<StudyElement>? setStart(List<StudyElement> list, int index, double t) {
    final l = _clone(list);
    if (index < 0 || index >= l.length) return null;
    final e = l[index];
    if (e.end - t < minDuration || t < 0) return null;
    if (index > 0) {
      final p = l[index - 1];
      final contiguous = (p.end - e.start).abs() < 1e-6;
      if (t <= p.start + minDuration) return null;
      if (p.end > t || contiguous) p.end = t;
    }
    e
      ..start = t
      ..editedTime = null;
    return l;
  }

  /// Fixe la fin de l'élément [index] à [t]. Le suivant (s'il chevauche ou
  /// était contigu) voit son début ajusté.
  static List<StudyElement>? setEnd(List<StudyElement> list, int index, double t) {
    final l = _clone(list);
    if (index < 0 || index >= l.length) return null;
    final e = l[index];
    if (t - e.start < minDuration) return null;
    if (index < l.length - 1) {
      final n = l[index + 1];
      final contiguous = (n.start - e.end).abs() < 1e-6;
      if (t >= n.end - minDuration) return null;
      if (n.start < t || contiguous) n.start = t;
    }
    e
      ..end = t
      ..editedTime = null;
    return l;
  }

  static List<StudyElement>? delete(List<StudyElement> list, int index) {
    final l = _clone(list);
    if (index < 0 || index >= l.length) return null;
    l.removeAt(index);
    return l;
  }

  /// Ajoute un élément saisi à la main entre [start] et [end].
  /// Les éléments existants qui chevauchent sont rognés.
  static List<StudyElement>? addManual(
    List<StudyElement> list, {
    required double start,
    required double end,
    required Motion motion,
    int? cycle,
  }) {
    if (end - start < minDuration || start < 0) return null;
    var l = _clone(list);
    final c = cycle ?? _cycleNear(l, start);
    final out = <StudyElement>[];
    for (final e in l) {
      if (e.end <= start || e.start >= end) {
        out.add(e);
        continue;
      }
      // Chevauchement : on garde les morceaux hors de [start, end].
      if (e.start < start && start - e.start >= minDuration) {
        out.add(e.copyWith(end: start)..editedTime = null);
      }
      if (e.end > end && e.end - end >= minDuration) {
        out.add(e.duplicate()
          ..start = end
          ..editedTime = null);
      }
    }
    out.add(StudyElement(
      cycle: c,
      start: start,
      end: end,
      code: motion.code,
      label: motion.label,
      motionClass: motion.motionClass,
      valueAdded: motion.valueAdded,
    ));
    l = sorted(out);
    return l;
  }

  static int _cycleNear(List<StudyElement> l, double t) {
    StudyElement? prev;
    for (final e in l) {
      if (e.start <= t) prev = e;
    }
    return prev?.cycle ?? (l.isEmpty ? 1 : l.first.cycle);
  }

  /// Fait commencer un nouveau cycle à l'élément [index] : cet élément et
  /// tous les suivants passent au cycle +1.
  static List<StudyElement>? startNewCycleAt(List<StudyElement> list, int index) {
    final l = _clone(list);
    if (index <= 0 || index >= l.length) return null;
    if (l[index].cycle != l[index - 1].cycle) return null; // déjà un début de cycle
    for (var i = index; i < l.length; i++) {
      l[i].cycle += 1;
    }
    return l;
  }

  /// Renumérote les cycles 1..n dans l'ordre chronologique.
  static List<StudyElement> renumberCycles(List<StudyElement> list) {
    final l = _clone(list);
    final map = <int, int>{};
    for (final e in l) {
      map.putIfAbsent(e.cycle, () => map.length + 1);
      e.cycle = map[e.cycle]!;
    }
    return l;
  }
}
