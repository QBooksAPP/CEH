class CehProject {
  const CehProject(
      {required this.id,
      required this.clientId,
      required this.name,
      required this.isActive,
      this.archivedAt});
  final int id;
  final int clientId;
  final String name;
  final bool isActive;
  final String? archivedAt;
  bool get isArchived => archivedAt != null || !isActive;
  factory CehProject.fromJson(Map<String, dynamic> json) => CehProject(
      id: (json['id'] as num).toInt(),
      clientId: (json['client_id'] as num).toInt(),
      name: '${json['name'] ?? ''}',
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          '${json['is_active']}' == '1',
      archivedAt: json['archived_at']?.toString());
}
