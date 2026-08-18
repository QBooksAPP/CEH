class CehClient {
  const CehClient(
      {required this.id, required this.name, required this.isActive});

  final int id;
  final String name;
  final bool isActive;

  factory CehClient.fromJson(Map<String, dynamic> json) => CehClient(
        id: (json['id'] as num).toInt(),
        name: (json['name'] ?? '').toString(),
        isActive: json['is_active'] == true ||
            json['is_active'] == 1 ||
            json['is_active']?.toString() == '1',
      );
}
