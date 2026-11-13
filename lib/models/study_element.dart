import 'package:uuid/uuid.dart';

import 'motion.dart';

const _uuid = Uuid();

/// Un élément de travail repéré dans la vidéo (temps en secondes vidéo).
class StudyElement {
  StudyElement({
    String? id,
    required this.cycle,
    required this.start,
    required this.end,
    required this.code,
    required this.label,
    required this.motionClass,
    required this.valueAdded,
    this.rating,
    this.editedTime,
    this.confidence,
    this.fromAi = false,
  }) : id = id ?? _uuid.v4();

  final String id;
  int cycle;
  double start;
  double end;
  String code;
  String label;
  MotionClass motionClass;
  bool valueAdded;

  /// Jugement d'allure propre à l'élément (%) ; null = allure de l'étude.
  int? rating;

  /// Temps édité manuellement (s) ; null = temps mesuré (fin - début).
  double? editedTime;

  /// Confiance renvoyée par l'IA (0..1), null si saisi à la main.
  double? confidence;
  bool fromAi;

  double get measured => end - start;
  double get observed => editedTime ?? measured;

  void applyMotion(Motion m, {bool keepLabel = false}) {
    code = m.code;
    if (!keepLabel) label = m.label;
    motionClass = m.motionClass;
    valueAdded = m.valueAdded;
  }

  StudyElement copyWith({String? id, int? cycle, double? start, double? end}) => StudyElement(
        id: id ?? this.id,
        cycle: cycle ?? this.cycle,
        start: start ?? this.start,
        end: end ?? this.end,
        code: code,
        label: label,
        motionClass: motionClass,
        valueAdded: valueAdded,
        rating: rating,
        editedTime: editedTime,
        confidence: confidence,
        fromAi: fromAi,
      );

  /// Copie avec un nouvel identifiant (utilisé quand on scinde).
  StudyElement duplicate() => copyWith(id: _uuid.v4());

  Map<String, dynamic> toJson() => {
        'id': id,
        'cycle': cycle,
        'start': start,
        'end': end,
        'code': code,
        'label': label,
        'class': motionClass.name,
        'va': valueAdded,
        'rating': rating,
        'edited': editedTime,
        'confidence': confidence,
        'ai': fromAi,
      };

  factory StudyElement.fromJson(Map<String, dynamic> j) => StudyElement(
        id: j['id'] as String?,
        cycle: (j['cycle'] as num?)?.toInt() ?? 1,
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
        code: j['code'] as String? ?? kOtherCode,
        label: j['label'] as String? ?? '',
        motionClass: MotionClass.parse(j['class']),
        valueAdded: j['va'] == true,
        rating: (j['rating'] as num?)?.toInt(),
        editedTime: (j['edited'] as num?)?.toDouble(),
        confidence: (j['confidence'] as num?)?.toDouble(),
        fromAi: j['ai'] == true,
      );
}
