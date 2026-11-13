import 'package:flutter_test/flutter_test.dart';
import 'package:textile_time_study/models/motion.dart';
import 'package:textile_time_study/models/study.dart';
import 'package:textile_time_study/screens/results_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  testWidgets('écran Résultats affiche SMV et histogramme', (tester) async {
    final s = Study(operation: 'Montage col', elements: [el(0, 2, code: 'P1'), el(2, 8, code: 'CD')]);
    await tester.pumpWidget(MaterialApp(home: ResultsScreen(study: s, library: defaultMotionLibrary())));
    await tester.pumpAndSettle();
    expect(find.text('SMV (min)'), findsOneWidget);
    expect(find.text('0,1533'), findsOneWidget); // (8 s × 1,15) / 60
    expect(find.text('TOTAL'), findsOneWidget);
  });
}
