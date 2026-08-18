double settingNumber(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

class ProductionSettingsResult {
  const ProductionSettingsResult({required this.data});
  final Map<String, dynamic> data;

  Map<String, dynamic> get mixer =>
      Map<String, dynamic>.from(data['mixer'] as Map? ?? {});
  Map<String, dynamic> get mixDesign =>
      Map<String, dynamic>.from(data['mix_design'] as Map? ?? {});
  Map<String, dynamic> get mix =>
      Map<String, dynamic>.from(data['mix'] as Map? ?? {});
  Map<String, dynamic> get settings =>
      Map<String, dynamic>.from(data['settings'] as Map? ?? {});
  Map<String, dynamic> get calibration =>
      Map<String, dynamic>.from(data['calibration'] as Map? ?? {});
  bool get saved => data['saved'] == true;
  double get productionRate =>
      settingNumber(settings['production_rate_m3_per_min']);
  double get minutesPerM3 => productionRate > 0 ? 1 / productionRate : 0;
  List<Map<String, dynamic>> get admixtures =>
      (settings['admixtures'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}

double admixtureLitresPerM3({
  required double cementKg,
  required double dosageLitresPer100Kg,
}) =>
    cementKg / 100 * dosageLitresPer100Kg;

double meteredAdmixtureFlowLpm(
        {required double cementKg,
        required double dosageLitresPer100Kg,
        required double productionRate,
        required double dilutionFactor}) =>
    admixtureLitresPerM3(
        cementKg: cementKg, dosageLitresPer100Kg: dosageLitresPer100Kg) *
    productionRate *
    dilutionFactor;
