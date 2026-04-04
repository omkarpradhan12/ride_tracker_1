class RideSession {
  final DateTime startTime;
  DateTime? endTime;
  List<Map<String, double>> route = [];
  double topSpeed = 0.0;
  double totalDistance = 0.0; // in meters

  RideSession({required this.startTime});

  // Java-style calculation for Average Speed
  double get avgSpeed {
    if (endTime == null) return 0.0;
    final durationHours = endTime!.difference(startTime).inSeconds / 3600;
    return durationHours > 0 ? (totalDistance / 1000) / durationHours : 0.0;
  }

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'topSpeed': topSpeed,
    'totalDistance': totalDistance,
    'route': route,
  };
}
