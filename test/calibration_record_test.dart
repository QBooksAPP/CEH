import 'package:ceh/models/calibration_record.dart';
import 'package:flutter_test/flutter_test.dart';

CalibrationRecord record(String status) => CalibrationRecord.fromJson({
      'calibration_id': 42,
      'mixer': {'id': 3, 'code': '307', 'name': 'HM10'},
      'calibration_date': '2026-08-18',
      'calibration_notes': 'Koton Karfi',
      'container_weight_kg': 2.5,
      'stone_moisture_pct': 1.2,
      'sand_moisture_pct': 2.3,
      'cement_safety_factor_pct': 2,
      'status': status,
      'rejection_reason': status == 'REJECTED' ? 'Correct Sand 8' : null,
      'reviewed_at': '2026-08-18 12:00:00',
      'trials': [
        {
          'material': 'SAND',
          'gate_cm': 8,
          'trial_no': 2,
          'total_weight_kg': 34.5,
          'counts': 20,
        }
      ],
    });

void main() {
  test('only DRAFT and REJECTED operator records are editable', () {
    expect(record('DRAFT').canEdit, isTrue);
    expect(record('REJECTED').canEdit, isTrue);
    expect(record('SUBMITTED').canEdit, isFalse);
    expect(record('APPROVED').canEdit, isFalse);
  });

  test('rejected record retains identity, reason and trial values', () {
    final value = record('REJECTED');
    expect(value.id, 42);
    expect(value.rejectionReason, 'Correct Sand 8');
    expect(value.trials.single['gate_cm'], 8);
    expect(value.trials.single['counts'], 20);
  });
}
