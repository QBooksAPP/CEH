<?php
declare(strict_types=1);
require_once __DIR__.'/bank_statement_parser.php';
function bank_admin(array $user):void {if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);}
/** Suggestions never consume a row and never establish duplicate identity. */
function bank_import_suggestion(PDO $db,int $bank,array $row):array {
 $minor=bank_amount($row['amount']);$reference=$row['reference'];
 if($minor>=0)return ['UNMATCHED',null,null];
 $start=(new DateTimeImmutable($row['date']))->modify('-3 days')->format('Y-m-d');
 $end=(new DateTimeImmutable($row['date']))->modify('+3 days')->format('Y-m-d');
 if($reference!==''){
  $q=$db->prepare('SELECT id FROM qbook_petty_cash_fundings WHERE bank_account_id=? AND amount=? AND funding_date BETWEEN ? AND ? AND LOWER(TRIM(bank_reference))=LOWER(TRIM(?)) AND journal_id IS NOT NULL LIMIT 2');
  $q->execute([$bank,accounts_minor_decimal(-$minor),$start,$end,$reference]);$matches=$q->fetchAll();
  if(count($matches)===1)return ['POTENTIAL_MATCH','PETTY_CASH_FUNDING',(int)$matches[0]['id']];
 }
 $q=$db->prepare("SELECT id FROM qbook_general_expenses WHERE bank_account_id=? AND amount=? AND expense_date BETWEEN ? AND ? AND status='APPROVED' AND journal_id IS NOT NULL AND ((?<>'' AND LOWER(TRIM(COALESCE(bank_reference,'')))=LOWER(TRIM(?))) OR (?='' AND supplier_name_snapshot IS NOT NULL AND LOWER(?) LIKE CONCAT('%',LOWER(supplier_name_snapshot),'%'))) LIMIT 2");
 $q->execute([$bank,accounts_minor_decimal(-$minor),$start,$end,$reference,$reference,$reference,$row['narration']]);$matches=$q->fetchAll();
 return count($matches)===1?['POTENTIAL_MATCH','GENERAL_EXPENSE',(int)$matches[0]['id']]:['UNMATCHED',null,null];
}
function bank_import_preview(PDO $db,array $user,int $bank,string $filename,string $path,string $adapter):array {
 bank_admin($user);$filename=basename(str_replace('\\','/',$filename));
 $filename=production_clean_text($filename,255,'STATEMENT_FILENAME_REQUIRED');
 $type=strtoupper(pathinfo($filename,PATHINFO_EXTENSION));$parsed=bank_parse_file($path,$type,$adapter);
 return accounts_transaction($db,function()use($db,$user,$bank,$filename,$type,$path,$parsed,$adapter){
  $b=$db->prepare("SELECT id FROM qbook_bank_accounts WHERE id=? AND is_active=1 AND currency='NGN' FOR UPDATE");$b->execute([$bank]);if(!$b->fetch())accounts_fail('ACTIVE_NGN_BANK_REQUIRED');
  $q=$db->prepare('SELECT id FROM qbook_bank_statement_documents WHERE bank_account_id=? AND sha256=?');$q->execute([$bank,$parsed['file_sha256']]);
  if($id=$q->fetchColumn())return ['document_id'=>(int)$id,'replayed'=>true];
  $bytes=file_get_contents($path);if(hash('sha256',$bytes)!==$parsed['file_sha256'])accounts_fail('STATEMENT_CHANGED');
  $q=$db->prepare('INSERT INTO qbook_bank_statement_documents(bank_account_id,original_filename,file_type,byte_size,sha256,document_data,adapter,preview_json,uploaded_by) VALUES(?,?,?,?,?,?,?,?,?)');
  $q->execute([$bank,$filename,$type,strlen($bytes),$parsed['file_sha256'],$bytes,$adapter,json_encode($parsed,JSON_THROW_ON_ERROR),$user['id']]);$id=(int)$db->lastInsertId();
  accounts_audit($db,$user,'BANK_STATEMENT_UPLOADED','BANK_DOCUMENT',$id,['bank_account_id'=>$bank,'sha256'=>$parsed['file_sha256'],'byte_size'=>strlen($bytes),'adapter'=>$adapter]);
  return ['document_id'=>$id,'replayed'=>false];
 });
}
function bank_import_plan(PDO $db,int $id,bool $lock=false):array {
 $suffix=$lock?' FOR UPDATE':'';
 $q=$db->prepare('SELECT id,bank_account_id,original_filename,file_type,byte_size,sha256,adapter,preview_json,uploaded_by,uploaded_at FROM qbook_bank_statement_documents WHERE id=?'.$suffix);$q->execute([$id]);$doc=$q->fetch();if(!$doc)accounts_fail('STATEMENT_NOT_FOUND',404);
 $p=json_decode($doc['preview_json'],true,512,JSON_THROW_ON_ERROR);unset($doc['preview_json']);
 $bankInfo=$db->prepare('SELECT id,name,bank_name,currency FROM qbook_bank_accounts WHERE id=?');$bankInfo->execute([$doc['bank_account_id']]);$p['bank']=$bankInfo->fetch();
 $b=$db->prepare('SELECT id,document_id FROM qbook_bank_import_batches WHERE bank_account_id=? AND file_sha256=?'.$suffix);$b->execute([$doc['bank_account_id'],$doc['sha256']]);$batch=$b->fetch();
 $check=$db->prepare('SELECT id FROM qbook_bank_statement_rows WHERE bank_account_id=? AND row_fingerprint=? LIMIT 1'.$suffix);$already=0;
 foreach($p['rows'] as &$row){
  if($row['outcome']==='INVALID')continue;
  if($batch&&(int)$batch['document_id']===$id){$row['outcome']='ALREADY IMPORTED';$already++;continue;}
  $check->execute([$doc['bank_account_id'],$row['fingerprint']]);
  if($check->fetchColumn()){$row['outcome']='INVALID';$row['reason']='AMBIGUOUS_OVERLAPPING_STATEMENT';$p['summary']['can_import']=false;}
 }unset($row);
 $p['summary']['invalid_rows']=count(array_filter($p['rows'],fn($r)=>$r['outcome']==='INVALID'));
 $p['summary']['already_imported_source_rows']=$already;
 if($batch&&(int)$batch['document_id']!==$id){$p['summary']['can_import']=false;$p['summary']['errors'][]='LEGACY_BATCH_REQUIRES_REVIEW';}
 $p['document']=$doc;$p['batch_id']=$batch?(int)$batch['id']:null;
 $p['confirmation_sha256']=hash('sha256',json_encode($p,JSON_THROW_ON_ERROR));return $p;
}
function bank_import_commit(PDO $db,array $user,int $id,string $confirmation):array {
 bank_admin($user);
 return accounts_transaction($db,function()use($db,$user,$id,$confirmation){
  $q=$db->prepare('SELECT bank_account_id FROM qbook_bank_statement_documents WHERE id=?');$q->execute([$id]);$bank=$q->fetchColumn();if(!$bank)accounts_fail('STATEMENT_NOT_FOUND',404);
  $q=$db->prepare('SELECT id FROM qbook_bank_accounts WHERE id=? AND is_active=1 FOR UPDATE');$q->execute([$bank]);if(!$q->fetch())accounts_fail('ACTIVE_BANK_ACCOUNT_REQUIRED');
  $p=bank_import_plan($db,$id,true);
  $integrity=$db->prepare('SELECT SHA2(document_data,256)=sha256 AND OCTET_LENGTH(document_data)=byte_size FROM qbook_bank_statement_documents WHERE id=?');$integrity->execute([$id]);if(!(int)$integrity->fetchColumn())accounts_fail('STATEMENT_INTEGRITY_FAILED');
  if(!$p['summary']['can_import'])accounts_fail('STATEMENT_REVIEW_REQUIRED',409);
  if($p['batch_id'])return ['batch_id'=>$p['batch_id'],'replayed'=>true,'journal_posted'=>false];
  if(!hash_equals($p['confirmation_sha256'],$confirmation))accounts_fail('PREVIEW_CHANGED',409);
  $d=$p['document'];$s=$p['summary'];
  $q=$db->prepare('INSERT INTO qbook_bank_import_batches(bank_account_id,original_filename,file_type,file_sha256,statement_from,statement_to,opening_balance,closing_balance,imported_by,document_id) VALUES(?,?,?,?,?,?,?,?,?,?)');
  $q->execute([$bank,$d['original_filename'],$d['file_type'],$d['sha256'],$s['statement_from'],$s['statement_to'],$s['opening_balance'],$s['closing_balance'],$user['id'],$id]);$batch=(int)$db->lastInsertId();
  $q=$db->prepare('INSERT INTO qbook_bank_statement_rows(import_batch_id,bank_account_id,transaction_date,amount,bank_reference,narration,row_fingerprint,status,source_sheet,source_row,occurrence_number,value_date,statement_balance,potential_source_type,potential_source_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
  foreach($p['rows'] as $row){[$status,$sourceType,$sourceId]=bank_import_suggestion($db,(int)$bank,$row);$q->execute([$batch,$bank,$row['date'],$row['amount'],$row['reference']?:null,$row['narration'],$row['fingerprint'],$status,$row['source_sheet'],$row['source_row'],$row['occurrence'],$row['value_date'],$row['balance'],$sourceType,$sourceId]);}
  accounts_audit($db,$user,'BANK_STATEMENT_IMPORTED','BANK_IMPORT',$batch,['document_id'=>$id,'sha256'=>$d['sha256'],'rows'=>count($p['rows']),'adapter'=>$d['adapter'],'journal_posted'=>false]);
  return ['batch_id'=>$batch,'imported'=>count($p['rows']),'outcome'=>'IMPORTED','replayed'=>false,'journal_posted'=>false];
 });
}
