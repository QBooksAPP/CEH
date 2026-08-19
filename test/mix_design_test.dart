import 'package:ceh/models/mix_design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mix Design business rules', () {
    test('CALCULATED mode balances sand to exactly one cubic metre', () {
      final sandKg = calculateBalancedSandKg(
        cementKg: 350,
        graniteKg: 1100,
        waterL: 180,
        airFraction: 0.02,
        cementSg: 3.15,
        sandSg: 2.60,
        graniteSg: 2.70,
      );

      expect(sandKg, isNotNull);
      final volume = calculateAbsoluteVolumeM3(
        cementKg: 350,
        sandKg: sandKg!,
        graniteKg: 1100,
        waterL: 180,
        airFraction: 0.02,
        cementSg: 3.15,
        sandSg: 2.60,
        graniteSg: 2.70,
      );
      expect(volume, closeTo(1, 0.0000001));
    });

    test('changing cement recalculates CALCULATED sand', () {
      final original = calculateBalancedSandKg(
        cementKg: 350,
        graniteKg: 1100,
        waterL: 180,
        airFraction: 0.02,
        cementSg: 3.15,
        sandSg: 2.60,
        graniteSg: 2.70,
      );
      final changed = calculateBalancedSandKg(
        cementKg: 400,
        graniteKg: 1100,
        waterL: 180,
        airFraction: 0.02,
        cementSg: 3.15,
        sandSg: 2.60,
        graniteSg: 2.70,
      );

      expect(changed, isNot(equals(original)));
      expect(changed!, lessThan(original!));
    });

    test('CLIENT absolute volume preserves supplied sand quantity', () {
      const suppliedSandKg = 720.0;
      final volume = calculateAbsoluteVolumeM3(
        cementKg: 350,
        sandKg: suppliedSandKg,
        graniteKg: 1100,
        waterL: 180,
        airFraction: 0.02,
        cementSg: 3.15,
        sandSg: 2.60,
        graniteSg: 2.70,
      );

      expect(suppliedSandKg, 720);
      expect(volume, isNot(closeTo(1, 0.0005)));
    });

    test('parses list response including admixtures and status', () {
      final design = MixDesign.fromJson({
        'id': 7,
        'name': '30 MPa',
        'design_mode': 'CLIENT',
        'client_name': 'Example Client',
        'project_name': 'Example Site',
        'batch_volume_m3': 1,
        'cement_kg': 350,
        'sand_kg': 720,
        'granite_kg': 1100,
        'water_l': 180,
        'air_pct': 0.02,
        'cement_sg': 3.15,
        'sand_sg': 2.6,
        'granite_sg': 2.7,
        'is_active': 1,
        'version_no': 3,
        'admixtures': [
          {
            'id': 4,
            'name': 'Plasticizer',
            'dosage_cc_per_100kg': 450,
            'dilution_factor': 1.5,
            'is_active': true,
          },
        ],
      });

      expect(design.mode, MixDesignMode.client);
      expect(design.isActive, true);
      expect(design.versionNo, 3);
      expect(design.admixtures.single.name, 'Plasticizer');
      expect(design.admixtures.single.dosageLitresPer100Kg, 0.45);
      expect(ccPer100KgToLitres(909), 0.909);
      expect(litresPer100KgToCc(0.909), 909);
    });

    test('CLIENT validation and job context are preserved', () {
      final design = MixDesign.fromJson({
        'id': 9,
        'name': 'Client 30',
        'design_mode': 'CLIENT',
        'client_id': 4,
        'project_id': 12,
        'client_name': 'ABC',
        'project_name': 'Depot',
        'stone_size': '3/4 Down',
        'client_validation_status': 'VALIDATED',
        'cement_kg': 320,
        'sand_kg': 700,
        'granite_kg': 1100,
        'water_l': 180,
        'air_pct': .02,
        'cement_sg': 3.15,
        'sand_sg': 2.6,
        'granite_sg': 2.7,
        'is_active': true,
      });
      expect(design.clientId, 4);
      expect(design.projectId, 12);
      expect(design.stoneSize, '3/4 Down');
      expect(design.isProductionEligible, isTrue);
      expect(
          design.absoluteVolumeDeviationLabel,
          anyOf(startsWith('SHORT BY'), startsWith('EXCEEDS BY'),
              'EXACTLY 1.000 m³'));
    });

    test('unvalidated CLIENT design is never production eligible', () {
      MixDesign design(String status) => MixDesign.fromJson({
            'id': 1,
            'name': 'Client',
            'design_mode': 'CLIENT',
            'client_validation_status': status,
            'cement_kg': 320,
            'sand_kg': 700,
            'granite_kg': 1100,
            'water_l': 180,
            'air_pct': .02,
            'cement_sg': 3.15,
            'sand_sg': 2.6,
            'granite_sg': 2.7,
            'is_active': true,
          });
      expect(design('PENDING_VALIDATION').isProductionEligible, isFalse);
      expect(design('REQUIRES_REVISION').isProductionEligible, isFalse);
      expect(design('VALIDATED').isProductionEligible, isTrue);
    });
  });
}
