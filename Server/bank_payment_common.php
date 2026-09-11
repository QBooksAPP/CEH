<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
require_once __DIR__.'/bank_row_usage.php';

function bank_payment_payload_hash(array $input):string {
    // Exact request identity: reordered object keys do not change a replay;
    // changed allocation values do. No client-supplied hash is trusted.
    $canonical=function(mixed $v)use(&$canonical):mixed {
        if(!is_array($v))return $v;
        if(!array_is_list($v))ksort($v);
        foreach($v as &$item)$item=$canonical($item);unset($item);return $v;
    };
    return hash('sha256',json_encode($canonical($input),JSON_THROW_ON_ERROR));
}

function bank_payment_transaction(PDO $db,int $id,callable $action):mixed {
    if($db->inTransaction())throw new LogicException('Payment transaction must be outermost');
    $q=$db->prepare('SELECT statement_row_id FROM qbook_customer_receipts WHERE id=?');$q->execute([$id]);$hint=$q->fetch();
    if(!$hint)accounts_fail('RECEIPT_NOT_FOUND',404);
    $row=$hint['statement_row_id'];
    return bank_ownership_transaction($db,function()use($db,$id,$row,$action){
        if($row!==null){$q=$db->prepare('SELECT id FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE');$q->execute([$row]);if(!$q->fetch())accounts_fail('BANK_ROW_NOT_FOUND',404);}
        $q=$db->prepare('SELECT statement_row_id FROM qbook_customer_receipts WHERE id=? FOR UPDATE');$q->execute([$id]);$current=$q->fetch();
        if(!$current||(string)$current['statement_row_id']!==(string)$row)accounts_fail('PAYMENT_CHANGED_REFRESH',409);
        return $action();
    });
}

function bank_payment_statement(PDO $db,array $receipt):array {
    $row=bank_row_available($db,(int)$receipt['statement_row_id'],'CUSTOMER_RECEIPT',(int)$receipt['id']);
    if(accounts_money_minor($row['amount'],false)<=0||(int)$row['bank_account_id']!==(int)$receipt['bank_account_id']
        ||accounts_money_minor($row['amount'],false)!==accounts_money_minor($receipt['cash_amount'],false)
        ||$row['transaction_date']!==$receipt['receipt_date']||(string)$row['bank_reference']!==(string)$receipt['bank_reference'])accounts_fail('STATEMENT_FIELDS_LOCKED',409);
    return $row;
}

function bank_payment_result(PDO $db,array $receipt,bool $replayed=false):array {
    $out=$receipt;
    $out['reference']=billing_ref('RECEIPT',$receipt['reference_no']);
    $out['draft_payload']=json_decode((string)($receipt['draft_payload']??'null'),true);
    // Resolve business references independently of the outstanding-invoice list.
    // Do not discard intent for an invoice which is now settled or void.
    if(is_array($out['draft_payload']))foreach($out['draft_payload'] as &$allocation){
        if(!is_array($allocation))continue;
        $q=$db->prepare('SELECT reference_no FROM qbook_invoices WHERE id=? AND client_id=?');
        $q->execute([(int)($allocation['invoice_id']??0),$receipt['client_id']]);$ref=$q->fetchColumn();
        if($ref!==false)$allocation['invoice_reference']=billing_ref('INVOICE',$ref);
    }unset($allocation);
    unset($out['posting_payload_sha256'],$out['creation_request_key']);
    $journal=null;
    if($receipt['journal_id']!==null){$q=$db->prepare('SELECT id,reference_no,status FROM qbook_financial_journals WHERE id=?');$q->execute([$receipt['journal_id']]);$journal=$q->fetch();}
    return ['receipt'=>$out,'journal'=>$journal,'replayed'=>$replayed];
}

function bank_payment_read(PDO $db,array $user,int $rowId):array {
    if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);
    return accounts_transaction($db,function()use($db,$rowId):array {
        $q=$db->prepare('SELECT id,bank_account_id,amount,transaction_date,value_date,bank_reference,narration,import_batch_id,source_sheet,source_row FROM qbook_bank_statement_rows WHERE id=?');$q->execute([$rowId]);$row=$q->fetch();
        if(!$row||accounts_money_minor($row['amount'],false)<=0)accounts_fail('UNMATCHED_BANK_CREDIT_REQUIRED',409);
        $q=$db->prepare("SELECT * FROM qbook_customer_receipts WHERE statement_row_id=? AND status<>'CANCELLED' ORDER BY id DESC LIMIT 1");$q->execute([$rowId]);$receipt=$q->fetch();
        return ['statement'=>$row]+($receipt?bank_payment_result($db,$receipt):['receipt'=>null]);
    });
}

