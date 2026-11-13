/// Bibliothèque maison de mouvements de confection.
///
/// Codes courts « maison » : ils ne reprennent PAS les codes GSD/Coats
/// (propriétaires). Chaque mouvement a une classe, un statut valeur ajoutée
/// et une couleur (pour le tableau et l'histogramme).
library;

enum MotionClass {
  prise('Prise'),
  positionnement('Positionnement'),
  couture('Couture'),
  coupe('Coupe'),
  depose('Dépose'),
  controle('Contrôle'),
  attente('Attente'),
  autre('Autre');

  const MotionClass(this.label);
  final String label;

  /// Couleur par défaut de la classe (ARGB).
  int get defaultColor => switch (this) {
        MotionClass.prise => 0xFFFFD54F,
        MotionClass.positionnement => 0xFF4FC3F7,
        MotionClass.couture => 0xFF66BB6A,
        MotionClass.coupe => 0xFFFF8A65,
        MotionClass.depose => 0xFFBA68C8,
        MotionClass.controle => 0xFF9575CD,
        MotionClass.attente => 0xFFBDBDBD,
        MotionClass.autre => 0xFF90A4AE,
      };

  static MotionClass parse(Object? v) {
    if (v is! String) return MotionClass.autre;
    final s = _fold(v);
    for (final c in MotionClass.values) {
      if (_fold(c.name) == s || _fold(c.label) == s) return c;
    }
    // Synonymes fréquents (anglais / variantes renvoyées par l'IA).
    const syn = {
      'pick': MotionClass.prise, 'get': MotionClass.prise, 'transfer': MotionClass.prise,
      'position': MotionClass.positionnement, 'setting': MotionClass.positionnement,
      'manipulation': MotionClass.positionnement, 'align': MotionClass.positionnement,
      'sew': MotionClass.couture, 'sewing': MotionClass.couture,
      'cut': MotionClass.coupe, 'trim': MotionClass.coupe,
      'dispose': MotionClass.depose, 'aside': MotionClass.depose,
      'inspect': MotionClass.controle, 'check': MotionClass.controle,
      'wait': MotionClass.attente, 'delay': MotionClass.attente,
    };
    return syn[s] ?? MotionClass.autre;
  }
}

String _fold(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final b = StringBuffer();
  for (final ch in s.trim().toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

class Motion {
  Motion({
    required this.code,
    required this.label,
    required this.motionClass,
    required this.valueAdded,
    int? color,
    this.description = '',
  }) : color = color ?? motionClass.defaultColor;

  String code;
  String label;
  MotionClass motionClass;
  bool valueAdded;
  int color;
  String description;

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        'class': motionClass.name,
        'va': valueAdded,
        'color': color,
        'description': description,
      };

  factory Motion.fromJson(Map<String, dynamic> j) => Motion(
        code: j['code'] as String,
        label: j['label'] as String? ?? j['code'] as String,
        motionClass: MotionClass.parse(j['class']),
        valueAdded: j['va'] == true,
        color: (j['color'] as num?)?.toInt(),
        description: j['description'] as String? ?? '',
      );

  Motion copy() => Motion.fromJson(toJson());
}

/// Code utilisé pour tout mouvement inconnu.
const String kOtherCode = 'AU';

/// Bibliothèque par défaut (codes maison, éditable par l'utilisateur).
List<Motion> defaultMotionLibrary() => [
      Motion(code: 'P1', label: 'Prendre pièce (1 main)', motionClass: MotionClass.prise, valueAdded: false,
          description: 'Saisir une pièce dans le paquet ou la caisse'),
      Motion(code: 'P2', label: 'Prendre pièces (2 mains / plusieurs)', motionClass: MotionClass.prise, valueAdded: false),
      Motion(code: 'AL', label: 'Aligner / assembler les plis', motionClass: MotionClass.positionnement, valueAdded: false,
          description: 'Superposer les bords, faire correspondre crans et repères'),
      Motion(code: 'PP', label: 'Positionner sous le pied', motionClass: MotionClass.positionnement, valueAdded: false),
      Motion(code: 'CD', label: 'Coudre droit', motionClass: MotionClass.couture, valueAdded: true, color: 0xFF2E7D32),
      Motion(code: 'CC', label: 'Coudre courbe', motionClass: MotionClass.couture, valueAdded: true, color: 0xFF43A047),
      Motion(code: 'CA', label: 'Coudre avec arrêt (point d\'arrêt)', motionClass: MotionClass.couture, valueAdded: true, color: 0xFF81C784),
      Motion(code: 'CF', label: 'Couper fil', motionClass: MotionClass.coupe, valueAdded: false),
      Motion(code: 'RT', label: 'Retourner / tourner la pièce', motionClass: MotionClass.positionnement, valueAdded: false, color: 0xFF0288D1),
      Motion(code: 'LS', label: 'Lisser / ajuster', motionClass: MotionClass.positionnement, valueAdded: false, color: 0xFF81D4FA),
      Motion(code: 'MP', label: 'Lever / baisser le pied-de-biche', motionClass: MotionClass.positionnement, valueAdded: false, color: 0xFF4DD0E1),
      Motion(code: 'MA', label: 'Aiguille haut / bas (manipulation machine)', motionClass: MotionClass.positionnement, valueAdded: false, color: 0xFF26A69A),
      Motion(code: 'DP', label: 'Déposer / empiler', motionClass: MotionClass.depose, valueAdded: false),
      Motion(code: 'CT', label: 'Contrôler', motionClass: MotionClass.controle, valueAdded: false),
      Motion(code: 'AT', label: 'Attente', motionClass: MotionClass.attente, valueAdded: false),
      Motion(code: 'DE', label: 'Déplacement', motionClass: MotionClass.attente, valueAdded: false, color: 0xFF9E9E9E),
      Motion(code: kOtherCode, label: 'Autre', motionClass: MotionClass.autre, valueAdded: false),
    ];
