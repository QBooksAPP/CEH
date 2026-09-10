-- READ ONLY. Administrator must select ceh_staging explicitly. Stop on mismatch.
SELECT DATABASE() AS selected_database;
SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()
 AND TABLE_NAME IN('qbook_bank_accounts','qbook_bank_import_batches','qbook_bank_statement_rows');
SELECT COUNT(*) AS new_document_table_must_be_zero FROM information_schema.TABLES
 WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='qbook_bank_statement_documents';
SELECT COUNT(*) AS batches FROM qbook_bank_import_batches;
SELECT COUNT(*) AS rows_before FROM qbook_bank_statement_rows;
SELECT COUNT(*) AS journals FROM qbook_financial_journals;
SELECT COUNT(*) AS journal_lines FROM qbook_financial_journal_lines;
SELECT @@max_allowed_packet AS packet_bytes;
SELECT r.id FROM qbook_bank_statement_rows r
 JOIN qbook_general_expense_refunds f ON f.statement_row_id=r.id
 JOIN qbook_bank_matches m ON m.statement_row_id=r.id;
SELECT created_from_statement_row_id,COUNT(*) AS active_expenses
 FROM qbook_general_expenses WHERE created_from_statement_row_id IS NOT NULL
 AND status NOT IN('CANCELLED_NOT_SPENT','VOIDED') GROUP BY created_from_statement_row_id HAVING COUNT(*)>1;
SELECT f.statement_row_id AS conflicting_refund_receipt FROM qbook_general_expense_refunds f
 JOIN qbook_customer_receipts c ON c.statement_row_id=f.statement_row_id AND c.status='POSTED';
SELECT e.created_from_statement_row_id AS conflicting_expense_receipt FROM qbook_general_expenses e
 JOIN qbook_customer_receipts c ON c.statement_row_id=e.created_from_statement_row_id AND c.status='POSTED'
 WHERE e.status NOT IN('CANCELLED_NOT_SPENT','VOIDED');
SELECT e.created_from_statement_row_id AS conflicting_expense_refund FROM qbook_general_expenses e
 JOIN qbook_general_expense_refunds f ON f.statement_row_id=e.created_from_statement_row_id
 WHERE e.status NOT IN('CANCELLED_NOT_SPENT','VOIDED');
SELECT m.statement_row_id AS conflicting_match_expense FROM qbook_bank_matches m
 JOIN qbook_general_expenses e ON e.created_from_statement_row_id=m.statement_row_id
 WHERE e.status NOT IN('CANCELLED_NOT_SPENT','VOIDED') AND NOT(m.source_type='GENERAL_EXPENSE' AND m.source_record_id=e.id);
SELECT m.statement_row_id AS conflicting_match_receipt FROM qbook_bank_matches m
 JOIN qbook_customer_receipts c ON c.statement_row_id=m.statement_row_id AND c.status='POSTED'
 WHERE NOT(m.source_type='CUSTOMER_RECEIPT' AND m.source_record_id=c.id);
SHOW CREATE TABLE qbook_bank_statement_rows;
SHOW CREATE TABLE qbook_bank_import_batches;
