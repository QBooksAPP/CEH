import 'package:ceh/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CEH user role is parsed from login JSON', () {
    final user = CehUser.fromJson({
      'id': 1,
      'full_name': 'CEH Admin',
      'email': 'admin@example.com',
      'phone': null,
      'role': 'ADMIN',
      'is_active': true,
    });

    expect(user.id, 1);
    expect(user.isAdmin, true);
    expect(user.isActive, true);
    expect(user.username, isNull);
    expect(user.email, 'admin@example.com');
  });

  test('operator login response supports username without email', () {
    final user = CehUser.fromJson({
      'id': 2,
      'full_name': 'Lucky',
      'username': 'lucky',
      'email': null,
      'role': 'OPERATOR',
      'is_active': 1,
    });

    expect(user.username, 'lucky');
    expect(user.email, '');
    expect(user.isOperator, isTrue);
  });
}
