import 'package:flutter_test/flutter_test.dart';
import 'package:textile_time_study/services/element_editor.dart';

import 'helpers.dart';

void main() {
  final base = [el(0, 2, code: 'P1'), el(2, 8, code: 'CD'), el(8, 10, code: 'DP')];

  test('scinder à la position courante', () {
    final r = ElementEditor.splitAt(base, 5)!;
    expect(r.length, 4);
    expect(r[1].start, 2);
    expect(r[1].end, 5);
    expect(r[2].start, 5);
    expect(r[2].end, 8);
    expect(r[2].code, 'CD');
    expect(r[1].id, isNot(r[2].id));
    // la liste d'origine n'est pas modifiée
    expect(base[1].end, 8);
    expect(base.length, 3);
  });

  test('scinder trop près d\'un bord ou hors élément : refusé', () {
    expect(ElementEditor.splitAt(base, 2.01), isNull);
    expect(ElementEditor.splitAt(base, 12), isNull);
  });

  test('fusionner avec le suivant', () {
    final r = ElementEditor.mergeWithNext(base, 0)!;
    expect(r.length, 2);
    expect(r[0].start, 0);
    expect(r[0].end, 8);
    expect(r[0].code, 'P1');
    expect(ElementEditor.mergeWithNext(base, 2), isNull);
  });

  test('pas de fusion entre deux cycles', () {
    final l = [el(0, 2, cycle: 1), el(2, 4, cycle: 2)];
    expect(ElementEditor.mergeWithNext(l, 0), isNull);
  });

  test('ajuster début et fin garde la contiguïté', () {
    final a = ElementEditor.setStart(base, 1, 3)!;
    expect(a[1].start, 3);
    expect(a[0].end, 3);
    final b = ElementEditor.setEnd(base, 1, 7)!;
    expect(b[1].end, 7);
    expect(b[2].start, 7);
    expect(ElementEditor.setEnd(base, 1, 1.9), isNull);
    expect(ElementEditor.setStart(base, 1, 8), isNull);
  });

  test('supprimer', () {
    final r = ElementEditor.delete(base, 1)!;
    expect(r.map((e) => e.code), ['P1', 'DP']);
  });

  test('ajout manuel rogne les chevauchements', () {
    final r = ElementEditor.addManual(base, start: 1, end: 3, motion: m('AL'))!;
    expect(r.map((e) => e.code).toList(), ['P1', 'AL', 'CD', 'DP']);
    expect(r[0].end, 1);
    expect(r[2].start, 3);
    expect(r[2].end, 8);
  });

  test('ajout manuel dans un trou', () {
    final r = ElementEditor.addManual([el(0, 2)], start: 3, end: 4, motion: m('CF'))!;
    expect(r.length, 2);
    expect(r[1].code, 'CF');
    expect(r[1].cycle, 1);
  });

  test('nouveau cycle à partir d\'un élément', () {
    final r = ElementEditor.startNewCycleAt(base, 2)!;
    expect(r.map((e) => e.cycle).toList(), [1, 1, 2]);
    expect(ElementEditor.startNewCycleAt(r, 2), isNull);
    expect(ElementEditor.startNewCycleAt(base, 0), isNull);
  });

  test('renuméroter les cycles', () {
    final r = ElementEditor.renumberCycles([el(0, 1, cycle: 3), el(1, 2, cycle: 7), el(2, 3, cycle: 7)]);
    expect(r.map((e) => e.cycle).toList(), [1, 2, 2]);
  });
}