function bank_payment_draft(PDO $db,array $user,array $in):array {
    if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);
    $rowId=(int)($in['statement_row_id']??0);$request=(string)($in['request_key']??'');
    if(!preg_match('/^[a-f0-9]{64}$/D',$request))accounts_fail('PAYMENT_REQUEST_KEY_REQUIRED');
    return bank_ownership_transaction($db,function()use($db,$user,$in,$rowId,$request):array {
        $q=$db->prepare('SELECT * FROM qbook_bank_statement_rows WHERE id=? FOR UPDATE');$q->execute([$rowId]);$row=$q->fetch();
        if(!$row||accounts_money_minor($row['amount'],false)<=0)accounts_fail('UNMATCHED_BANK_CREDIT_REQUIRED',409);
        foreach(['bank_account_id','cash_amount','receipt_date','bank_reference'] as $field)if(array_key_exists($field,$in)){
            $source=['bank_account_id'=>'bank_account_id','cash_amount'=>'amount','receipt_date'=>'transaction_date','bank_reference'=>'bank_reference'][$field];
            if((string)$in[$field]!==(string)$row[$source])accounts_fail('STATEMENT_FIELDS_LOCKED',409);
        }
        $q=$db->prepare('SELECT * FROM qbook_customer_receipts WHERE created_by=? AND creation_request_key=? FOR UPDATE');$q->execute([$user['id'],$request]);$prior=$q->fetch();
        if($prior){if((int)$prior['statement_row_id']!==$rowId||(int)$prior['client_id']!==(int)($in['client_id']??0))accounts_fail('PAYMENT_RETRY_PAYLOAD_MISMATCH',409);if($prior['status']==='CANCELLED')accounts_fail('PAYMENT_DRAFT_CANCELLED',409);return bank_payment_result($db,$prior,true);}
        bank_row_available($db,$rowId);
        $client=billing_client($db,$in['client_id']??0);
        $q=$db->prepare('SELECT id FROM qbook_bank_accounts WHERE id=? AND is_active=1');$q->execute([$row['bank_account_id']]);if(!$q->fetch())accounts_fail('ACTIVE_BANK_ACCOUNT_REQUIRED');
        $ref=billing_allocate_reference($db,'qbook_customer_receipt_references');
        $db->prepare("INSERT INTO qbook_customer_receipts(reference_no,client_id,client_name_snapshot,bank_account_id,receipt_date,cash_amount,bank_reference,narration,destination,statement_row_id,created_by,creation_request_key)VALUES(?,?,?,?,?,?,?,?,'CUSTOMER_ADVANCES',?,?,?)")
            ->execute([$ref,$client['id'],$client['name'],$row['bank_account_id'],$row['transaction_date'],$row['amount'],$row['bank_reference'],$row['narration'],$rowId,$user['id'],$request]);
        $id=(int)$db->lastInsertId();accounts_audit($db,$user,'CUSTOMER_RECEIPT_DRAFT_SAVED','CUSTOMER_RECEIPT',$id,['statement_row_id'=>$rowId,'reference_no'=>billing_ref('RECEIPT',$ref),'journal_posted'=>false]);
        $q=$db->prepare('SELECT * FROM qbook_customer_receipts WHERE id=?');$q->execute([$id]);return bank_payment_result($db,$q->fetch());
    });
}

function bank_payment_edit(PDO $db,array $user,array $in,bool $cancel=false):array {
    if(($user['role']??'')!=='ADMIN')accounts_fail('FORBIDDEN',403);
    $id=(int)($in['receipt_id']??0);
    return bank_payment_transaction($db,$id,function()use($db,$user,$in,$cancel,$id):array {
        $q=$db->prepare('SELECT * FROM qbook_customer_receipts WHERE id=? FOR UPDATE');$q->execute([$id]);$receipt=$q->fetch();
        if($receipt['statement_row_id']===null)accounts_fail('STATEMENT_PAYMENT_REQUIRED');
        if($cancel&&$receipt['status']==='CANCELLED')return bank_payment_result($db,$receipt,true);
        if($receipt['status']!=='DRAFT'||$receipt['journal_id']!==null)accounts_fail('PAYMENT_NOT_EDITABLE',409);
        bank_payment_statement($db,$receipt);
        if((int)($in['draft_revision']??-1)!==(int)$receipt['draft_revision'])accounts_fail('PAYMENT_DRAFT_CHANGED_REFRESH',409);
        if($cancel){
            $reason=production_clean_text($in['reason']??'',500,'CANCELLATION_REASON_REQUIRED');
            $db->prepare("UPDATE qbook_customer_receipts SET status='CANCELLED',cancelled_by=?,cancelled_at=UTC_TIMESTAMP(),cancellation_reason=?,draft_revision=draft_revision+1 WHERE id=?")->execute([$user['id'],$reason,$id]);
            accounts_audit($db,$user,'CUSTOMER_RECEIPT_DRAFT_CANCELLED','CUSTOMER_RECEIPT',$id,['statement_row_id'=>(int)$receipt['statement_row_id'],'reason'=>$reason,'journal_posted'=>false]);
        }else{
            $payload=$in['allocations']??[];if(!is_array($payload)||count($payload)>100)accounts_fail('INVALID_ALLOCATIONS');
            // Draft intent is not an accounting allocation; posting revalidates every value.
            $json=json_encode($payload,JSON_THROW_ON_ERROR);if(strlen($json)>100000)accounts_fail('INVALID_ALLOCATIONS');
            $db->prepare('UPDATE qbook_customer_receipts SET draft_payload=?,draft_revision=draft_revision+1 WHERE id=?')->execute([$json,$id]);
            accounts_audit($db,$user,'CUSTOMER_RECEIPT_DRAFT_UPDATED','CUSTOMER_RECEIPT',$id,['statement_row_id'=>(int)$receipt['statement_row_id'],'journal_posted'=>false]);
        }
        $q->execute([$id]);return bank_payment_result($db,$q->fetch());
    });
}
