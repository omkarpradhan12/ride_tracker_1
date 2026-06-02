import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import '../services/fuel_service.dart';
import '../models/fuel_fill.dart';

class FuelDashboard extends StatefulWidget {
  const FuelDashboard({super.key});

  @override
  State<FuelDashboard> createState() => _FuelDashboardState();
}

class _FuelDashboardState extends State<FuelDashboard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FuelService.instance,
      builder: (context, _) {
        final service = FuelService.instance;
        final fills = service.getCostTrendData();

        return Column(
          children: [
            const SizedBox(height: 20),
            _buildCollapseHeader(service, fills),
            if (service.isLoading || fills.isEmpty)
              SizedBox(
                height: 260,
                child: Center(
                  child: fills.isEmpty
                      ? const Text("No fuel data available", style: TextStyle(color: Colors.white54))
                      : const CircularProgressIndicator(color: Colors.orangeAccent),
                ),
              )
            else if (_expanded)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildStatsGrid(service),
                      const SizedBox(height: 24),
                      _buildMileageChart(fills),
                      const SizedBox(height: 24),
                      _buildCostChart(fills),
                      const SizedBox(height: 24),
                      _buildEfficiencyMetrics(fills),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              )
            else
              const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildCollapseHeader(FuelService service, List<FuelFill> fills) {
    final latestKilometers = service.latestDistanceSinceFillKm;
    final hasMetrics = fills.isNotEmpty && !service.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: hasMetrics ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Fuel Dashboard",
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      hasMetrics ? "Tap to ${_expanded ? 'collapse' : 'expand'}" : "No fuel data yet",
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    if (hasMetrics) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _dashboardMetric("KM DRIVEN", latestKilometers.toStringAsFixed(1), "KM"),
                          const SizedBox(width: 12),
                          _dashboardMetric("MILEAGE", service.averageMileage.toStringAsFixed(1), "KM/L"),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.orangeAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardMetric(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(FuelService service) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statCard("AVG MILEAGE", "${service.averageMileage.toStringAsFixed(1)} KM/L", Colors.greenAccent),
                _statCard("TOTAL COST", "₹${service.totalCostInr.toStringAsFixed(0)}", Colors.cyan),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statCard("KM/RUPEE", service.averageKmPerRupee.toStringAsFixed(2), Colors.purpleAccent),
                _statCard("COST/100KM", "₹${service.averageCostPer100Km.toStringAsFixed(0)}", Colors.amberAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color accentColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildMileageChart(List<FuelFill> fills) {
    final validFills = fills.where((f) => f.mileage != null && f.mileage! > 0).toList();
    if (validFills.isEmpty) return const SizedBox.shrink();

    final maxMileage = validFills.map((f) => f.mileage!).reduce((a, b) => a > b ? a : b);
    final minMileage = validFills.map((f) => f.mileage!).reduce((a, b) => a < b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mileage Trend (KM/L)",
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _buildLineChart(validFills, (f) => f.mileage!, Colors.greenAccent, maxMileage, minMileage),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostChart(List<FuelFill> fills) {
    final costs = fills.map((f) => f.costInr).toList();
    if (costs.isEmpty) return const SizedBox.shrink();

    final maxCost = costs.reduce((a, b) => a > b ? a : b);
    final minCost = costs.reduce((a, b) => a < b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Fuel Cost Trend (₹)",
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _buildLineChart(fills, (f) => f.costInr, Colors.cyan, maxCost, minCost),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEfficiencyMetrics(List<FuelFill> fills) {
    final validFills = fills.where((f) => f.kmPerRupee != null && f.kmPerRupee! > 0).toList();
    if (validFills.isEmpty) return const SizedBox.shrink();

    final maxEfficiency = validFills.map((f) => f.kmPerRupee!).reduce((a, b) => a > b ? a : b);
    final minEfficiency = validFills.map((f) => f.kmPerRupee!).reduce((a, b) => a < b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Efficiency Trend (KM/₹)",
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _buildLineChart(
                  validFills, (f) => f.kmPerRupee!, Colors.purpleAccent, maxEfficiency, minEfficiency),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text("Best", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(maxEfficiency.toStringAsFixed(3),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(width: 1, height: 40, color: Colors.white10),
                  Column(
                    children: [
                      const Text("Worst", style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(height: 4),
                      Text(minEfficiency.toStringAsFixed(3),
                          style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<FuelFill> fills, Function(FuelFill) getValue, Color lineColor, double maxValue,
      double minValue) {
    if (fills.length < 2) {
      return Center(
        child: Text("Need at least 2 entries", style: TextStyle(color: Colors.white54)),
      );
    }

    final padding = (maxValue - minValue) * 0.1; // 10% padding

    return CustomPaint(
      painter: LineChartPainter(
        values: fills.map((f) => getValue(f)).toList().cast<double>(),
        labels: fills.map((f) => DateFormat('MMM d').format(f.date)).toList(),
        lineColor: lineColor,
        minValue: minValue - padding,
        maxValue: maxValue + padding,
      ),
      size: const Size(double.infinity, 180),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;
  final double minValue;
  final double maxValue;

  LineChartPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
    required this.minValue,
    required this.maxValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final gridPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5;

    void textPainter(String text, Offset offset) {
      final span = TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white54, fontSize: 10),
      );
      final tp = TextPainter(text: span, textDirection: ui.TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, offset);
    }

    final padding = 40.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;

    // Draw grid lines
    for (int i = 0; i <= 4; i++) {
      final y = padding + (graphHeight / 4) * i;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    // Calculate points
    final points = <Offset>[];
    final range = maxValue - minValue;

    for (int i = 0; i < values.length; i++) {
      final x = padding + (graphWidth / (values.length - 1)) * i;
      final normalizedY = (values[i] - minValue) / range;
      final y = padding + graphHeight - (graphHeight * normalizedY);
      points.add(Offset(x, y));
    }

    // Draw line
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }

    // Draw points
    for (final point in points) {
      canvas.drawPoints(ui.PointMode.points, [point], pointPaint);
    }

    // Draw labels (every nth label to avoid crowding)
    final labelStep = (values.length / 4).ceil();
    for (int i = 0; i < values.length; i += labelStep) {
      final x = padding + (graphWidth / (values.length - 1)) * i;
      textPainter(labels[i], Offset(x - 15, size.height - 20));
    }

    // Draw value labels on Y axis
    for (int i = 0; i <= 4; i++) {
      final value = minValue + (range / 4) * i;
      final y = padding + (graphHeight / 4) * (4 - i);
      final label = value.toStringAsFixed(1);
      textPainter(label, Offset(5, y - 8));
    }
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) => false;
}
