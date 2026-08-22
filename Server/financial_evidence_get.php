<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();production_require_method('GET');$id=(int)($_GET['evidence_id']??0);if($id<=0)qbook_json(['ok'=>false,'error'=>'EVIDENCE_REQUIRED'],422);
$db=production_db();$s=$db->prepare("SELECT * FROM qbook_financial_evidence WHERE id=?");$s->execute([$id]);$e=$s->fetch();if(!$e)qbook_json(['ok'=>false,'error'=>'EVIDENCE_NOT_FOUND'],404);
$allowed=strtoupper((string)$user['role'])==='ADMIN';if(!$allowed&&$e['source_type']==='PETTY_CASH_EXPENSE'){$x=$db->prepare("SELECT custodian_user_id FROM qbook_petty_cash_expenses WHERE id=?");$x->execute([(int)$e['source_record_id']]);$allowed=(int)$x->fetchColumn()===(int)$user['id'];}
if(!$allowed)qbook_json(['ok'=>false,'error'=>'FORBIDDEN'],403);if($e['storage_driver']!=='MYSQL_BLOB'||$e['evidence_data']===null)qbook_json(['ok'=>false,'error'=>'EVIDENCE_UNAVAILABLE'],409);
$bytes=(string)$e['evidence_data'];if(!hash_equals((string)$e['sha256'],hash('sha256',$bytes)))qbook_json(['ok'=>false,'error'=>'EVIDENCE_INTEGRITY_FAILED'],500);
production_discard_output();header('Content-Type: '.$e['mime_type']);header('Content-Length: '.strlen($bytes));header('Content-Disposition: attachment; filename="evidence-'.$id.'"');header('Cache-Control: private, no-store');header('X-Content-Type-Options: nosniff');echo $bytes;exit;
