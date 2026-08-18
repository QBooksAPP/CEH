import 'package:ceh/models/production_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('320kg example calculates 3.2 L/m3 and 1.6 L/min', () {
    expect(admixtureLitresPerM3(cementKg: 320, dosageLitresPer100Kg: 1), 3.2);
    expect(
      meteredAdmixtureFlowLpm(
        cementKg: 320,
        dosageLitresPer100Kg: 1,
        productionRate: .5,
        dilutionFactor: 1,
      ),
      1.6,
    );
  });

  test('370kg example calculates 2.96 L/m3 and 1.776 L/min', () {
    expect(
      admixtureLitresPerM3(cementKg: 370, dosageLitresPer100Kg: .8),
      closeTo(2.96, .000001),
    );
    expect(
      meteredAdmixtureFlowLpm(
        cementKg: 370,
        dosageLitresPer100Kg: .8,
        productionRate: .6,
        dilutionFactor: 1,
      ),
      closeTo(1.776, .000001),
    );
  });

  test('dilution multiplies metered solution flow', () {
    expect(
      meteredAdmixtureFlowLpm(
        cementKg: 320,
        dosageLitresPer100Kg: 1,
        productionRate: .5,
        dilutionFactor: 2,
      ),
      3.2,
    );
  });
}
