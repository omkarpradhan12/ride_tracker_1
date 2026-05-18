import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/fuel_fill.dart';

class FuelService extends ChangeNotifier {
  static final FuelService instance = FuelService._();
  FuelService._();

  List<FuelFill> _fills = [];
  List<FuelFill> get fills => List.unmodifiable(_fills);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  double get averageMileage {
    final validFills = _fills.where((f) => f.mileage != null && f.mileage! > 0).toList();
    if (validFills.isEmpty) return 0.0;
    return validFills.map((f) => f.mileage!).reduce((a, b) => a + b) / validFills.length;
  }

  double get totalFuel => _fills.fold(0.0, (sum, f) => sum + f.liters);

  double get totalCostInr => _fills.fold(0.0, (sum, f) => sum + f.costInr);

  double get averageCostPerLiter {
    if (_fills.isEmpty) return 0.0;
    return totalCostInr / totalFuel;
  }

  /// Average km per rupee (fuel efficiency in distance per cost)
  double get averageKmPerRupee {
    final validFills = _fills.where((f) => f.kmPerRupee != null && f.kmPerRupee! > 0).toList();
    if (validFills.isEmpty) return 0.0;
    return validFills.map((f) => f.kmPerRupee!).reduce((a, b) => a + b) / validFills.length;
  }

  /// Average cost per 100 km
  double get averageCostPer100Km {
    final validFills = _fills.where((f) => f.costPer100Km != null && f.costPer100Km! > 0).toList();
    if (validFills.isEmpty) return 0.0;
    return validFills.map((f) => f.costPer100Km!).reduce((a, b) => a + b) / validFills.length;
  }

  /// Get last N fuel fills (sorted by date descending)
  List<FuelFill> getLastNFills(int n) {
    return _fills.take(n).toList();
  }

  /// Get cost trend over time (sorted by date ascending for charting)
  List<FuelFill> getCostTrendData() {
    final sorted = List<FuelFill>.from(_fills)..sort((a, b) => a.date.compareTo(b.date));
    return sorted;
  }

  Future<void> init() async {
    await loadFills();
  }

  Future<void> loadFills() async {
    _isLoading = true;
    notifyListeners();
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/fuel_data.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(content);
        _fills = decoded.map((item) => FuelFill.fromJson(item)).toList();
        _fills.sort((a, b) => b.date.compareTo(a.date));
      }
      await calculateAllMileage();
    } catch (e) {
      debugPrint('❌ Error loading fuel data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveFills() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/fuel_data.json');
      final content = jsonEncode(_fills.map((f) => f.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('❌ Error saving fuel data: $e');
    }
  }

  Future<void> addFill(DateTime date, double liters, {double costInr = 0.0}) async {
    final newFill = FuelFill(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: date,
      liters: liters,
      costInr: costInr,
    );
    _fills.add(newFill);
    _fills.sort((a, b) => b.date.compareTo(a.date));
    await calculateAllMileage();
    await saveFills();
    notifyListeners();
  }

  Future<void> deleteFill(String id) async {
    _fills.removeWhere((f) => f.id == id);
    await calculateAllMileage();
    await saveFills();
    notifyListeners();
  }

  Future<void> editFill(String id, DateTime date, double liters, double costInr) async {
    final index = _fills.indexWhere((f) => f.id == id);
    if (index != -1) {
      _fills[index] = _fills[index].copyWith(date: date, liters: liters, costInr: costInr);
      _fills.sort((a, b) => b.date.compareTo(a.date));
      await calculateAllMileage();
      await saveFills();
      notifyListeners();
    }
  }

  Future<void> calculateAllMileage() async {
    if (_fills.isEmpty) return;

    // Get all rides to calculate distance
    final rides = await _loadAllRides();

    // Sort fills chronologically for calculation
    final sortedFills = List<FuelFill>.from(_fills)..sort((a, b) => a.date.compareTo(b.date));

    for (int i = 0; i < sortedFills.length; i++) {
      final currentFill = sortedFills[i];
      final startDate = i == 0 ? null : sortedFills[i - 1].date;

      // If no earlier fill exists, include all ride distance before this fill date.
      // This supports backdated first fills and ensures preceding rides are counted.
      double totalDistanceMeters = 0.0;
      for (final ride in rides) {
        final rideDate = DateTime.parse(ride['date'] as String);
        final includeRide = startDate == null
            ? rideDate.isBefore(currentFill.date) || rideDate.isAtSameMomentAs(currentFill.date)
            : rideDate.isAfter(startDate) && (rideDate.isBefore(currentFill.date) || rideDate.isAtSameMomentAs(currentFill.date));
        if (includeRide) {
          totalDistanceMeters += (ride['distance'] as num).toDouble();
        }
      }

      if (currentFill.liters > 0 && totalDistanceMeters > 0) {
        currentFill.mileage = (totalDistanceMeters / 1000) / currentFill.liters;
      } else {
        currentFill.mileage = null;
      }
    }

    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _loadAllRides() async {
    final List<Map<String, dynamic>> allRides = [];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync().where((f) => f.path.endsWith('.json')).toList();

      for (var f in files) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (name.contains('fuel_data.json') || name.contains('speed_settings.json')) continue;

        try {
          final content = await File(f.path).readAsString();
          final data = jsonDecode(content);

          if (name.startsWith('archive_')) {
            if (data is List) {
              for (var ride in data) {
                if (ride is Map<String, dynamic>) allRides.add(ride);
              }
            }
          } else if (name.startsWith('ride_')) {
            if (data is Map<String, dynamic>) allRides.add(data);
          }
        } catch (e) {
          debugPrint('⚠️ Error reading ride file ${f.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading rides for mileage: $e');
    }
    return allRides;
  }
}
