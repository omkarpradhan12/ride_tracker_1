import 'package:flutter/material.dart';

class SpeedRange {
  final double threshold;
  final Color color;

  SpeedRange({
    required this.threshold,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'threshold': threshold,
        'color': color.toARGB32(),
      };

  factory SpeedRange.fromJson(Map<String, dynamic> json) => SpeedRange(
        threshold: (json['threshold'] as num).toDouble(),
        color: Color(json['color'] as int),
      );
}
