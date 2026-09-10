<?php
declare(strict_types=1);
require_once __DIR__.'/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
$q=production_db()->prepare('SELECT file_type,sha256,document_data FROM qbook_bank_statement_documents WHERE id=?');$q->execute([(int)($_GET['document_id']??0)]);$r=$q->fetch();
if(!$r)qbook_json(['ok'=>false,'error'=>'STATEMENT_NOT_FOUND'],404);
if(!hash_equals($r['sha256'],hash('sha256',$r['document_data'])))qbook_json(['ok'=>false,'error'=>'STATEMENT_INTEGRITY_FAILED'],500);
header('Content-Type: application/octet-stream');header('X-Content-Type-Options: nosniff');header('Cache-Control: no-store');header('Content-Disposition: attachment; filename="CEH-Bank-Statement.'.strtolower($r['file_type']).'"');header('Content-Length: '.strlen($r['document_data']));echo $r['document_data'];
