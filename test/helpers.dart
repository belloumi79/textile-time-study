import 'package:textile_time_study/models/motion.dart';
import 'package:textile_time_study/models/study_element.dart';

final lib = defaultMotionLibrary();
Motion m(String code) => lib.firstWhere((x) => x.code == code);

StudyElement el(double s, double e, {String code = 'CD', int cycle = 1, int? rating, double? edited}) {
  final mo = m(code);
  return StudyElement(
    cycle: cycle,
    start: s,
    end: e,
    code: mo.code,
    label: mo.label,
    motionClass: mo.motionClass,
    valueAdded: mo.valueAdded,
    rating: rating,
    editedTime: edited,
  );
}
