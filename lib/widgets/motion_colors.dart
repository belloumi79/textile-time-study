import 'package:material_ui/material_ui.dart';

import '../models/motion.dart';

/// Couleur d'un code mouvement selon la bibliothèque (sinon couleur de classe).
Color motionColor(String code, MotionClass cls, List<Motion> library) {
  for (final m in library) {
    if (m.code == code) return Color(m.color);
  }
  return Color(cls.defaultColor);
}

/// Texte lisible sur un fond donné.
Color onColor(Color bg) => bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
