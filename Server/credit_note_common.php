<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
function credit_note_rows(PDO $db,string $sql,array $args=[],bool $lock=false):array {
 $q=$db->prepare($sql.($lock?' FOR UPDATE':''));$q->execute($args);return $q->fetchAll();
}
function credit_note_split(int $net,int $vat,int $usedNet,int $usedVat,int $gross):array {
 if($net<0||$vat<0||$usedNet<0||$usedVat<0||$usedNet>$net||$usedVat>$vat)accounts_fail('CREDIT_HISTORY_INTEGRITY_ERROR',409);
 if($gross<=0||$gross>$net+$vat-$usedNet-$usedVat)accounts_fail('CREDIT_EXCEEDS_INVOICE_LINE',409);
 $target=billing_multiply_divide_round_half_up($usedNet+$usedVat+$gross,$vat,$net+$vat);
 $v=max(0,min($gross,$vat-$usedVat,$target-$usedVat));
 $v=max($v,$gross-($net-$usedNet));
 return ['net'=>$gross-$v,'vat'=>$v,'gross'=>$gross];
}
function credit_note_input(array $input):array {
 $id=(int)($input['invoice_id']??0);if($id<=0)accounts_fail('INVOICE_REQUIRED');
 $raw=$input['lines']??null;if(!is_array($raw)||!$raw||count($raw)>100)accounts_fail('CREDIT_LINES_REQUIRED');
 $seen=[];$lines=[];
 foreach($raw as $x){
  if(!is_array($x))accounts_fail('INVALID_CREDIT_LINE');$lid=(int)($x['invoice_line_id']??0);
  if($lid<=0)accounts_fail('INVOICE_LINE_NOT_FOUND',404);
  if(isset($seen[$lid]))accounts_fail('DUPLICATE_CREDIT_INVOICE_LINE',409);$seen[$lid]=true;
  if(array_key_exists('released_m3',$x)||array_key_exists('quantity_treatment',$x))accounts_fail('ALLOCATION_SPECIFIC_RELEASE_REQUIRED');
  $rawReleases=$x['production_releases']??[];if(!is_array($rawReleases)||count($rawReleases)>100)accounts_fail('INVALID_PRODUCTION_RELEASES');
  $seenReleases=[];$releases=[];
  foreach($rawReleases as $r){
   if(!is_array($r))accounts_fail('INVALID_PRODUCTION_RELEASE');$aid=(int)($r['invoice_production_allocation_id']??0);
   if($aid<=0||isset($seenReleases[$aid]))accounts_fail('INVALID_PRODUCTION_ALLOCATION_RELEASE');$seenReleases[$aid]=true;
   $qty=trim((string)($r['released_m3']??''));if(!preg_match('/\A\d{1,8}(?:\.\d{1,2})?\z/',$qty))accounts_fail('INVALID_RELEASED_M3');
   $releases[]=['invoice_production_allocation_id'=>$aid,'released_m3'=>accounts_minor_decimal(accounts_money_minor($qty))];
  }
  usort($releases,fn($a,$b)=>$a['invoice_production_allocation_id']<=>$b['invoice_production_allocation_id']);
  $lines[]=['invoice_line_id'=>$lid,'gross_amount'=>accounts_minor_decimal(accounts_money_minor($x['gross_amount']??'')),'production_releases'=>$releases];
 }
 usort($lines,fn($a,$b)=>$a['invoice_line_id']<=>$b['invoice_line_id']);
 // Require a stable explicit date so a retry across midnight has the same payload.
 return ['invoice_id'=>$id,'credit_date'=>accounts_date($input['credit_date']??''),'reason'=>production_clean_text($input['reason']??'',500,'REASON_REQUIRED'),'lines'=>$lines];
}
function credit_note_contract(PDO $db,int $id,bool $lock=false):array {
 $invoice=billing_invoice_outstanding($db,$id,$lock);$reasons=[];
 $invoice['reference']=billing_ref('INVOICE',$invoice['reference_no']);
 if($invoice['status']!=='ISSUED')$reasons[]='ISSUED_INVOICE_REQUIRED';
 if($invoice['outstanding_minor']<=0)$reasons[]='NO_OUTSTANDING_BALANCE';
 $lines=credit_note_rows($db,'SELECT * FROM qbook_invoice_lines WHERE invoice_id=? ORDER BY id',[$id],$lock);
 foreach($lines as &$l){
  $used=['net'=>0,'vat'=>0,'gross'=>0];
  foreach(credit_note_rows($db,"SELECT cl.net_amount,cl.vat_amount,cl.gross_amount FROM qbook_credit_note_lines cl JOIN qbook_credit_notes c ON c.id=cl.credit_note_id WHERE cl.invoice_line_id=? AND c.status='ISSUED' ORDER BY cl.id",[$l['id']],$lock) as $c)foreach($used as $k=>$_)$used[$k]+=accounts_money_minor($c[$k.'_amount'],false);
  if($used['net']+$used['vat']!==$used['gross']||accounts_money_minor($l['net_amount'],false)+accounts_money_minor($l['vat_amount'],false)!==accounts_money_minor($l['gross_amount'],false))accounts_fail('CREDIT_HISTORY_INTEGRITY_ERROR',409);
  foreach($used as $k=>$v){$original=accounts_money_minor($l[$k.'_amount'],false);if($v<0||$v>$original)accounts_fail('CREDIT_HISTORY_INTEGRITY_ERROR',409);$l['credited_'.$k]=accounts_minor_decimal($v);$l['remaining_'.$k]=accounts_minor_decimal($original-$v);}
  $alloc=credit_note_rows($db,'SELECT * FROM qbook_invoice_production_allocations WHERE invoice_line_id=? ORDER BY id',[$l['id']],$lock);
  foreach($alloc as &$a){$released=0;
   foreach(credit_note_rows($db,"SELECT cr.released_m3 FROM qbook_credit_note_production_releases cr JOIN qbook_credit_note_lines cl ON cl.id=cr.credit_note_line_id JOIN qbook_credit_notes c ON c.id=cl.credit_note_id WHERE cr.invoice_production_allocation_id=? AND c.status='ISSUED' ORDER BY cr.id",[$a['id']],$lock) as $r)$released+=accounts_money_minor($r['released_m3'],false);
   $remaining=accounts_money_minor($a['billed_m3'],false)-$released;if($remaining<0)accounts_fail('QUANTITY_RELEASE_INTEGRITY_ERROR',409);
   $a['released_m3']=accounts_minor_decimal($released);$a['remaining_releasable_m3']=$a['status']==='COMMITTED'?accounts_minor_decimal($remaining):'0.00';
  }unset($a);$l['production_allocations']=$alloc;
 }unset($l);
 return ['invoice'=>$invoice,'can_issue_credit_note'=>$reasons===[],'blocking_reasons'=>$reasons,'outstanding'=>accounts_minor_decimal($invoice['outstanding_minor']),'lines'=>$lines];
}
function credit_note_plan(PDO $db,array $input,bool $lock=false):array {
 $contract=credit_note_contract($db,$input['invoice_id'],$lock);
 if(!$contract['can_issue_credit_note'])accounts_fail($contract['blocking_reasons'][0],409);
 $invoice=$contract['invoice'];if($input['credit_date']<$invoice['invoice_date'])accounts_fail('CREDIT_DATE_BEFORE_INVOICE');
 $byId=[];foreach($contract['lines'] as $l)$byId[(int)$l['id']]=$l;
 $lines=[];$net=$vat=$gross=0;
 foreach($input['lines'] as $r){$l=$byId[$r['invoice_line_id']]??null;if(!$l)accounts_fail('INVOICE_LINE_NOT_FOUND',404);
  $split=credit_note_split(accounts_money_minor($l['net_amount'],false),accounts_money_minor($l['vat_amount'],false),accounts_money_minor($l['credited_net'],false),accounts_money_minor($l['credited_vat'],false),accounts_money_minor($r['gross_amount']));
  $alloc=[];foreach($l['production_allocations'] as $a)$alloc[(int)$a['id']]=$a;
  foreach($r['production_releases'] as $release){$a=$alloc[$release['invoice_production_allocation_id']]??null;if(!$a||$a['status']!=='COMMITTED')accounts_fail('PRODUCTION_ALLOCATION_RELEASE_MISMATCH',409);if(accounts_money_minor($release['released_m3'])>accounts_money_minor($a['remaining_releasable_m3'],false))accounts_fail('QUANTITY_RELEASE_EXCEEDS_ALLOCATION_M3',409);}
  $net+=$split['net'];$vat+=$split['vat'];$gross+=$split['gross'];
  $lines[]=['original'=>$l,'net_amount'=>accounts_minor_decimal($split['net']),'vat_amount'=>accounts_minor_decimal($split['vat']),'gross_amount'=>accounts_minor_decimal($split['gross']),'production_releases'=>$r['production_releases']];
 }
 if($gross>$invoice['outstanding_minor'])accounts_fail('CREDIT_EXCEEDS_OUTSTANDING',409);
 return ['invoice'=>$invoice,'credit_date'=>$input['credit_date'],'reason'=>$input['reason'],'lines'=>$lines,'net_amount'=>accounts_minor_decimal($net),'vat_amount'=>accounts_minor_decimal($vat),'total_amount'=>accounts_minor_decimal($gross),'outstanding_after'=>accounts_minor_decimal($invoice['outstanding_minor']-$gross)];
}
function credit_note_issue_execute(PDO $db,array $user,array $raw):array {
 if(strtoupper((string)($user['role']??''))!=='ADMIN')accounts_fail('FORBIDDEN',403);
 $input=credit_note_input($raw); // Duplicates and malformed input rejected before any write.
 $key=(string)($raw['request_key']??'');if(!preg_match('/\A[a-zA-Z0-9-]{32,80}\z/',$key))accounts_fail('IDEMPOTENCY_KEY_REQUIRED');
 $digest=hash('sha256',json_encode($input,JSON_THROW_ON_ERROR));
 return accounts_transaction($db,function()use($db,$user,$input,$key,$digest){
  $locked=credit_note_rows($db,'SELECT id FROM qbook_invoices WHERE id=?',[$input['invoice_id']],true);if(!$locked)accounts_fail('INVOICE_NOT_FOUND',404);
  $prior=credit_note_rows($db,'SELECT * FROM qbook_credit_note_requests WHERE actor_id=? AND request_key=?',[$user['id'],$key],true);
  if($prior){if(!hash_equals($prior[0]['payload_sha256'],$digest))accounts_fail('IDEMPOTENCY_PAYLOAD_MISMATCH',409);return json_decode($prior[0]['result_json'],true,512,JSON_THROW_ON_ERROR);}
  $plan=credit_note_plan($db,$input,true);$invoice=$plan['invoice'];$ref=billing_allocate_reference($db,'qbook_credit_note_references');
  $db->prepare('INSERT INTO qbook_credit_notes(reference_no,invoice_id,credit_date,reason,net_amount,vat_amount,total_amount,created_by,document_snapshot) VALUES(?,?,?,?,?,?,?,?,?)')->execute([$ref,$invoice['id'],$input['credit_date'],$input['reason'],$plan['net_amount'],$plan['vat_amount'],$plan['total_amount'],$user['id'],json_encode($plan,JSON_THROW_ON_ERROR)]);
  $cid=(int)$db->lastInsertId();$jl=[];$quantityAudit=[];
  foreach($plan['lines'] as $n=>$l){$ol=$l['original'];
   $db->prepare('INSERT INTO qbook_credit_note_lines(credit_note_id,invoice_line_id,line_no,description,revenue_account_id,net_amount,vat_amount,gross_amount,project_id,mixer_id) VALUES(?,?,?,?,?,?,?,?,?,?)')->execute([$cid,$ol['id'],$n+1,$ol['description'],$ol['revenue_account_id'],$l['net_amount'],$l['vat_amount'],$l['gross_amount'],$ol['project_id'],$ol['mixer_id']]);$lid=(int)$db->lastInsertId();
   $net=accounts_money_minor($l['net_amount'],false);if($net>0)$jl[]=['account_id'=>(int)$ol['revenue_account_id'],'debit_minor'=>$net,'description'=>$input['reason'],'client_id'=>(int)$invoice['client_id'],'project_id'=>$ol['project_id'],'mixer_id'=>$ol['mixer_id']];
   foreach($l['production_releases'] as $r){$db->prepare('INSERT INTO qbook_credit_note_production_releases(credit_note_line_id,invoice_production_allocation_id,released_m3) VALUES(?,?,?)')->execute([$lid,$r['invoice_production_allocation_id'],$r['released_m3']]);$quantityAudit[]=['credit_note_line_id'=>$lid,'invoice_line_id'=>(int)$ol['id']]+$r;}
  }
  $vat=accounts_money_minor($plan['vat_amount'],false);if($vat>0)$jl[]=['account_id'=>billing_account_role($db,'OUTPUT_VAT_PAYABLE'),'debit_minor'=>$vat,'description'=>'VAT credit '.billing_ref('CREDIT_NOTE',$ref),'client_id'=>(int)$invoice['client_id']];
  $jl[]=['account_id'=>billing_account_role($db,'TRADE_RECEIVABLES'),'credit_minor'=>accounts_money_minor($plan['total_amount']),'description'=>billing_ref('CREDIT_NOTE',$ref),'client_id'=>(int)$invoice['client_id']];
  $j=accounts_post_journal($db,$user,['transaction_date'=>$input['credit_date'],'description'=>'Credit note '.billing_ref('CREDIT_NOTE',$ref),'source_module'=>'CREDIT_NOTE','source_record_id'=>$cid,'approved_by'=>$user['id']],$jl);
  $db->prepare("UPDATE qbook_credit_notes SET status='ISSUED',journal_id=?,issued_by=?,issued_at=UTC_TIMESTAMP() WHERE id=?")->execute([$j['id'],$user['id'],$cid]);
  $db->prepare('INSERT INTO qbook_credit_note_allocations(credit_note_id,invoice_id,amount) VALUES(?,?,?)')->execute([$cid,$invoice['id'],$plan['total_amount']]);
  $result=['credit_note'=>['id'=>$cid,'reference'=>billing_ref('CREDIT_NOTE',$ref),'status'=>'ISSUED'],'journal'=>$j,'outstanding_after'=>$plan['outstanding_after']];
  $db->prepare('INSERT INTO qbook_credit_note_requests(actor_id,request_key,payload_sha256,credit_note_id,result_json) VALUES(?,?,?,?,?)')->execute([$user['id'],$key,$digest,$cid,json_encode($result,JSON_THROW_ON_ERROR)]);
  accounts_audit($db,$user,'CREDIT_NOTE_ISSUED','CREDIT_NOTE',$cid,['invoice_id'=>$invoice['id'],'journal_id'=>$j['id'],'production_quantity'=>$quantityAudit,'request_key'=>$key,'payload_sha256'=>$digest]);
  return $result;
 });
}
