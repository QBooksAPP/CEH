class CalibrationSource {
  const CalibrationSource({
    required this.id,
    required this.mixerId,
    required this.calibrationDate,
    required this.revisionNo,
    required this.notes,
    required this.reviewedAt,
    this.clientId,
    this.projectId,
    this.stoneSize = '',
    this.clientName = '',
    this.projectName = '',
  });

  final int id;
  final int mixerId;
  final String calibrationDate;
  final int revisionNo;
  final String notes;
  final String? reviewedAt;
  final int? clientId;
  final int? projectId;
  final String stoneSize;
  final String clientName;
  final String projectName;

  factory CalibrationSource.fromJson(Map<String, dynamic> json) =>
      CalibrationSource(
        id: (json['id'] as num).toInt(),
        mixerId: (json['mixer_id'] as num).toInt(),
        calibrationDate: '${json['calibration_date']}',
        revisionNo: (json['revision_no'] as num? ?? 1).toInt(),
        notes: '${json['calibration_notes'] ?? ''}',
        reviewedAt: json['reviewed_at']?.toString(),
        clientId: (json['client_id'] as num?)?.toInt(),
        projectId: (json['project_id'] as num?)?.toInt(),
        stoneSize: '${json['stone_size'] ?? ''}',
        clientName: '${json['client_name'] ?? ''}',
        projectName: '${json['project_name'] ?? ''}',
      );

  String get dateLabel {
    final date = DateTime.tryParse(calibrationDate);
    if (date == null) return calibrationDate;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String get optionLabel =>
      '#$id • $dateLabel • Rev $revisionNo • $clientName / $projectName • $stoneSize • '
      '${notes.isEmpty ? 'No site notes' : notes}'
      '${reviewedAt == null ? '' : ' • Approved ${_dateTimeLabel(reviewedAt!)}'}';

  static String _dateTimeLabel(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
