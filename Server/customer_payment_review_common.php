<?php
declare(strict_types=1);
require_once __DIR__.'/bank_payment_common.php';
require_once __DIR__.'/customer_payment_draft_state.php';

function customer_payment_review_result(PDO $db, array $r): array {
    $intent = customer_payment_reviewed_intent($r);
    $r['reference'] = billing_ref('RECEIPT', $r['reference_no']);
    $r['review_required'] = customer_payment_legacy_review_required($r);
    $r['reviewed_allocations'] = $intent['allocations'] ?? null;
    $r['client_credit_confirmed'] = $intent['client_credit_confirmed'] ?? false;
    unset($r['creation_request_key'], $r['posting_payload_sha256'], $r['draft_payload']);
    $q = $db->prepare('SELECT * FROM qbook_customer_receipt_allocations WHERE receipt_id=? ORDER BY id');
    $q->execute([$r['id']]);
    $historical = $q->fetchAll();
    $q = $db->prepare('SELECT * FROM qbook_receipt_wht WHERE receipt_id=? ORDER BY id');
    $q->execute([$r['id']]);
    return ['receipt'=>$r,'historical_allocations'=>$historical,'historical_wht'=>$q->fetchAll()];
}

function customer_payment_review_read(PDO $db,array $user,int $id): array {
    if (($user['role']??'')!=='ADMIN') accounts_fail('FORBIDDEN',403);
    $q=$db->prepare('SELECT r.*,b.name current_bank_name FROM qbook_customer_receipts r JOIN qbook_bank_accounts b ON b.id=r.bank_account_id WHERE r.id=? AND r.statement_row_id IS NULL');
    $q->execute([$id]);$r=$q->fetch();
    if(!$r) accounts_fail('ORDINARY_PAYMENT_DRAFT_NOT_FOUND',404);
    return customer_payment_review_result($db,$r);
}

