import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'api_client.dart';
import '../models/banking_workspace.dart';
import '../models/session.dart';

/// Downloads authenticated bytes only into private cache; no public URL or share.
Future<String> cacheBankOriginal(
    CehApiClient api, CehSession session, Map<String, dynamic> record) async {
  final bytes = await api.bankOriginal(session, bankInt(record['document_id']));
  if (bytes.length != bankInt(record['byte_size']) ||
      sha256.convert(bytes).toString() != record['file_sha256']) {
    throw const ApiException('STATEMENT_INTEGRITY_FAILED');
  }
  final cache = await getTemporaryDirectory();
  final dir = Directory('${cache.path}/bank-originals');
  await dir.create(recursive: true);
  final ext = record['file_type'] == 'XLSX' ? 'xlsx' : 'csv';
  final file =
      File('${dir.path}/statement-${bankInt(record['document_id'])}.$ext');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> viewBankOriginal(String path) =>
    const MethodChannel('com.concreteequipmenthire.ceh/bank_document')
        .invokeMethod<void>('viewOriginal', {'path': path});
