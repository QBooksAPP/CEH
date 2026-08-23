<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();production_require_method('POST');$input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $type=strtoupper(trim((string)($input['source_type']??'')));$sourceId=(int)($input['source_record_id']??0);if($sourceId<=0||!in_array($type,['PETTY_CASH_FUNDING','PETTY_CASH_EXPENSE','GENERAL_EXPENSE'],true)) accounts_fail('INVALID_EVIDENCE_SOURCE');
    $mime=strtolower(trim((string)($input['mime_type']??'')));if(!in_array($mime,['image/jpeg','image/png','application/pdf'],true)) accounts_fail('UNSUPPORTED_EVIDENCE_TYPE');
    $filename=production_clean_text($input['filename']??'',255,'EVIDENCE_FILENAME_REQUIRED');$encoded=(string)($input['data_base64']??'');$bytes=base64_decode($encoded,true);if($bytes===false||$bytes===''||strlen($bytes)>8*1024*1024) accounts_fail('INVALID_EVIDENCE_DATA');
    $db=production_db();return accounts_transaction($db,function() use($db,$user,$type,$sourceId,$mime,$filename,$bytes): array {
        if($type==='PETTY_CASH_EXPENSE'){$s=$db->prepare("SELECT custodian_user_id,status FROM qbook_petty_cash_expenses WHERE id=? FOR UPDATE");$s->execute([$sourceId]);$row=$s->fetch();if(!$row)accounts_fail('EXPENSE_NOT_FOUND',404);if(!accounts_can_access_custodian($user,(int)$row['custodian_user_id']))accounts_fail('FORBIDDEN',403);if(!in_array($row['status'],['DRAFT','CORRECTION_REQUIRED'],true))accounts_fail('EXPENSE_LOCKED',409);}
        elseif($type==='GENERAL_EXPENSE'){qbook_require_role($user,['ADMIN']);$s=$db->prepare("SELECT status FROM qbook_general_expenses WHERE id=? FOR UPDATE");$s->execute([$sourceId]);$status=$s->fetchColumn();if($status===false)accounts_fail('EXPENSE_NOT_FOUND',404);if(!in_array($status,['DRAFT','CORRECTION_REQUIRED'],true))accounts_fail('EXPENSE_LOCKED',409);}
        else{qbook_require_role($user,['ADMIN']);$s=$db->prepare("SELECT id FROM qbook_petty_cash_fundings WHERE id=?");$s->execute([$sourceId]);if(!$s->fetch())accounts_fail('FUNDING_NOT_FOUND',404);}
        $hash=hash('sha256',$bytes);$s=$db->prepare("INSERT INTO qbook_financial_evidence(source_type,source_record_id,original_filename,mime_type,byte_size,sha256,storage_driver,evidence_data,uploaded_by) VALUES(?,?,?,?,?,?,'MYSQL_BLOB',?,?)");$s->bindValue(1,$type);$s->bindValue(2,$sourceId,PDO::PARAM_INT);$s->bindValue(3,$filename);$s->bindValue(4,$mime);$s->bindValue(5,strlen($bytes),PDO::PARAM_INT);$s->bindValue(6,$hash);$s->bindValue(7,$bytes,PDO::PARAM_LOB);$s->bindValue(8,(int)$user['id'],PDO::PARAM_INT);$s->execute();$id=(int)$db->lastInsertId();accounts_audit($db,$user,'FINANCIAL_EVIDENCE_UPLOADED','FINANCIAL_EVIDENCE',$id,['source_type'=>$type,'source_record_id'=>$sourceId,'sha256'=>$hash]);return ['evidence'=>['id'=>$id,'filename'=>$filename,'mime_type'=>$mime,'byte_size'=>strlen($bytes),'sha256'=>$hash]];
    });
});