function customer_payment_review_edit(PDO $db,array $user,array $in): array {
    if (($user['role']??'')!=='ADMIN') accounts_fail('FORBIDDEN',403);
    $id=(int)($in['receipt_id']??0);
    return bank_payment_transaction($db,$id,function()use($db,$user,$in,$id):array {
        $q=$db->prepare('SELECT * FROM qbook_customer_receipts WHERE id=? FOR UPDATE');
        $q->execute([$id]);$r=$q->fetch();
        if(!$r || $r['statement_row_id']!==null) accounts_fail('ORDINARY_PAYMENT_REQUIRED',409);
        $cancel=($in['action']??'')==='CANCEL';
        if($cancel && $r['status']==='CANCELLED') return customer_payment_review_result($db,$r)+['replayed'=>true];
        if($r['status']!=='DRAFT'||$r['journal_id']!==null) accounts_fail('PAYMENT_NOT_EDITABLE',409);
        if(!$cancel && ($in['action']??'')!=='SAVE_REVIEW') accounts_fail('INVALID_REVIEW_ACTION');
        $old=customer_payment_reviewed_intent($r);
        if(!customer_payment_legacy_review_required($r) && $old===null) accounts_fail('LEGACY_PAYMENT_REVIEW_NOT_REQUIRED',409);
        $request=(string)($in['request_key']??'');
        if(!preg_match('/^[a-f0-9]{64}$/D',$request)) accounts_fail('PAYMENT_REQUEST_KEY_REQUIRED');
        $requestHash=bank_payment_payload_hash($in);
        if(!$cancel && $old!==null && ($old['request_key']??'')===$request){
            if(!hash_equals((string)$old['request_hash'],$requestHash)) accounts_fail('PAYMENT_RETRY_PAYLOAD_MISMATCH',409);
            return customer_payment_review_result($db,$r)+['replayed'=>true];
        }
        if((int)($in['draft_revision']??-1)!==(int)$r['draft_revision']) accounts_fail('PAYMENT_DRAFT_CHANGED_REFRESH',409);
        if($cancel){
            $reason=production_clean_text($in['reason']??'',500,'CANCELLATION_REASON_REQUIRED');
            $db->prepare("UPDATE qbook_customer_receipts SET status='CANCELLED',cancelled_by=?,cancelled_at=UTC_TIMESTAMP(),cancellation_reason=?,draft_revision=draft_revision+1 WHERE id=?")
                ->execute([$user['id'],$reason,$id]);
            accounts_audit($db,$user,'CUSTOMER_RECEIPT_DRAFT_CANCELLED','CUSTOMER_RECEIPT',$id,['reason'=>$reason,'legacy_review'=>true,'journal_posted'=>false]);
        }else{
            if(($in['review_completed']??false)!==true || !array_key_exists('allocations',$in)) accounts_fail('LEGACY_PAYMENT_REVIEW_REQUIRED',409);
            $alloc=$in['allocations'];
            if(!is_array($alloc)||!array_is_list($alloc)||count($alloc)>100) accounts_fail('INVALID_ALLOCATIONS');
            foreach($alloc as $a) if(!is_array($a)) accounts_fail('INVALID_ALLOCATION');
            // Existing historical rows must not be overwritten or duplicated by reconstruction.
            foreach(['qbook_customer_receipt_allocations','qbook_receipt_wht'] as $table){
                $s=$db->prepare("SELECT COUNT(*) FROM $table WHERE receipt_id=?");$s->execute([$id]);
                if((int)$s->fetchColumn()>0) accounts_fail('LEGACY_PAYMENT_HISTORICAL_SETTLEMENT_REVIEW_REQUIRED',409);
            }
            $cash=0;$seen=[];
            usort($alloc,static fn($a,$b)=>(int)($a['invoice_id']??0)<=>(int)($b['invoice_id']??0));
            foreach($alloc as &$a){
                if(!is_array($a)) accounts_fail('INVALID_ALLOCATION');
                $invoiceId=(int)($a['invoice_id']??0);
                if(isset($seen[$invoiceId])) accounts_fail('DUPLICATE_INVOICE_ALLOCATION',409);
                $seen[$invoiceId]=true;
                $invoice=billing_invoice_outstanding($db,$invoiceId,true);
                if($invoice['status']!=='ISSUED'||(int)$invoice['client_id']!==(int)$r['client_id']) accounts_fail('INVOICE_ALLOCATION_MISMATCH',409);
                $c=accounts_money_minor($a['cash_amount']??'0',false);
                $w=accounts_money_minor($a['wht_amount']??'0',false);
                if($c+$w<=0||$c+$w>$invoice['outstanding_minor']) accounts_fail('INVOICE_OVERALLOCATION',409);
                if($w>0){
                    $code=billing_tax_code($db,$a['wht_tax_code_id']??0,'WHT',$r['receipt_date']);
                    $base=accounts_money_minor($a['wht_calculation_base_amount']??'');
                    $suggested=billing_percent_amount($base,(string)$code['rate_percent']);
                    if($suggested!==$w && trim((string)($a['wht_override_reason']??''))==='') accounts_fail('WHT_OVERRIDE_REASON_REQUIRED',409);
                }
                $a['outstanding_minor_snapshot']=$invoice['outstanding_minor'];
                $cash+=$c;
            }unset($a);
            $received=accounts_money_minor($r['cash_amount'],false);
            if($cash>$received) accounts_fail('RECEIPT_OVERALLOCATION',409);
            if($cash<$received && ($in['client_credit_confirmed']??false)!==true) accounts_fail('EXPLICIT_CLIENT_CREDIT_DECISION_REQUIRED',409);
            $payload=['kind'=>'LEGACY_REVIEW_V1','allocations'=>$alloc,'client_credit_confirmed'=>($in['client_credit_confirmed']??false)===true,
                'reviewed_by'=>(int)$user['id'],'request_key'=>$request,'request_hash'=>$requestHash];
            $encoded=json_encode($payload,JSON_THROW_ON_ERROR);
            if(strlen($encoded)>100000) accounts_fail('INVALID_ALLOCATIONS');
            $db->prepare('UPDATE qbook_customer_receipts SET draft_payload=?,draft_revision=draft_revision+1,creation_request_key=COALESCE(creation_request_key,?) WHERE id=?')
                ->execute([$encoded,bin2hex(random_bytes(32)),$id]);
            accounts_audit($db,$user,'CUSTOMER_RECEIPT_LEGACY_REVIEW_SAVED','CUSTOMER_RECEIPT',$id,['journal_posted'=>false,'draft_revision'=>(int)$r['draft_revision']+1]);
        }
        $q->execute([$id]);return customer_payment_review_result($db,$q->fetch());
    });
}
