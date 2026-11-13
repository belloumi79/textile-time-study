import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:textile_time_study/models/study.dart';
import 'package:textile_time_study/services/calculations.dart';
import 'package:textile_time_study/services/export_service.dart';
import 'package:textile_time_study/services/storage_service.dart';

import 'helpers.dart';

Study sample() => Study(
      article: 'Polo « été »',
      operation: 'Montage col',
      machine: 'Piqueuse 301',
      operatorName: 'Fatma',
      elements: [el(0, 2, code: 'P1'), el(2, 8, code: 'CD'), el(8, 10, code: 'DP')],
    );

void main() {
  test('CSV : séparateur ; et virgule décimale, SMV 4 décimales', () {
    final s = sample();
    final csv = buildCsv(s, computeStudy(s));
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('SMV (min);0,1917'));
    expect(csv, contains('"Polo « été »"'));
    expect(csv, contains('2;CD;"Coudre droit";Couture;oui;6,00'));
  });

  test('PDF généré avec police DejaVu (accents)', () async {
    final regular = pw.Font.ttf(File('assets/fonts/DejaVuSans.ttf').readAsBytesSync().buffer.asByteData());
    final bold = pw.Font.ttf(File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytesSync().buffer.asByteData());
    final s = sample();
    final bytes = await buildPdf(s, computeStudy(s), regular: regular, bold: bold);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('stockage JSON : enregistrer, relire, bibliothèque', () async {
    final dir = await Directory.systemTemp.createTemp('tts_store');
    final st = StorageService(dir);
    final s = sample();
    await st.saveStudy(s);
    final l = await st.listStudies();
    expect(l.length, 1);
    expect(l.first.operation, 'Montage col');
    expect(l.first.elements.length, 3);
    expect(l.first.elements[1].code, 'CD');
    final libr = await st.loadLibrary();
    expect(libr.any((x) => x.code == 'AU'), isTrue);
    libr.removeWhere((x) => x.code == 'CT');
    await st.saveLibrary(libr);
    expect((await st.loadLibrary()).any((x) => x.code == 'CT'), isFalse);
    await st.deleteStudy(s);
    expect(await st.listStudies(), isEmpty);
    await dir.delete(recursive: true);
  });
}
