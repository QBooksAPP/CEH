class CalibrationTrialValue {
  const CalibrationTrialValue({
    required this.totalWeightKg,
    required this.counts,
  });

  final double totalWeightKg;
  final double counts;
}

class CalibrationResultValue {
  const CalibrationResultValue({
    required this.validTrials,
    required this.kgPerCount,
  });

  final int validTrials;
  final double kgPerCount;
}

CalibrationResultValue calculateCalibrationResult({
  required Iterable<CalibrationTrialValue> trials,
  required double containerWeightKg,
  double moisturePct = 0,
  double cementSafetyFactorPct = 0,
  bool applyMoistureCorrection = false,
  bool applyCementSafetyFactor = false,
}) {
  final valid = trials.where((trial) => trial.counts > 0).toList();

  if (valid.isEmpty) {
    return const CalibrationResultValue(validTrials: 0, kgPerCount: 0);
  }

  final averageCounts =
      valid.fold<double>(0, (sum, trial) => sum + trial.counts) /
          valid.length;

  final averageNetWeight = valid.fold<double>(0, (sum, trial) {
        var netWeight = trial.totalWeightKg - containerWeightKg;
        if (applyMoistureCorrection) {
          netWeight /= 1 + moisturePct / 100;
        }
        return sum + netWeight;
      }) /
      valid.length;

  var kgPerCount = averageNetWeight / averageCounts;
  if (applyCementSafetyFactor) {
    kgPerCount *= 1 - cementSafetyFactorPct / 100;
  }

  return CalibrationResultValue(
    validTrials: valid.length,
    kgPerCount: kgPerCount,
  );
}
