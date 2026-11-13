import 'package:flutter_test/flutter_test.dart';
import 'package:textile_time_study/models/study.dart';
import 'package:textile_time_study/services/calculations.dart';

import 'helpers.dart';

void main() {
  test('un cycle : normal, standard, SMV, %VA, production', () {
    final s = Study(rating: 100, allowance: 15, efficiency: 80, elements: [
      el(0, 2, code: 'P1'), // 2 s NVA
      el(2, 8, code: 'CD'), // 6 s VA
      el(8, 10, code: 'DP'), // 2 s NVA
    ]);
    final r = computeStudy(s);
    expect(r.elements.length, 3);
    expect(r.totalNormal, closeTo(10, 1e-9));
    expect(r.totalStandard, closeTo(11.5, 1e-9));
    expect(r.smv, 0.1917); // 11.5 / 60 = 0.191666…
    expect(r.valueAddedPercent, closeTo(60, 1e-9));
    expect(r.piecesPerHour100, closeTo(60 / 0.1917, 1e-9));
    expect(r.piecesPerHourAtEfficiency, closeTo(60 / 0.1917 * 0.8, 1e-9));
  });

  test('allure par élément et temps édité', () {
    final s = Study(rating: 100, allowance: 0, elements: [
      el(0, 4, code: 'CD', rating: 120), // 4 × 1.2 = 4.8
      el(4, 10, code: 'DP', edited: 3), // édité 3 s × 1.0
    ]);
    final r = computeStudy(s);
    expect(r.elements[0].normal, closeTo(4.8, 1e-9));
    expect(r.elements[0].rating, closeTo(120, 1e-9));
    expect(r.elements[1].observed, 3);
    expect(r.totalNormal, closeTo(7.8, 1e-9));
  });

  test('allure globale appliquée', () {
    final s = Study(rating: 90, allowance: 10, elements: [el(0, 10)]);
    final r = computeStudy(s);
    expect(r.totalNormal, closeTo(9, 1e-9));
    expect(r.totalStandard, closeTo(9.9, 1e-9));
    expect(r.smv, 0.165);
  });

  test('plusieurs cycles : moyenne par position', () {
    final s = Study(allowance: 0, elements: [
      el(0, 2, code: 'P1', cycle: 1),
      el(2, 6, code: 'CD', cycle: 1),
      el(6, 9, code: 'P1', cycle: 2),
      el(9, 15, code: 'CD', cycle: 2),
    ]);
    final r = computeStudy(s);
    expect(r.cycleCount, 2);
    expect(r.cycleMismatch, isFalse);
    expect(r.elements[0].observed, closeTo(2.5, 1e-9));
    expect(r.elements[1].observed, closeTo(5, 1e-9));
    expect(r.elements[1].samples, 2);
    expect(r.smv, round4(7.5 / 60));
  });

  test('cycles inégaux signalés', () {
    final s = Study(elements: [
      el(0, 2, cycle: 1),
      el(2, 4, cycle: 2),
      el(4, 5, code: 'CF', cycle: 2),
    ]);
    final r = computeStudy(s);
    expect(r.cycleMismatch, isTrue);
    expect(r.elements.length, 2);
    expect(r.elements[1].samples, 1);
    expect(r.elements[1].code, 'CF');
  });

  test('étude vide', () {
    final r = computeStudy(Study());
    expect(r.smv, 0);
    expect(r.piecesPerHour100, 0);
    expect(r.valueAddedPercent, 0);
  });
}
