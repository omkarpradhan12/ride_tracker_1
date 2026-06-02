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
              Expanded(
                child: fills.isEmpty
                    ? const Center(
                        child: Text("No petrol records yet.",
                            style: TextStyle(color: Colors.white24, fontSize: 13)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 120),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orangeAccent.withValues(alpha: 0.08), Colors.orangeAccent.withValues(alpha: 0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _summaryStat("AVG MILEAGE", service.averageMileage.toStringAsFixed(1), "KM/L")),
                    Container(width: 0.5, height: 50, color: Colors.white.withValues(alpha: 0.08)),
                    Expanded(child: _summaryStat("KM/RUPEE", service.averageKmPerRupee.toStringAsFixed(2), "")),
                  ],
                ),
                const SizedBox(height: 16),
                Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _summaryStat("TOTAL COST", "₹${service.totalCostInr.toStringAsFixed(0)}", "")),
                    Container(width: 0.5, height: 50, color: Colors.white.withValues(alpha: 0.08)),
                    Expanded(child: _summaryStat("COST/L", "₹${service.averageCostPerLiter.toStringAsFixed(2)}", "")),
                  ],
                ),
                if (service.averageCostPer100Km > 0) ...[
                  const SizedBox(height: 16),
                  Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _summaryStat("COST/L", "₹${service.averageCostPerLiter.toStringAsFixed(2)}", "")),
                      Container(width: 0.5, height: 50, color: Colors.white.withValues(alpha: 0.08)),
                      Expanded(child: _summaryStat("COST/100KM", "₹${service.averageCostPer100Km.toStringAsFixed(0)}", "")),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (service.latestFill != null) ...[
            const SizedBox(height: 12),
            _buildLastFillDistanceCard(service),
          ]
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, String unit) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9, letterSpacing: 0.8, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1)),
            ]
          ],
        ),
      ],
    );
  }

  Widget _buildLastFillDistanceCard(FuelService service) {
    final fill = service.latestFill!;
    final distance = service.latestDistanceSinceFillKm;
    final progress = (distance / 250).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orangeAccent.withValues(alpha: 0.06), Colors.orangeAccent.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("KM SINCE FILL",
                  style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w500)),
              Text(DateFormat('MMM dd').format(fill.date),
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Text("${distance.toStringAsFixed(1)} KM",
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              color: Colors.orangeAccent,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 8),
          Text("Since ${DateFormat('MMM dd').format(fill.date)} • resets on new fill",
              style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.2)),
        ],
      ),
    );
  }

  Widget _buildFuelCard(FuelFill fill) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_gas_station, color: Colors.orangeAccent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM dd, yyyy').format(fill.date),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.1),
                    ),
                    const SizedBox(height: 3),
                    Text("${fill.liters.toStringAsFixed(2)}L • ₹${fill.costInr.toStringAsFixed(0)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.1)),
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
                          color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold, height: 1),
                    ),
                    const Text("KM/L", style: TextStyle(color: Colors.greenAccent, fontSize: 9, height: 1)),
                  ],
                )
              else
                const Text("—", style: TextStyle(color: Colors.white24, fontSize: 16)),
              const SizedBox(width: 8),
              PopupMenuButton(
                color: const Color(0xFF1E1E1E),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: const Row(
                      children: [Icon(Icons.edit, color: Colors.cyan, size: 18), SizedBox(width: 8), Text("Edit", style: TextStyle(color: Colors.white))],
                    ),
                    onTap: () => _showEditFuelDialog(fill),
                  ),
                  PopupMenuItem(
                    child: const Row(
                      children: [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 8), Text("Delete", style: TextStyle(color: Colors.white))],
                    ),
                    onTap: () => _confirmDelete(fill),
                  ),
                ],
                child: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
              ),
            ],
          ),
          if (fill == FuelService.instance.latestFill) ...[
            const SizedBox(height: 12),
            _buildFillDistanceVisual(fill),
          ],
          if (fill.kmPerRupee != null) ...[
            const SizedBox(height: 10),
            Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statBadge("Cost/L", "₹${fill.costPerLiter.toStringAsFixed(1)}", Colors.cyan),
                _statBadge("KM/₹", fill.kmPerRupee!.toStringAsFixed(2), Colors.purpleAccent),
                _statBadge("Cost/100KM", "₹${fill.costPer100Km!.toStringAsFixed(0)}", Colors.amberAccent),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, height: 1)),
        ],
      ),
    );
  }

  Widget _buildFillDistanceVisual(FuelFill fill) {
    final distance = fill.distanceSinceFillKm ?? 0.0;
    final progress = (distance / 250).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Distance since",
                style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.5, fontWeight: FontWeight.w500)),
            Text("${distance.toStringAsFixed(1)} KM",
                style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: Colors.greenAccent,
            minHeight: 4,
          ),
        ),
      ],
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
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              title: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("ADD PETROL",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: litersController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Liters",
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.local_gas_station, color: Colors.orangeAccent, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Cost (₹)",
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.currency_rupee, color: Colors.cyan, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.orangeAccent, size: 18),
                          const SizedBox(width: 12),
                          Text(DateFormat('MMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
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
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              title: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text("EDIT PETROL",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: litersController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Liters",
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.local_gas_station, color: Colors.orangeAccent, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: "Cost (₹)",
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(Icons.currency_rupee, color: Colors.cyan, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
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
                          selectedDate = DateTime(date.year, date.month, date.day, selectedDate.hour, selectedDate.minute);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.orangeAccent, size: 18),
                          const SizedBox(width: 12),
                          Text(DateFormat('MMM dd, yyyy').format(selectedDate),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(FuelFill fill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Record?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure? This cannot be undone.",
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              FuelService.instance.deleteFill(fill.id);
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
