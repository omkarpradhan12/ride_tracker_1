class RideSession {
  final DateTime startTime;
  DateTime? endTime;
  List<Map<String, double>> route = [];
  List<double> segmentSpeeds = [];
  double topSpeed = 0.0;
  double totalDistance = 0.0; // in meters

  RideSession({required this.startTime, List<double>? segmentSpeeds})
      : segmentSpeeds = segmentSpeeds ?? [];

  // Java-style calculation for Average Speed
  double get avgSpeed {
    if (endTime == null) return 0.0;
    final durationHours = endTime!.difference(startTime).inSeconds / 3600;
    return durationHours > 0 ? (totalDistance / 1000) / durationHours : 0.0;
  }

  bool get hasSegmentSpeeds => segmentSpeeds.isNotEmpty;

  factory RideSession.fromJson(Map<String, dynamic> json) {
    final session = RideSession(
      startTime: DateTime.parse(json['startTime'] as String),
      segmentSpeeds: json['segmentSpeeds'] != null
          ? List<double>.from((json['segmentSpeeds'] as List).map((e) => (e as num).toDouble()))
          : [],
    );

    session.endTime = json['endTime'] != null
        ? DateTime.parse(json['endTime'] as String)
        : null;
    session.topSpeed = (json['topSpeed'] as num?)?.toDouble() ?? 0.0;
    session.totalDistance = (json['totalDistance'] as num?)?.toDouble() ?? 0.0;
    session.route = [];
    if (json['route'] != null) {
      final rawRoute = json['route'] as List;
      for (final item in rawRoute) {
        if (item is List && item.length >= 2) {
          session.route.add({
            'latitude': (item[0] as num).toDouble(),
            'longitude': (item[1] as num).toDouble(),
          });
        } else if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final lat = map['latitude'] ?? map['lat'];
          final lon = map['longitude'] ?? map['lng'] ?? map['lon'];
          if (lat != null && lon != null) {
            session.route.add({
              'latitude': (lat as num).toDouble(),
              'longitude': (lon as num).toDouble(),
            });
          }
        }
      }
    }
    return session;
  }

  Map<String, dynamic> toJson() {
    final data = {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'topSpeed': topSpeed,
      'totalDistance': totalDistance,
      'route': route,
    };
    if (segmentSpeeds.isNotEmpty) {
      data['segmentSpeeds'] = segmentSpeeds;
    }
    return data;
  }
}
