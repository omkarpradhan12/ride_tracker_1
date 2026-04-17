import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/speed_settings.dart';

class SettingsService extends ChangeNotifier {
  static const String _keySpeedSettings = 'speed_settings';

  List<SpeedRange> _ranges = [];

  List<SpeedRange> get ranges => List.unmodifiable(_ranges);

  SettingsService._();
  static final SettingsService instance = SettingsService._();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_keySpeedSettings);

    if (encoded != null) {
      try {
        final List<dynamic> decoded = jsonDecode(encoded);
        _ranges = decoded.map((item) => SpeedRange.fromJson(item)).toList();
      } catch (e) {
        debugPrint('❌ Error loading speed settings: $e');
        _loadDefaults();
      }
    } else {
      _loadDefaults();
    }
    notifyListeners();
  }

  void _loadDefaults() {
    _ranges = [
      SpeedRange(threshold: 30.0, color: const Color(0xFFFFD700)), // Gold
      SpeedRange(threshold: 55.0, color: const Color(0xFF4CAF50)), // Green
      SpeedRange(threshold: 75.0, color: const Color(0xFFFF8C00)), // Dark Orange
      SpeedRange(threshold: 999.0, color: const Color(0xFFE60000)), // Red (Aggressive)
    ];
  }

  Future<void> saveRanges(List<SpeedRange> newRanges) async {
    _ranges = newRanges;
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_ranges.map((r) => r.toJson()).toList());
    await prefs.setString(_keySpeedSettings, encoded);
    notifyListeners();
  }

  Color getColorForSpeed(double speedKmH) {
    for (final range in _ranges) {
      if (speedKmH <= range.threshold) {
        return range.color;
      }
    }
    return _ranges.isNotEmpty ? _ranges.last.color : Colors.grey;
  }
}
