import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/motion.dart';
import '../models/study.dart';
import 'calculations.dart';
import 'format.dart';

/// CSV (séparateur « ; », virgule décimale, BOM UTF-8 pour Excel FR).
String buildCsv(Study study, StudyResult r) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('\uFEFF');
  b.writeln('Article;${q(study.article)}');
  b.writeln('Opération;${q(study.operation)}');
  b.writeln('Machine / point;${q(study.machine)}');
  b.writeln('Opératrice;${q(study.operatorName)}');
  b.writeln('Date;${frDate(study.date)}');
  b.writeln('Majoration %;${fr(study.allowance, 1)}');
  b.writeln('Cycles;${r.cycleCount}');
  b.writeln();
  b.writeln('N°;Code;Élément;Classe;VA;Observé moyen (s);Allure %;Normal (s);Standard (s);Cycles');
  for (final e in r.elements) {
    b.writeln([
      e.position,
      e.code,
      q(e.label),
      e.motionClass.label,
      e.valueAdded ? 'oui' : 'non',
      fr(e.observed, 2),
      fr(e.rating, 0),
      fr(e.normal, 2),
      fr(e.standard, 2),
      e.samples,
    ].join(';'));
  }
  b.writeln();
  b.writeln('Total observé (s);${fr(r.totalObserved, 2)}');
  b.writeln('Total normal (s);${fr(r.totalNormal, 2)}');
  b.writeln('Total standard (s);${fr(r.totalStandard, 2)}');
  b.writeln('SMV (min);${fr(r.smv, 4)}');
  b.writeln('Valeur ajoutée %;${fr(r.valueAddedPercent, 1)}');
  b.writeln('Pièces/heure à 100 %;${fr(r.piecesPerHour100, 1)}');
  b.writeln('Pièces/heure à ${fr(study.efficiency, 0)} %;${fr(r.piecesPerHourAtEfficiency, 1)}');
  b.writeln();
  b.writeln('Détail par cycle');
  b.writeln('Cycle;Code;Élément;Début (s);Fin (s);Mesuré (s);Édité (s);Allure %');
  final cycles = elementsByCycle(study.elements);
  for (final entry in cycles.entries) {
    for (final e in entry.value) {
      b.writeln([
        entry.key,
        e.code,
        q(e.label),
        fr(e.start, 2),
        fr(e.end, 2),
        fr(e.measured, 2),
        e.editedTime == null ? '' : fr(e.editedTime!, 2),
        e.rating ?? study.rating,
      ].join(';'));
    }
  }
  return b.toString();
}

/// Fiche opération (style « fiche de méthode ») au format PDF.
Future<Uint8List> buildPdf(Study study, StudyResult r, {required pw.Font regular, required pw.Font bold}) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: 'Fiche opération — ${study.title}',
    creator: 'Textile Time Study',
  );
  final header = PdfColor.fromInt(0xFF1F3A5F);
  pw.Widget kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(children: [
          pw.SizedBox(width: 95, child: pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v.isEmpty ? '—' : v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
        ]),
      );

  pw.Widget swatch(MotionClass c, String code) {
    return pw.Container(
      width: 8,
      height: 8,
      color: PdfColor.fromInt(c.defaultColor),
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      color: header,
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('FICHE OPÉRATION — ANALYSE DU TRAVAIL',
            style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.Text('SMV ${fr(r.smv, 4)} min', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
      ]),
    ),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Textile Time Study v0.1 — bibliothèque de mouvements maison', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          kv('Article', study.article),
          kv('Opération', study.operation),
          kv('Machine / point', study.machine),
        ])),
        pw.SizedBox(width: 12),
        pw.Expanded(
            child: pw.Column(children: [
          kv('Opératrice', study.operatorName),
          kv('Date', frDate(study.date)),
          kv('Cycles observés', '${r.cycleCount}'),
        ])),
      ]),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: pw.BoxDecoration(color: header),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignments: {
          0: pw.Alignment.center,
          1: pw.Alignment.center,
          4: pw.Alignment.center,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
          7: pw.Alignment.centerRight,
          8: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(22),
          1: const pw.FixedColumnWidth(30),
          2: const pw.FlexColumnWidth(4),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FixedColumnWidth(24),
          5: const pw.FixedColumnWidth(46),
          6: const pw.FixedColumnWidth(36),
          7: const pw.FixedColumnWidth(46),
          8: const pw.FixedColumnWidth(50),
        },
        headers: ['N°', 'Code', 'Élément', 'Classe', 'VA', 'Obs. (s)', 'Allure', 'Normal (s)', 'Standard (s)'],
        data: [
          for (final e in r.elements)
            [
              '${e.position}',
              e.code,
              e.label,
              e.motionClass.label,
              e.valueAdded ? 'oui' : '',
              fr(e.observed),
              '${fr(e.rating, 0)} %',
              fr(e.normal),
              fr(e.standard),
            ],
          ['', '', 'TOTAL', '', '', fr(r.totalObserved), '', fr(r.totalNormal), fr(r.totalStandard)],
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: header)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          kv('Majoration', '${fr(study.allowance, 1)} % (repos / besoins)'),
          kv('Temps standard', '${fr(r.totalStandard)} s'),
          kv('SMV / SAM', '${fr(r.smv, 4)} min'),
          kv('Valeur ajoutée', '${fr(r.valueAddedPercent, 1)} % du temps normal'),
          kv('Production / heure', '${fr(r.piecesPerHour100, 1)} pcs à 100 %  —  ${fr(r.piecesPerHourAtEfficiency, 1)} pcs à ${fr(study.efficiency, 0)} %'),
        ]),
      ),
      pw.SizedBox(height: 10),
      pw.Text('Répartition par classe (temps normal)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      ..._classBreakdown(r).entries.map((en) => pw.Row(children: [
            swatch(en.key, ''),
            pw.SizedBox(width: 4),
            pw.SizedBox(width: 90, child: pw.Text(en.key.label, style: const pw.TextStyle(fontSize: 8))),
            pw.Container(
              width: 250 * (r.totalNormal > 0 ? en.value / r.totalNormal : 0),
              height: 6,
              color: PdfColor.fromInt(en.key.defaultColor),
            ),
            pw.SizedBox(width: 4),
            pw.Text('${fr(en.value)} s', style: const pw.TextStyle(fontSize: 8)),
          ])),
      if (r.cycleMismatch)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('Attention : les cycles n\'ont pas tous le même nombre d\'éléments (moyenne par position).',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.red700)),
        ),
    ],
  ));
  return doc.save();
}

Map<MotionClass, double> _classBreakdown(StudyResult r) {
  final m = <MotionClass, double>{};
  for (final e in r.elements) {
    m[e.motionClass] = (m[e.motionClass] ?? 0) + e.normal;
  }
  return m;
}
