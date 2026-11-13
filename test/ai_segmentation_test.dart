import 'package:flutter_test/flutter_test.dart';
import 'package:textile_time_study/models/motion.dart';
import 'package:textile_time_study/services/ai_segmentation.dart';

import 'helpers.dart';

void main() {
  test('prompt contient la bibliothèque et le format JSON', () {
    final p = buildSegmentationPrompt(library: lib, operation: 'Montage col', machine: 'Piqueuse 301');
    expect(p, contains('CD | Coudre droit | Couture | VA=oui'));
    expect(p, contains('Montage col'));
    expect(p, contains('"start_s"'));
  });

  test('extrait le JSON d\'un bloc ```json', () {
    final j = extractJson('Voici :\n```json\n{"elements":[]}\n```\n');
    expect(j, isA<Map>());
    expect(() => extractJson('pas de json'), throwsA(isA<AiFormatException>()));
  });

  test('normalise cycles, codes inconnus, chevauchements, durée', () {
    final json = extractJson('''
    {"cycles":[
      {"cycle":1,"elements":[
        {"start_s":0,"end_s":1.5,"code":"p1","libelle":"x","classe":"Prise","valeur_ajoutee":false,"confiance":0.9},
        {"start_s":1.4,"end_s":6,"code":"CD","confiance":1.7},
        {"start_s":"6,0","end_s":"6.5","code":"ZZ9","libelle":"Souffler la pièce","classe":"Contrôle","valeur_ajoutee":"non"}
      ]},
      {"cycle":5,"elements":[
        {"start_s":7,"end_s":8,"code":"P1"},
        {"start_s":8,"end_s":30,"code":"CC"},
        {"start_s":40,"end_s":45,"code":"DP"},
        {"start_s":9,"end_s":"abc","code":"DP"}
      ]}
    ]}''');
    final r = normalizeAiSegmentation(json, library: lib, videoDuration: 20);
    final e = r.elements;
    expect(e.map((x) => x.code).toList(), ['P1', 'CD', kOtherCode, 'P1', 'CC']);
    // code connu en minuscules reconnu, libellé de la bibliothèque
    expect(e[0].label, m('P1').label);
    // chevauchement corrigé
    expect(e[1].start, 1.5);
    // confiance bornée
    expect(e[1].confidence, 1.0);
    // inconnu -> Autre avec description IA et classe IA
    expect(e[2].label, 'Souffler la pièce');
    expect(e[2].motionClass, MotionClass.controle);
    expect(e[2].valueAdded, isFalse);
    // cycles renumérotés 1..2
    expect(e.map((x) => x.cycle).toList(), [1, 1, 1, 2, 2]);
    // fin bornée à la durée de la vidéo
    expect(e[4].end, 20);
    // ordre croissant, pas de chevauchement
    for (var i = 1; i < e.length; i++) {
      expect(e[i].start >= e[i - 1].end, isTrue);
    }
    expect(r.warnings.join(' '), contains('inconnu'));
    expect(r.warnings.join(' '), contains('ignoré'));
  });

  test('accepte une liste plate et trie', () {
    final r = normalizeAiSegmentation([
      {'start_s': 5, 'end_s': 6, 'code': 'DP'},
      {'start_s': 0, 'end_s': 5, 'code': 'CD', 'cycle': 1},
    ], library: lib);
    expect(r.elements.map((e) => e.code).toList(), ['CD', 'DP']);
    expect(r.elements.every((e) => e.fromAi), isTrue);
  });

  test('aucun élément exploitable -> erreur', () {
    expect(() => normalizeAiSegmentation({'elements': []}, library: lib), throwsA(isA<AiFormatException>()));
    expect(() => normalizeAiSegmentation({'foo': 1}, library: lib), throwsA(isA<AiFormatException>()));
  });
}
