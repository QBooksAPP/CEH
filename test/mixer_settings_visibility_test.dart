import 'package:ceh/models/production_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Operator Mixer Settings exposes only operational fields', () {
    expect(
        operatorMixerSettingLabels,
        containsAll([
          'Mixer',
          'Mix Design',
          'Production Rate',
          'Cement Target',
          'Counts',
          'Sand Gate Opening',
          'Stone / Granite Gate Opening',
          'Water Flow Rate',
          'Admixture Flow Rate',
        ]));
    expect(operatorMixerSettingLabels, isNot(contains('Calibration Source')));
    expect(operatorMixerSettingLabels, isNot(contains('Moisture')));
    expect(operatorMixerSettingLabels, isNot(contains('Batch volume')));
  });

  test(
      'production settings model preserves both operational and engineering fields',
      () {
    final result = ProductionSettingsResult(data: {
      'saved': false,
      'mixer': {'code': '307'},
      'mix_design': {'name': '30 MPa'},
      'calibration': {'id': 9, 'revision_no': 2},
      'mix': {'cement_kg': 370, 'sand_kg': 700},
      'settings': {
        'production_rate_m3_per_min': .68,
        'counts_per_m3': 1057,
        'sand_gate_cm': 8.5,
        'granite_gate_cm': 13.3,
        'water_flow_lpm': 126
      },
    });
    expect(result.productionRate, .68);
    expect(result.settings['counts_per_m3'], 1057);
    expect(result.mix['sand_kg'], 700); // retained for Admin engineering view
  });
}
