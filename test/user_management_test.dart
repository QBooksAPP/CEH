import 'dart:io';

import 'package:ceh/core/view_mode.dart';
import 'package:ceh/models/session.dart';
import 'package:ceh/models/user_account.dart';
import 'package:ceh/screens/user_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String serverFile(String name) => File('Server/$name').readAsStringSync();

const operatorSession = CehSession(
  token: 'operator-token',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 2,
    fullName: 'Lucky',
    email: '',
    username: 'lucky',
    role: 'OPERATOR',
    isActive: true,
  ),
);

const adminSession = CehSession(
  token: 'admin-token',
  tokenType: 'Bearer',
  expiresAt: '',
  user: CehUser(
    id: 1,
    fullName: 'Admin',
    email: 'admin@example.test',
    role: 'ADMIN',
    isActive: true,
  ),
);

void main() {
  test('username normalization is case-insensitive and trims input', () {
    expect(normalizeUsername('  Lucky.Operator  '), 'lucky.operator');
    expect(isValidUsername('Lucky_01'), isTrue);
  });

  test('username validation rejects email addresses and short names', () {
    expect(isValidUsername('lucky@example.com'), isFalse);
    expect(isValidUsername('ab'), isFalse);
  });

  test('migration adds only nullable case-insensitive unique username', () {
    final sql = serverFile('migration_v1_5_username_login.sql');
    expect(sql, contains('username VARCHAR(100)'));
    expect(sql, contains('utf8mb4_unicode_ci NULL'));
    expect(sql, contains('UNIQUE KEY uq_users_username'));
    expect(sql.toLowerCase(), isNot(contains('modify column email')));
  });

  test('login supports existing email and username with active check', () {
    final php = serverFile('login.php');
    expect(php, contains(r"$input['login'] ?? $input['email']"));
    expect(php, contains('LOWER(username)'));
    expect(php, contains('LOWER(email)'));
    expect(php, contains('password_verify'));
    expect(php, contains("!(bool)\$user['is_active']"));
    expect(php, contains('password_needs_rehash'));
  });

  test('operator creation needs username but not email and is Admin-only', () {
    final php = serverFile('users_create.php');
    expect(php, contains("qbook_require_role(\$admin, ['ADMIN'])"));
    expect(php, contains(r"$input['username']"));
    expect(php, contains(r"$input['email'] ?? ''"));
    expect(php, contains("'OPERATOR'"));
    expect(php, contains(r'password_hash($password, PASSWORD_DEFAULT)'));
  });

  test('password reset is Admin-only and revokes existing tokens', () {
    final php = serverFile('users_reset_password.php');
    expect(php, contains("qbook_require_role(\$user, ['ADMIN'])"));
    expect(php, contains('password_hash'));
    expect(php, contains('SET revoked_at = UTC_TIMESTAMP()'));
    expect(php, isNot(contains("'password' =>")));
  });

  test('Production Log list/get enforce operator ownership', () {
    final list = serverFile('production_sessions.php');
    final get = serverFile('production_session_get.php');
    final common = serverFile('production_log_common.php');
    expect(list, contains("operator_id = ?"));
    expect(list, contains(r"$params[] = (int)$user['id']"));
    expect(get, contains(r'production_can_access($user, $row)'));
    expect(common, contains(r"$user['role'] === 'ADMIN'"));
    expect(
        common, contains(r"(int)$session['operator_id'] === (int)$user['id']"));
  });

  testWidgets('Operator cannot access User Management', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: UserManagementScreen(session: operatorSession),
    ));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Create Operator'), findsNothing);
  });

  testWidgets('Admin View as Operator cannot access User Management',
      (tester) async {
    final controller = CehViewModeController()..enableOperatorView();
    await tester.pumpWidget(CehViewModeScope(
      controller: controller,
      child: const MaterialApp(
        home: UserManagementScreen(session: adminSession),
      ),
    ));
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Create Operator'), findsNothing);
  });
}
