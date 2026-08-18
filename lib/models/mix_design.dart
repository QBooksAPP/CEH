enum MixDesignMode {
  client('CLIENT'),
  calculated('CALCULATED');

  const MixDesignMode(this.apiValue);

  final String apiValue;

  static MixDesignMode fromApi(dynamic value) {
    return value?.toString().toUpperCase() == 'CALCULATED'
        ? MixDesignMode.calculated
        : MixDesignMode.client;
  }
}

double _number(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _integer(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _boolean(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

class MixAdmixture {
  const MixAdmixture({
    required this.id,
    required this.name,
    required this.dosageLitresPer100Kg,
    required this.dilutionFactor,
    required this.sortOrder,
    required this.isActive,
    this.mixDesignId,
  });

  final int id;
  final int? mixDesignId;
  final String name;
  final double dosageLitresPer100Kg;
  final double dilutionFactor;
  final int sortOrder;
  final bool isActive;

  factory MixAdmixture.fromJson(Map<String, dynamic> json) {
    return MixAdmixture(
      id: _integer(json['id']),
      mixDesignId: json['mix_design_id'] == null
          ? null
          : _integer(json['mix_design_id']),
      name: (json['name'] ?? '').toString(),
      dosageLitresPer100Kg: ccPer100KgToLitres(
        _number(json['dosage_cc_per_100kg']),
      ),
      dilutionFactor: _number(json['dilution_factor'], 1),
      sortOrder: _integer(json['sort_order'], 1),
      isActive: _boolean(json['is_active'], true),
    );
  }

  MixAdmixture copyWith({
    int? id,
    int? mixDesignId,
    String? name,
    double? dosageLitresPer100Kg,
    double? dilutionFactor,
    int? sortOrder,
    bool? isActive,
  }) {
    return MixAdmixture(
      id: id ?? this.id,
      mixDesignId: mixDesignId ?? this.mixDesignId,
      name: name ?? this.name,
      dosageLitresPer100Kg: dosageLitresPer100Kg ?? this.dosageLitresPer100Kg,
      dilutionFactor: dilutionFactor ?? this.dilutionFactor,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toApiPayload({required int parentMixDesignId}) {
    return {
      if (id > 0) 'admixture_id': id,
      if (id <= 0) 'mix_design_id': parentMixDesignId,
      'name': name.trim(),
      'dosage_cc_per_100kg': litresPer100KgToCc(dosageLitresPer100Kg),
      'dilution_factor': dilutionFactor,
      'sort_order': sortOrder,
      if (id > 0) 'is_active': isActive,
    };
  }
}

double ccPer100KgToLitres(double dosageCcPer100Kg) => dosageCcPer100Kg / 1000;

double litresPer100KgToCc(double dosageLitresPer100Kg) =>
    dosageLitresPer100Kg * 1000;

class MixDesign {
  const MixDesign({
    required this.id,
    required this.name,
    required this.description,
    required this.mode,
    required this.clientName,
    required this.projectName,
    required this.batchVolumeM3,
    required this.cementKg,
    required this.sandKg,
    required this.graniteKg,
    required this.waterL,
    required this.airFraction,
    required this.cementSg,
    required this.sandSg,
    required this.graniteSg,
    required this.isActive,
    required this.versionNo,
    required this.admixtures,
    this.serverCalculatedAbsoluteVolumeM3,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String description;
  final MixDesignMode mode;
  final String clientName;
  final String projectName;
  final double batchVolumeM3;
  final double cementKg;
  final double sandKg;
  final double graniteKg;
  final double waterL;
  final double airFraction;
  final double cementSg;
  final double sandSg;
  final double graniteSg;
  final bool isActive;
  final int versionNo;
  final List<MixAdmixture> admixtures;
  final double? serverCalculatedAbsoluteVolumeM3;
  final String? createdAt;
  final String? updatedAt;

  double get absoluteVolumeM3 => calculateAbsoluteVolumeM3(
        cementKg: cementKg,
        sandKg: sandKg,
        graniteKg: graniteKg,
        waterL: waterL,
        airFraction: airFraction,
        cementSg: cementSg,
        sandSg: sandSg,
        graniteSg: graniteSg,
      );

  factory MixDesign.fromJson(Map<String, dynamic> json) {
    return MixDesign(
      id: _integer(json['id']),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      mode: MixDesignMode.fromApi(json['design_mode']),
      clientName: (json['client_name'] ?? '').toString(),
      projectName: (json['project_name'] ?? '').toString(),
      batchVolumeM3: _number(json['batch_volume_m3'], 1),
      cementKg: _number(json['cement_kg']),
      sandKg: _number(json['sand_kg']),
      graniteKg: _number(json['granite_kg']),
      waterL: _number(json['water_l']),
      airFraction: _number(json['air_pct']),
      cementSg: _number(json['cement_sg'], 3.15),
      sandSg: _number(json['sand_sg'], 2.60),
      graniteSg: _number(json['granite_sg'], 2.70),
      isActive: _boolean(json['is_active'], true),
      versionNo: _integer(json['version_no'], 1),
      serverCalculatedAbsoluteVolumeM3:
          json['calculated_absolute_volume_m3'] == null
              ? null
              : _number(json['calculated_absolute_volume_m3']),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      admixtures: (json['admixtures'] as List? ?? const [])
          .map(
            (item) =>
                MixAdmixture.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

double calculateAbsoluteVolumeM3({
  required double cementKg,
  required double sandKg,
  required double graniteKg,
  required double waterL,
  required double airFraction,
  required double cementSg,
  required double sandSg,
  required double graniteSg,
}) {
  if (cementSg <= 0 || sandSg <= 0 || graniteSg <= 0) {
    return 0;
  }

  return cementKg / (cementSg * 1000) +
      sandKg / (sandSg * 1000) +
      graniteKg / (graniteSg * 1000) +
      waterL / 1000 +
      airFraction;
}

double? calculateBalancedSandKg({
  required double cementKg,
  required double graniteKg,
  required double waterL,
  required double airFraction,
  required double cementSg,
  required double sandSg,
  required double graniteSg,
}) {
  if (cementSg <= 0 || sandSg <= 0 || graniteSg <= 0) {
    return null;
  }

  final sandVolume = 1 -
      cementKg / (cementSg * 1000) -
      graniteKg / (graniteSg * 1000) -
      waterL / 1000 -
      airFraction;

  if (sandVolume <= 0) return null;
  return sandVolume * sandSg * 1000;
}
