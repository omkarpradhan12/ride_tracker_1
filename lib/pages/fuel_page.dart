import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/fuel_service.dart';
import '../models/fuel_fill.dart';

class FuelPage extends StatefulWidget {
  const FuelPage({super.key});

  @override
  State<FuelPage> createState() => _FuelPageState();
}

class _FuelPageState extends State<FuelPage> {
  bool _costChartExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("PETROL LOGS",
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFuelDialog,
        backgroundColor: Colors.orangeAccent,
        child: const Icon(Icons.local_gas_station, color: Colors.black),
      ),
      body: ListenableBuilder(
        listenable: FuelService.instance,
        builder: (context, _) {
          final service = FuelService.instance;
          final fills = service.fills;

          if (service.isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
          }

          return Column(
            children: [
              _buildSummaryHeader(service),
              _buildCostPerLiterPreview(service),
              Expanded(
                child: fills.isEmpty
                    ? const Center(
                        child: Text("No petrol records yet.",
                            style: TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        itemCount: fills.length,
                        itemBuilder: (context, index) {
                          return _buildFuelCard(fills[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(FuelService service) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orangeAccent.withValues(alpha: 0.15), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryStat("AVG MILEAGE", service.averageMileage.toStringAsFixed(1), "KM/L"),
              Container(width: 1, height: 40, color: Colors.white10),
              _summaryStat("TOTAL FUEL", service.totalFuel.toStringAsFixed(1), "L"),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryStat("TOTAL COST", "₹${service.totalCostInr.toStringAsFixed(0)}", ""),
              Container(width: 1, height: 40, color: Colors.white10),
              _summaryStat("KM/RUPEE", service.averageKmPerRupee.toStringAsFixed(2), ""),
            ],
          ),
          if (service.averageCostPer100Km > 0) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white10),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryStat("COST/L", "₹${service.averageCostPerLiter.toStringAsFixed(2)}", ""),
                Container(width: 1, height: 40, color: Colors.white10),
                _summaryStat("COST/100KM", "₹${service.averageCostPer100Km.toStringAsFixed(0)}", ""),
              ],
            ),
          ] else ...[
            const SizedBox(height: 20),
            _summaryStat("COST/L", "₹${service.averageCostPerLiter.toStringAsFixed(2)}", ""),
          ]
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildCostPerLiterPreview(FuelService service) {
    final fills = service.getCostTrendData();
    if (fills.length < 2) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _costChartExpanded = !_costChartExpanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Fuel Cost/L Trend",
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text(_costChartExpanded ? "Collapse" : "Expand",
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Icon(_costChartExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.orangeAccent, size: 18),
                  ],
                )
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 86,
                child: CustomPaint(
                  painter: CostPerLiterChartPainter(
                    values: fills.map((f) => f.costPerLiter).toList(),
                    labels: fills.map((f) => DateFormat('MMM d').format(f.date)).toList(),
                    lineColor: Colors.orangeAccent,
                  ),
                  size: const Size(double.infinity, 86),
                ),
              ),
            ),
            crossFadeState: _costChartExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
          if (!_costChartExpanded) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showCostPerLiterTrendDialog(fills),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Text("Open full trend",
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  SizedBox(width: 4),
                  Icon(Icons.open_in_new, color: Colors.orangeAccent, size: 16),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildFuelCard(FuelFill fill) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_gas_station, color: Colors.orangeAccent, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(fill.date),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text("${fill.liters.toStringAsFixed(2)} Liters • ₹${fill.costInr.toStringAsFixed(0)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (fill.mileage != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fill.mileage!.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const Text("KM/L", style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  ],
                )
              else
                const Text("—", style: TextStyle(color: Colors.white24)),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.cyan, size: 20),
                onPressed: () => _showEditFuelDialog(fill),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                onPressed: () => _confirmDelete(fill),
              ),
            ],
          ),
          if (fill.kmPerRupee != null) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text("Cost/L", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text("₹${fill.costPerLiter.toStringAsFixed(1)}",
                        style: const TextStyle(color: Colors.cyan, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(width: 1, height: 30, color: Colors.white10),
                Column(
                  children: [
                    const Text("KM/₹", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text(fill.kmPerRupee!.toStringAsFixed(2),
                        style: const TextStyle(color: Colors.purpleAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(width: 1, height: 30, color: Colors.white10),
                Column(
                  children: [
                    const Text("Cost/100KM", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 4),
                    Text("₹${fill.costPer100Km!.toStringAsFixed(0)}",
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Future<void> _showAddFuelDialog() async {
    final TextEditingController litersController = TextEditingController();
    final TextEditingController costController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("ADD PETROL FILL",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  TextField(
                    controller: litersController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Liters",
                      labelStyle: TextStyle(color: Colors.orangeAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Cost (₹ INR)",
                      labelStyle: TextStyle(color: Colors.cyan),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyan)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Date", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    subtitle: Text(DateFormat('MMM dd, yyyy').format(selectedDate),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.calendar_today, color: Colors.orangeAccent, size: 20),
                    onTap: () async {
                      // ignore: use_build_context_synchronously
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          selectedDate = DateTime(date.year, date.month, date.day, DateTime.now().hour, DateTime.now().minute);
                        });
                      }
                    },
                  ),
                ],
              ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final liters = double.tryParse(litersController.text);
                    final cost = double.tryParse(costController.text) ?? 0.0;
                    if (liters != null && liters > 0) {
                      FuelService.instance.addFill(selectedDate, liters, costInr: cost);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditFuelDialog(FuelFill fill) async {
    final TextEditingController litersController = TextEditingController(text: fill.liters.toString());
    final TextEditingController costController = TextEditingController(text: fill.costInr.toStringAsFixed(0));
    DateTime selectedDate = fill.date;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("EDIT PETROL FILL",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  TextField(
                    controller: litersController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Liters",
                      labelStyle: TextStyle(color: Colors.orangeAccent),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Cost (₹ INR)",
                      labelStyle: TextStyle(color: Colors.cyan),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyan)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Date", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    subtitle: Text(DateFormat('MMM dd, yyyy').format(selectedDate),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.calendar_today, color: Colors.orangeAccent, size: 20),
                    onTap: () async {
                      // ignore: use_build_context_synchronously
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          // Keep the original time, only change the date
                          selectedDate = DateTime(date.year, date.month, date.day, selectedDate.hour, selectedDate.minute);
                        });
                      }
                    },
                  ),
                ],
              ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final liters = double.tryParse(litersController.text);
                    final cost = double.tryParse(costController.text) ?? 0.0;
                    if (liters != null && liters > 0) {
                      FuelService.instance.editFill(fill.id, selectedDate, liters, cost);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCostPerLiterTrendDialog(List<FuelFill> fills) {
    final service = FuelService.instance;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Fuel Cost per Liter",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 220,
                  child: CustomPaint(
                    painter: CostPerLiterChartPainter(
                      values: fills.map((f) => f.costPerLiter).toList(),
                      labels: fills.map((f) => DateFormat('MMM d').format(f.date)).toList(),
                      lineColor: Colors.orangeAccent,
                    ),
                    size: const Size(double.infinity, 220),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _summaryStat("Avg Cost/L", "₹${service.averageCostPerLiter.toStringAsFixed(2)}", ""),
                    _summaryStat("Total Cost", "₹${service.totalCostInr.toStringAsFixed(0)}", ""),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CLOSE", style: TextStyle(color: Colors.orangeAccent)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(FuelFill fill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Delete Record?", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to delete this fuel record?",
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              FuelService.instance.deleteFill(fill.id);
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class CostPerLiterChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color lineColor;

  CostPerLiterChartPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || values.length < 2) return;

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;

    final padding = 24.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs();
    final yRange = range > 0 ? range : (maxValue.abs() > 0 ? maxValue.abs() * 0.1 : 1.0);

    for (int i = 0; i <= 3; i++) {
      final y = padding + (graphHeight / 3) * i;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = padding + (graphWidth / (values.length - 1)) * i;
      final normalizedY = (values[i] - minValue) / yRange;
      final y = padding + graphHeight - (graphHeight * normalizedY);
      points.add(Offset(x, y));
    }

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, paint);

    for (final point in points) {
      canvas.drawCircle(point, 3.5, pointPaint);
    }

    final textStyle = const TextStyle(color: Colors.white54, fontSize: 10);
    for (int i = 0; i < labels.length; i++) {
      final textSpan = TextSpan(text: labels[i], style: textStyle);
      final tp = TextPainter(text: textSpan, textDirection: ui.TextDirection.ltr);
      tp.layout(maxWidth: 60);
      final x = points[i].dx - tp.width / 2;
      final y = size.height - padding + 4;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
