class CalibrationRecord {
  const CalibrationRecord({
    required this.id,
    required this.mixer,
    required this.calibrationDate,
    required this.notes,
    required this.containerWeightKg,
    required this.stoneMoisturePct,
    required this.sandMoisturePct,
    required this.cementSafetyFactorPct,
    required this.status,
    required this.rejectionReason,
    required this.reviewedAt,
    required this.trials,
    this.clientId,
    this.projectId,
    this.clientName = '',
    this.projectName = '',
    this.stoneSize = '',
  });

  final int id;
  final Map<String, dynamic> mixer;
  final String calibrationDate;
  final String notes;
  final double containerWeightKg;
  final double stoneMoisturePct;
  final double sandMoisturePct;
  final double cementSafetyFactorPct;
  final String status;
  final String? rejectionReason;
  final String? reviewedAt;
  final List<Map<String, dynamic>> trials;
  final int? clientId;
  final int? projectId;
  final String clientName;
  final String projectName;
  final String stoneSize;

  bool get canEdit => status == 'DRAFT' || status == 'REJECTED';

  factory CalibrationRecord.fromJson(Map<String, dynamic> json) =>
      CalibrationRecord(
        id: (json['calibration_id'] as num).toInt(),
        mixer: Map<String, dynamic>.from(json['mixer'] as Map? ?? {}),
        calibrationDate: '${json['calibration_date']}',
        notes: '${json['calibration_notes'] ?? ''}',
        containerWeightKg:
            (json['container_weight_kg'] as num? ?? 0).toDouble(),
        stoneMoisturePct: (json['stone_moisture_pct'] as num? ?? 0).toDouble(),
        sandMoisturePct: (json['sand_moisture_pct'] as num? ?? 0).toDouble(),
        cementSafetyFactorPct:
            (json['cement_safety_factor_pct'] as num? ?? 0).toDouble(),
        status: '${json['status']}',
        rejectionReason: json['rejection_reason']?.toString(),
        reviewedAt: json['reviewed_at']?.toString(),
        trials: (json['trials'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        clientId: (json['client_id'] as num?)?.toInt(),
        projectId: (json['project_id'] as num?)?.toInt(),
        clientName: '${json['client_name'] ?? ''}',
        projectName: '${json['project_name'] ?? ''}',
        stoneSize: '${json['stone_size'] ?? ''}',
      );
}
