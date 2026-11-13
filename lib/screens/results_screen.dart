import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/motion.dart';
import '../models/study.dart';
import '../services/app_services.dart';
import '../services/calculations.dart';
import '../services/export_service.dart';
import '../services/format.dart';
import '../widgets/element_chart.dart';
import '../widgets/motion_colors.dart';

/// Résultats : SMV, % VA, production horaire, histogramme, export PDF / CSV.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.study, required this.library});
  final Study study;
  final List<Motion> library;

  String get _fileBase {
    final raw = '${study.operation}_${study.article}'.trim();
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_').replaceAll(RegExp(r'_+'), '_');
    return 'fiche_${safe.isEmpty || safe == '_' ? study.id.substring(0, 8) : safe}';
  }

  Future<void> _pdf(BuildContext context, StudyResult r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
      final bytes = await buildPdf(study, r, regular: regular, bold: bold);
      final dir = await storage.sub('exports');
      final f = File(p.join(dir.path, '$_fileBase.pdf'));
      await f.writeAsBytes(bytes);
      await Printing.sharePdf(bytes: bytes, filename: '$_fileBase.pdf');
      messenger.showSnackBar(SnackBar(content: Text('PDF enregistré : ${f.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export PDF impossible : $e')));
    }
  }

  Future<void> _print(BuildContext context, StudyResult r) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    await Printing.layoutPdf(name: _fileBase, onLayout: (_) => buildPdf(study, r, regular: regular, bold: bold));
  }

  Future<void> _csv(BuildContext context, StudyResult r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await storage.sub('exports');
      final f = File(p.join(dir.path, '$_fileBase.csv'));
      await f.writeAsString(buildCsv(study, r));
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: study.title));
      }
      messenger.showSnackBar(SnackBar(content: Text('CSV enregistré : ${f.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export CSV impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = computeStudy(study);
    Widget tile(String label, String value, {Color? color}) => Card(
          color: color,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Résultats'), actions: [
        IconButton(tooltip: 'Imprimer / aperçu', icon: const Icon(Icons.print), onPressed: r.elements.isEmpty ? null : () => _print(context, r)),
        IconButton(tooltip: 'Exporter PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: r.elements.isEmpty ? null : () => _pdf(context, r)),
        IconButton(tooltip: 'Exporter CSV', icon: const Icon(Icons.table_view), onPressed: r.elements.isEmpty ? null : () => _csv(context, r)),
      ]),
      body: r.elements.isEmpty
          ? const Center(child: Text('Aucun élément : découpez la vidéo avant de voir les résultats.'))
          : ListView(padding: const EdgeInsets.all(12), children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                tile('SMV (min)', fr(r.smv, 4), color: const Color(0xFFE3F2FD)),
                tile('Valeur ajoutée', '${fr(r.valueAddedPercent, 1)} %', color: const Color(0xFFE8F5E9)),
                tile('Pièces / h à 100 %', fr(r.piecesPerHour100, 1)),
                tile('Pièces / h à ${fr(study.efficiency, 0)} %', fr(r.piecesPerHourAtEfficiency, 1)),
                tile('Cycles', '${r.cycleCount}'),
              ]),
              const SizedBox(height: 8),
              Text(
                'Temps standard = normal × (1 + ${fr(study.allowance, 1)} %) · total ${fr(r.totalStandard)} s'
                '${study.aiModel == null ? '' : ' · découpage proposé par ${study.aiModel}'}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (r.cycleMismatch)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    "⚠ Les cycles n'ont pas tous le même nombre d'éléments : moyenne faite par position. "
                    'Harmonisez le découpage pour un résultat fiable.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 12),
              Text('Temps standard par élément (s)', style: Theme.of(context).textTheme.titleSmall),
              SizedBox(
                height: 220,
                child: ElementChart(bars: [
                  for (final e in r.elements)
                    ChartBar(
                      label: '${e.code} ${e.label}',
                      value: e.standard,
                      color: motionColor(e.code, e.motionClass, library),
                      tooltip: e.motionClass.label,
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 36,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('N°')),
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Élément')),
                    DataColumn(label: Text('Classe')),
                    DataColumn(label: Text('VA')),
                    DataColumn(label: Text('Obs. moy.'), numeric: true),
                    DataColumn(label: Text('Allure'), numeric: true),
                    DataColumn(label: Text('Normal'), numeric: true),
                    DataColumn(label: Text('Standard'), numeric: true),
                    DataColumn(label: Text('n'), numeric: true),
                  ],
                  rows: [
                    for (final e in r.elements)
                      DataRow(cells: [
                        DataCell(Container(
                          width: 26,
                          alignment: Alignment.center,
                          color: motionColor(e.code, e.motionClass, library),
                          child: Text('${e.position}'),
                        )),
                        DataCell(Text(e.code)),
                        DataCell(SizedBox(width: 220, child: Text(e.label, overflow: TextOverflow.ellipsis))),
                        DataCell(Text(e.motionClass.label)),
                        DataCell(Icon(e.valueAdded ? Icons.check_box : Icons.check_box_outline_blank, size: 18)),
                        DataCell(Text(fr(e.observed))),
                        DataCell(Text('${fr(e.rating, 0)} %')),
                        DataCell(Text(fr(e.normal))),
                        DataCell(Text(fr(e.standard), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text('${e.samples}')),
                      ]),
                    DataRow(color: WidgetStateProperty.all(const Color(0xFFDDE6F0)), cells: [
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                      const DataCell(Text('')),
                      DataCell(Text(fr(r.totalObserved))),
                      const DataCell(Text('')),
                      DataCell(Text(fr(r.totalNormal))),
                      DataCell(Text(fr(r.totalStandard), style: const TextStyle(fontWeight: FontWeight.bold))),
                      const DataCell(Text('')),
                    ]),
                  ],
                ),
              ),
            ]),
    );
  }
}
