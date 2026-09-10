<?php
// CLI only. Empty-feature rollback; refuses to destroy imported evidence/rows.
declare(strict_types=1);
if(PHP_SAPI!=='cli')exit(1);
if(($argv[1]??'')!=='--confirmed-staging-maintenance')exit("Requires confirmed staging maintenance and schema backup\n");
if(!function_exists('posix_geteuid')||posix_geteuid()!==0)exit("cehadmin/root required\n");
$db=new PDO('mysql:unix_socket=/var/run/mysqld/mysqld.sock;dbname=ceh_staging','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
if($db->query('SELECT DATABASE()')->fetchColumn()!=='ceh_staging')exit(1);
if((int)$db->query('SELECT COUNT(*) FROM qbook_bank_statement_documents')->fetchColumn()!==0||(int)$db->query('SELECT COUNT(*) FROM qbook_bank_statement_rows WHERE source_row IS NOT NULL')->fetchColumn()!==0)exit("STOP: retain schema and evidence; application-only rollback required\n");
if($db->query('SELECT 1 FROM qbook_bank_statement_rows GROUP BY bank_account_id,row_fingerprint HAVING COUNT(*)>1 LIMIT 1')->fetchColumn())exit("STOP: duplicate legacy fingerprints\n");
$db->exec('ALTER TABLE qbook_bank_statement_rows DROP INDEX uq_bank_physical_row, DROP INDEX idx_bank_content_fingerprint, ADD UNIQUE KEY uq_bank_statement_fingerprint(bank_account_id,row_fingerprint), DROP COLUMN source_sheet,DROP COLUMN source_row,DROP COLUMN occurrence_number,DROP COLUMN value_date,DROP COLUMN statement_balance');
$db->exec('ALTER TABLE qbook_bank_import_batches DROP FOREIGN KEY fk_bank_batch_document,DROP INDEX uq_bank_batch_document,DROP COLUMN document_id');
$db->exec('DROP TABLE qbook_bank_statement_documents');
echo "EMPTY_FEATURE_ROLLBACK_COMPLETED\n";
