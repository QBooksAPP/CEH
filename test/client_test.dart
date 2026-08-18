import 'package:ceh/models/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client parses integer active flag from the existing PHP contract', () {
    final client = CehClient.fromJson(
        {'id': 12, 'name': 'ABC Construction Ltd', 'is_active': 1});

    expect(client.id, 12);
    expect(client.name, 'ABC Construction Ltd');
    expect(client.isActive, isTrue);
  });

  test('inactive client is identified for exclusion from operator choices', () {
    final clients = [
      CehClient.fromJson({'id': 1, 'name': 'Active', 'is_active': true}),
      CehClient.fromJson({'id': 2, 'name': 'Inactive', 'is_active': false}),
    ];

    expect(clients.where((client) => client.isActive).map((c) => c.name),
        ['Active']);
  });
}
