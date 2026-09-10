import 'banking_workspace.dart';

/// Server totals and confirmation identity; never derive totals from page rows.
class BankImportPreview {
  BankImportPreview(this.json);
  final Map<String, dynamic> json;
  Map<String, dynamic> get summary => bankMap(json['summary']);
  Map<String, dynamic> get document => bankMap(json['document']);
  int get documentId => bankInt(document['id']);
  int get batchId => bankInt(json['batch_id']);
  String get confirmation => bankText(json['confirmation_sha256']);
  bool get alreadyImported => batchId > 0;
  int get ambiguousRows => bankInt(summary['ambiguous_overlap_rows']);
  bool get canConfirm =>
      !alreadyImported &&
      summary['can_import'] == true &&
      bankInt(summary['invalid_rows']) == 0 &&
      ambiguousRows == 0 &&
      documentId > 0 &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(confirmation);
}
