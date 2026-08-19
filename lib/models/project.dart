class CehProject {
  const CehProject(
      {required this.id,
      required this.clientId,
      required this.name,
      required this.isActive});
  final int id;
  final int clientId;
  final String name;
  final bool isActive;
  factory CehProject.fromJson(Map<String, dynamic> json) => CehProject(
      id: (json['id'] as num).toInt(),
      clientId: (json['client_id'] as num).toInt(),
      name: '${json['name'] ?? ''}',
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          '${json['is_active']}' == '1');
}
