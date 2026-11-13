/// Formats d'affichage (français : virgule décimale).
String fr(double v, [int decimals = 2]) => v.toStringAsFixed(decimals).replaceAll('.', ',');

String frDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Position vidéo : « 12,34 s » ou « 1:02,3 ».
String clock(double seconds) {
  if (seconds < 60) return '${fr(seconds, 2)} s';
  final m = seconds ~/ 60;
  final s = seconds - m * 60;
  return '$m:${s < 10 ? '0' : ''}${fr(s, 1)}';
}
