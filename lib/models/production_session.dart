class ProductionLoad {
  const ProductionLoad(
      {required this.id,
      required this.number,
      required this.volumeM3,
      required this.recordedAt});
  final int id;
  final int number;
  final double volumeM3;
  final String recordedAt;

  factory ProductionLoad.fromJson(Map<String, dynamic> json) => ProductionLoad(
        id: (json['id'] as num).toInt(),
        number: (json['load_number'] as num).toInt(),
        volumeM3: (json['volume_m3'] as num).toDouble(),
        recordedAt: (json['recorded_at'] ?? '').toString(),
      );
}

class ProductionSession {
  const ProductionSession({
    required this.id,
    required this.productionDate,
    required this.clientName,
    required this.projectSite,
    required this.mixer,
    required this.operator,
    required this.loadingPoint,
    required this.dischargePoint,
    required this.status,
    this.notes = '',
    this.loads = const [],
    this.signoff,
  });
  final int id;
  final String productionDate;
  final String clientName;
  final String projectSite;
  final Map<String, dynamic> mixer;
  final Map<String, dynamic> operator;
  final String loadingPoint;
  final String dischargePoint;
  final String status;
  final String notes;
  final List<ProductionLoad> loads;
  final Map<String, dynamic>? signoff;

  bool get isOpen => status == 'OPEN';
  int get loadCount => loads.length;
  double get totalM3 => calculateProductionTotal(loads.map((e) => e.volumeM3));

  factory ProductionSession.fromJson(Map<String, dynamic> json) =>
      ProductionSession(
        id: (json['id'] as num).toInt(),
        productionDate: (json['production_date'] ?? '').toString(),
        clientName: (json['client_name'] ?? '').toString(),
        projectSite: (json['project_site'] ?? '').toString(),
        mixer: Map<String, dynamic>.from(json['mixer'] as Map? ?? {}),
        operator: Map<String, dynamic>.from(json['operator'] as Map? ?? {}),
        loadingPoint: (json['loading_point'] ?? '').toString(),
        dischargePoint: (json['discharge_point'] ?? '').toString(),
        status: (json['status'] ?? '').toString().toUpperCase(),
        notes: (json['notes'] ?? '').toString(),
        loads: (json['loads'] as List? ?? const [])
            .map((e) =>
                ProductionLoad.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        signoff: json['signoff'] == null
            ? null
            : Map<String, dynamic>.from(json['signoff'] as Map),
      );
}

double calculateProductionTotal(Iterable<double> volumes) =>
    volumes.fold<double>(0, (sum, value) => sum + value);

int nextLoadNumber(Iterable<ProductionLoad> loads) =>
    loads.fold<int>(0, (max, load) => load.number > max ? load.number : max) +
    1;

bool isSensibleLoadVolume(double? volume) =>
    volume != null && volume > 0 && volume <= 100;

bool canAccessProductionSession(
        {required bool isAdmin,
        required int userId,
        required int operatorId}) =>
    isAdmin || userId == operatorId;

bool canEditProductionSession(ProductionSession session) => session.isOpen;

DateTime? productionUtcToLocal(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
  final hasZone = normalized.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalized);
  return DateTime.tryParse(hasZone ? normalized : '${normalized}Z')?.toLocal();
}

String displayProductionTime(String? value) {
  final local = productionUtcToLocal(value);
  if (local == null) return value ?? '';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String? validateSignoff(
    {required String representativeName, required bool hasSignature}) {
  if (representativeName.trim().isEmpty) {
    return 'Client representative name is required.';
  }
  if (!hasSignature) {
    return 'Client representative signature is required.';
  }
  return null;
}
