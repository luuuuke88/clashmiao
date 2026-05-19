import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/providers/stats_history_provider.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TrafficSparklineCard extends ConsumerWidget {
  const TrafficSparklineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(statsHistoryProvider);
    final current = history.isNotEmpty ? history.last : BoxStats.empty;

    final uplinkSpots = history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.uplink.toDouble()))
        .toList();
    final downlinkSpots = history
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.downlink.toDouble()))
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(
                  label: '↑',
                  speed: formatSpeed(current.uplink),
                  total: formatBytes(current.uplinkTotal),
                  color: Colors.blue,
                ),
                _StatItem(
                  label: '↓',
                  speed: formatSpeed(current.downlink),
                  total: formatBytes(current.downlinkTotal),
                  color: Colors.green,
                ),
              ],
            ),
            if (history.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    lineBarsData: [
                      LineChartBarData(
                        spots: uplinkSpots,
                        color: Colors.blue.withValues(alpha: 0.7),
                        isCurved: true,
                        barWidth: 1.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.blue.withValues(alpha: 0.08),
                        ),
                      ),
                      LineChartBarData(
                        spots: downlinkSpots,
                        color: Colors.green.withValues(alpha: 0.7),
                        isCurved: true,
                        barWidth: 1.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.green.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.speed,
    required this.total,
    required this.color,
  });
  final String label;
  final String speed;
  final String total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(speed, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              total,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
