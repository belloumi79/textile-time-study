import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../services/format.dart';

class ChartBar {
  ChartBar({required this.label, required this.value, required this.color, this.tooltip = ''});
  final String label;
  final double value;
  final Color color;
  final String tooltip;
}

/// Histogramme coloré des temps par élément.
class ElementChart extends StatelessWidget {
  const ElementChart({super.key, required this.bars, this.highlight, this.unit = 's', this.onTap});
  final List<ChartBar> bars;
  final int? highlight;
  final String unit;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return const Center(child: Text('Aucun élément à afficher', style: TextStyle(color: Colors.grey)));
    }
    final maxV = bars.map((b) => b.value).fold(0.0, (a, b) => a > b ? a : b);
    final width = bars.length > 14 ? 14.0 : 22.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 4),
      child: BarChart(
        BarChartData(
          maxY: maxV <= 0 ? 1 : maxV * 1.15,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchCallback: (event, resp) {
              if (onTap != null && event is FlTapUpEvent && resp?.spot != null) {
                onTap!(resp!.spot!.touchedBarGroupIndex);
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${bars[group.x].label}\n${fr(rod.toY)} $unit${bars[group.x].tooltip.isEmpty ? '' : '\n${bars[group.x].tooltip}'}',
                const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) => Text(fr(v, 1), style: const TextStyle(fontSize: 9)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (bars.length > 30 && i % 2 == 1) return const SizedBox.shrink();
                  return Text('${i + 1}', style: const TextStyle(fontSize: 9));
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: bars[i].value,
                  color: bars[i].color,
                  width: width,
                  borderRadius: BorderRadius.circular(2),
                  borderSide: i == highlight
                      ? const BorderSide(color: Colors.redAccent, width: 2)
                      : const BorderSide(color: Colors.black26, width: 0.5),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
