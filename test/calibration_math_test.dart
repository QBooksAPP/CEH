import 'package:ceh/core/calibration_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calibration mathematics', () {
    test('deducts container weight and cement safety factor', () {
      final result = calculateCalibrationResult(
        trials: const [
          CalibrationTrialValue(totalWeightKg: 52, counts: 10),
          CalibrationTrialValue(totalWeightKg: 102, counts: 20),
        ],
        containerWeightKg: 2,
        cementSafetyFactorPct: 2,
        applyCementSafetyFactor: true,
      );

      expect(result.validTrials, 2);
      expect(result.kgPerCount, closeTo(4.9, 0.0000001));
    });

    test('deducts container weight and corrects aggregate moisture', () {
      final result = calculateCalibrationResult(
        trials: const [
          CalibrationTrialValue(totalWeightKg: 112, counts: 10),
        ],
        containerWeightKg: 2,
        moisturePct: 10,
        applyMoistureCorrection: true,
      );

      expect(result.kgPerCount, closeTo(10, 0.0000001));
    });

    test('returns no result when an optional section has no valid trials', () {
      final result = calculateCalibrationResult(
        trials: const [],
        containerWeightKg: 2,
        cementSafetyFactorPct: 2,
        applyCementSafetyFactor: true,
      );

      expect(result.validTrials, 0);
      expect(result.kgPerCount, 0);
    });
  });
}
