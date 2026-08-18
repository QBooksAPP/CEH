import 'package:ceh/models/production_session.dart';
import 'package:flutter_test/flutter_test.dart';

ProductionLoad load(int id, int number, double volume) => ProductionLoad(
    id: id,
    number: number,
    volumeM3: volume,
    recordedAt: '2026-08-18 10:00:00');

ProductionSession record(
        {String status = 'OPEN', List<ProductionLoad> loads = const []}) =>
    ProductionSession(
      id: 1,
      productionDate: '2026-08-18',
      clientName: 'ABC',
      projectSite: 'Point B',
      mixer: const {'id': 3, 'code': '307'},
      operator: const {'id': 7, 'name': 'Operator'},
      loadingPoint: 'Point A',
      dischargePoint: 'Point B',
      status: status,
      loads: loads,
    );

void main() {
  test('load numbering follows the highest existing sequential number', () {
    expect(nextLoadNumber([load(1, 1, 7.2), load(2, 2, 7.8)]), 3);
  });

  test('daily total sums load volumes', () {
    final session =
        record(loads: [load(1, 1, 7.2), load(2, 2, 7.8), load(3, 3, 7.4)]);
    expect(session.loadCount, 3);
    expect(session.totalM3, closeTo(22.4, 0.0001));
  });

  test('positive sensible load validation rejects zero, negative and excessive',
      () {
    expect(isSensibleLoadVolume(7.5), isTrue);
    expect(isSensibleLoadVolume(0), isFalse);
    expect(isSensibleLoadVolume(-1), isFalse);
    expect(isSensibleLoadVolume(100.01), isFalse);
  });

  test('only OPEN sessions are editable', () {
    expect(canEditProductionSession(record()), isTrue);
    expect(canEditProductionSession(record(status: 'SIGNED')), isFalse);
  });

  test('sign-off requires representative name and signature', () {
    expect(validateSignoff(representativeName: '', hasSignature: true),
        contains('name'));
    expect(
        validateSignoff(representativeName: 'A. Client', hasSignature: false),
        contains('signature'));
    expect(validateSignoff(representativeName: 'A. Client', hasSignature: true),
        isNull);
  });

  test('operator access is ownership-bound and admin history is broad', () {
    expect(canAccessProductionSession(isAdmin: false, userId: 7, operatorId: 7),
        isTrue);
    expect(canAccessProductionSession(isAdmin: false, userId: 8, operatorId: 7),
        isFalse);
    expect(canAccessProductionSession(isAdmin: true, userId: 8, operatorId: 7),
        isTrue);
  });

  test('UTC production timestamps are parsed before local display', () {
    final parsed = productionUtcToLocal('2026-08-18 18:54:53');
    expect(parsed, isNotNull);
    expect(parsed!.toUtc(), DateTime.utc(2026, 8, 18, 18, 54, 53));
    expect(productionUtcToLocal('2026-08-18T18:54:53Z')!.toUtc(),
        DateTime.utc(2026, 8, 18, 18, 54, 53));
    expect(displayProductionTime(''), '');
  });
}
