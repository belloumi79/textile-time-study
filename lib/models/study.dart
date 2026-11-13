import 'package:uuid/uuid.dart';

import 'study_element.dart';

/// Une étude de temps (une opération filmée).
class Study {
  Study({
    String? id,
    this.article = '',
    this.operation = '',
    this.machine = '',
    this.operatorName = '',
    DateTime? date,
    this.rating = 100,
    this.allowance = 15,
    this.efficiency = 80,
    this.videoPath,
    List<StudyElement>? elements,
    this.aiModel,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? DateTime.now(),
        elements = elements ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String article;
  String operation;

  /// Machine / type de point (ex. « Piqueuse plate 301 »).
  String machine;
  String operatorName;
  DateTime date;

  /// Jugement d'allure global (%), défaut 100.
  int rating;

  /// Majoration repos / besoins personnels (%), défaut 15.
  double allowance;

  /// Rendement saisi (%) pour la production horaire réaliste.
  double efficiency;
  String? videoPath;
  List<StudyElement> elements;
  String? aiModel;
  DateTime updatedAt;

  String get title {
    final parts = [operation, article].where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Étude sans titre' : parts.join(' — ');
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'article': article,
        'operation': operation,
        'machine': machine,
        'operator': operatorName,
        'date': date.toIso8601String(),
        'rating': rating,
        'allowance': allowance,
        'efficiency': efficiency,
        'video': videoPath,
        'aiModel': aiModel,
        'updatedAt': updatedAt.toIso8601String(),
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory Study.fromJson(Map<String, dynamic> j) => Study(
        id: j['id'] as String?,
        article: j['article'] as String? ?? '',
        operation: j['operation'] as String? ?? '',
        machine: j['machine'] as String? ?? '',
        operatorName: j['operator'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? ''),
        rating: (j['rating'] as num?)?.toInt() ?? 100,
        allowance: (j['allowance'] as num?)?.toDouble() ?? 15,
        efficiency: (j['efficiency'] as num?)?.toDouble() ?? 80,
        videoPath: j['video'] as String?,
        aiModel: j['aiModel'] as String?,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        elements: ((j['elements'] as List?) ?? [])
            .map((e) => StudyElement.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
