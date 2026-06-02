import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RideService extends ChangeNotifier {
  static final RideService instance = RideService._();
  RideService._();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _lastBackupStatus = '';
  String get lastBackupStatus => _lastBackupStatus;

  /// Get all ride files from app documents directory
  Future<List<File>> getAllRideFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final rideFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ride_') && f.path.endsWith('.json'))
          .toList();
      return rideFiles;
    } catch (e) {
      debugPrint('❌ Error getting ride files: $e');
      return [];
    }
  }

  /// Load all rides and return as list of maps
  Future<List<Map<String, dynamic>>> loadAllRides() async {
    try {
      final files = await getAllRideFiles();
      final rides = <Map<String, dynamic>>[];

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final ride = jsonDecode(content) as Map<String, dynamic>;
          rides.add(ride);
        } catch (e) {
          debugPrint('❌ Error reading ride file ${file.path}: $e');
        }
      }

      return rides;
    } catch (e) {
      debugPrint('❌ Error loading all rides: $e');
      return [];
    }
  }

  /// Create a backup of all rides to Downloads folder
  Future<String> createBackup() async {
    _isLoading = true;
    _lastBackupStatus = 'Creating backup...';
    notifyListeners();

    try {
      // Get all rides
      final rides = await loadAllRides();

      if (rides.isEmpty) {
        _lastBackupStatus = 'No rides to backup';
        _isLoading = false;
        notifyListeners();
        return _lastBackupStatus;
      }

      // Get Downloads directory
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        _lastBackupStatus = 'Downloads folder not found';
        _isLoading = false;
        notifyListeners();
        return _lastBackupStatus;
      }

      // Create backup file
      final timestamp = DateTime.now();
      final fileName = 'ride_tracker_backup_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}.json';
      final backupFile = File('${downloadDir.path}/$fileName');

      // Encode all rides as JSON
      final backupData = jsonEncode({
        'backup_timestamp': timestamp.toIso8601String(),
        'ride_count': rides.length,
        'rides': rides,
      });

      await backupFile.writeAsString(backupData);

      _lastBackupStatus = 'Backup created: $fileName (${rides.length} rides)';
      debugPrint('✅ Backup created: ${backupFile.path}');
    } catch (e) {
      _lastBackupStatus = 'Backup failed: $e';
      debugPrint('❌ Backup error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _lastBackupStatus;
  }

  /// Restore rides from a backup file
  Future<String> restoreFromBackup(File backupFile) async {
    _isLoading = true;
    _lastBackupStatus = 'Restoring backup...';
    notifyListeners();

    try {
      final content = await backupFile.readAsString();
      final backupData = jsonDecode(content) as Map<String, dynamic>;

      final rides = backupData['rides'] as List<dynamic>? ?? [];
      if (rides.isEmpty) {
        _lastBackupStatus = 'No rides in backup file';
        _isLoading = false;
        notifyListeners();
        return _lastBackupStatus;
      }

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();

      int restoredCount = 0;
      for (final rideData in rides) {
        try {
          final ride = rideData as Map<String, dynamic>;
          final timestamp = DateTime.parse(ride['date'] as String? ?? DateTime.now().toIso8601String());
          final fileName = 'ride_${timestamp.millisecondsSinceEpoch}.json';
          final rideFile = File('${appDir.path}/$fileName');

          // Only write if file doesn't already exist (avoid duplicates)
          if (!await rideFile.exists()) {
            await rideFile.writeAsString(jsonEncode(ride));
            restoredCount++;
          }
        } catch (e) {
          debugPrint('❌ Error restoring individual ride: $e');
        }
      }

      _lastBackupStatus = 'Restored $restoredCount rides from backup';
      debugPrint('✅ Restoration complete: $restoredCount rides restored');
    } catch (e) {
      _lastBackupStatus = 'Restore failed: $e';
      debugPrint('❌ Restore error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _lastBackupStatus;
  }

  /// List available backup files in Downloads
  Future<List<File>> getAvailableBackupFiles() async {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        return [];
      }

      final backupFiles = downloadDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ride_tracker_backup_') && f.path.endsWith('.json'))
          .toList();

      // Sort by modification time (newest first)
      backupFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      return backupFiles;
    } catch (e) {
      debugPrint('❌ Error listing backup files: $e');
      return [];
    }
  }

  /// Delete a backup file
  Future<bool> deleteBackup(File backupFile) async {
    try {
      await backupFile.delete();
      debugPrint('✅ Backup deleted: ${backupFile.path}');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting backup: $e');
      return false;
    }
  }
}
