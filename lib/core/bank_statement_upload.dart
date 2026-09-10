import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class BankStatementFile {
  BankStatementFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  void validate() {
    if (!RegExp(r'\.(csv|xlsx)$', caseSensitive: false).hasMatch(name)) {
      throw const FormatException('Choose a CSV or XLSX statement.');
    }
    if (bytes.isEmpty || bytes.length > 10000000) {
      throw const FormatException(
          'Statement must be between 1 byte and 10 MB.');
    }
  }
}

Future<BankStatementFile?> pickBankStatement() async {
  final result =
      await const MethodChannel('com.concreteequipmenthire.ceh/bank_picker')
          .invokeMapMethod<String, dynamic>('pick');
  if (result == null) return null;
  final file =
      BankStatementFile(result['name'] as String, result['bytes'] as Uint8List);
  file.validate();
  return file;
}

class BankUploadRequest extends http.MultipartRequest {
  BankUploadRequest(Uri uri, this.progress) : super('POST', uri);
  final void Function(double) progress;
  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(stream.map((chunk) {
      sent += chunk.length;
      progress(sent / total);
      return chunk;
    }));
  }
}
