\
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
  });
}
