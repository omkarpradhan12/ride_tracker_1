class FuelFill {
  final String id;
  final DateTime date;
  final double liters;
  final double costInr;
  double? mileage; // Calculated mileage for this fill (km/L)

  FuelFill({
    required this.id,
    required this.date,
    required this.liters,
    required this.costInr,
    this.mileage,
  });

  /// Calculate rupees per liter
  double get costPerLiter => costInr / liters;

  /// Calculate km per rupee (efficiency metric)
  double? get kmPerRupee => mileage != null ? mileage! / costPerLiter : null;

  /// Get fuel cost per 100 km
  double? get costPer100Km => mileage != null ? (100 / mileage!) * costPerLiter : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'liters': liters,
        'costInr': costInr,
        'mileage': mileage,
      };

  factory FuelFill.fromJson(Map<String, dynamic> json) => FuelFill(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        liters: (json['liters'] as num).toDouble(),
        costInr: (json['costInr'] as num?)?.toDouble() ?? 0.0,
        mileage: (json['mileage'] as num?)?.toDouble(),
      );

  FuelFill copyWith({
    String? id,
    DateTime? date,
    double? liters,
    double? costInr,
    double? mileage,
  }) {
    return FuelFill(
      id: id ?? this.id,
      date: date ?? this.date,
      liters: liters ?? this.liters,
      costInr: costInr ?? this.costInr,
      mileage: mileage ?? this.mileage,
    );
  }
}
