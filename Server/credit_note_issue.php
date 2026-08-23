<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin(); production_require_method('POST'); $in=production_input();
accounts_endpoint(function()use($user,$in):array{
    $db=production_db();
    return accounts_transaction($db,function()use($db,$user,$in):array{
        $invoice=billing_invoice_outstanding($db,(int)($in['invoice_id']??0),true);
        if($invoice['status']!=='ISSUED') accounts_fail('ISSUED_INVOICE_REQUIRED',409);
        $raw=$in['lines']??null; if(!is_array($raw)||$raw===[]) accounts_fail('CREDIT_LINES_REQUIRED');
        $ref=billing_allocate_reference($db,'qbook_credit_note_references');
        $reason=production_clean_text($in['reason']??'',500,'REASON_REQUIRED');
        $net=$vat=$gross=0; $lines=[];
        foreach(array_values($raw) as $idx=>$x){
            if(!is_array($x)) accounts_fail('INVALID_CREDIT_LINE');
            $lid=(int)($x['invoice_line_id']??0);
            $s=$db->prepare("SELECT * FROM qbook_invoice_lines WHERE id=? AND invoice_id=? FOR UPDATE");
            $s->execute([$lid,$invoice['id']]); $ol=$s->fetch(); if(!$ol) accounts_fail('INVOICE_LINE_NOT_FOUND',404);
            $g=accounts_money_minor($x['gross_amount']??''); $originalGross=accounts_money_minor($ol['gross_amount'],false);
            $already=$db->prepare("SELECT COALESCE(SUM(cl.gross_amount),0) FROM qbook_credit_note_lines cl JOIN qbook_credit_notes c ON c.id=cl.credit_note_id AND c.status='ISSUED' WHERE cl.invoice_line_id=?");
            $already->execute([$lid]); $am=accounts_money_minor((string)$already->fetchColumn(),false);
            if($am+$g>$originalGross) accounts_fail('CREDIT_EXCEEDS_INVOICE_LINE',409);
            $treatment=strtoupper((string)($x['quantity_treatment']??'NO_QUANTITY_RELEASE'));
            if(!in_array($treatment,['NO_QUANTITY_RELEASE','RELEASE_QUANTITY'],true)) accounts_fail('INVALID_QUANTITY_TREATMENT');
            $released=null;
            $pa=$db->prepare("SELECT billed_m3 FROM qbook_invoice_production_allocations WHERE invoice_line_id=? AND status='COMMITTED' FOR UPDATE");
            $pa->execute([$lid]); $allocation=$pa->fetch();
            if($treatment==='RELEASE_QUANTITY'){
                if(!$allocation) accounts_fail('PRODUCTION_QUANTITY_RELEASE_NOT_AVAILABLE',409);
                $releasedRaw=trim((string)($x['released_m3']??''));
                if(!preg_match('/\A\d{1,8}(?:\.\d{1,2})?\z/',$releasedRaw)||(float)$releasedRaw<=0) accounts_fail('INVALID_RELEASED_M3');
                $released=number_format((float)$releasedRaw,2,'.','');
                $used=$db->prepare("SELECT COALESCE(SUM(cl.released_m3),0) FROM qbook_credit_note_lines cl JOIN qbook_credit_notes cn ON cn.id=cl.credit_note_id AND cn.status='ISSUED' WHERE cl.invoice_line_id=? AND cl.quantity_treatment='RELEASE_QUANTITY'");
                $used->execute([$lid]);
                if((float)$used->fetchColumn()+(float)$released>(float)$allocation['billed_m3']) accounts_fail('QUANTITY_RELEASE_EXCEEDS_BILLED_M3',409);
            } elseif(array_key_exists('released_m3',$x)&&trim((string)$x['released_m3'])!=='') accounts_fail('RELEASED_M3_NOT_ALLOWED');
            $v=0; $n=$g;
            if($originalGross>0&&accounts_money_minor($ol['vat_amount'],false)>0){
                $v=(int)round($g*accounts_money_minor($ol['vat_amount'],false)/$originalGross); $n=$g-$v;
            }
            $net+=$n; $vat+=$v; $gross+=$g; $lines[]=[$idx+1,$ol,$n,$v,$g,$treatment,$released];
        }
        if($gross>$invoice['outstanding_minor']) accounts_fail('CREDIT_EXCEEDS_OUTSTANDING',409);
        $date=accounts_date($in['credit_date']??gmdate('Y-m-d'));
        $db->prepare("INSERT INTO qbook_credit_notes(reference_no,invoice_id,credit_date,reason,net_amount,vat_amount,total_amount,created_by)VALUES(?,?,?,?,?,?,?,?)")
            ->execute([$ref,$invoice['id'],$date,$reason,accounts_minor_decimal($net),accounts_minor_decimal($vat),accounts_minor_decimal($gross),$user['id']]);
        $cid=(int)$db->lastInsertId();
        $il=$db->prepare("INSERT INTO qbook_credit_note_lines(credit_note_id,invoice_line_id,line_no,description,revenue_account_id,net_amount,vat_amount,gross_amount,project_id,mixer_id,quantity_treatment,released_m3)VALUES(?,?,?,?,?,?,?,?,?,?,?,?)");
        $jl=[]; $quantityAudit=[];
        foreach($lines as[$no,$ol,$n,$v,$g,$treatment,$released]){
            $il->execute([$cid,$ol['id'],$no,$reason,$ol['revenue_account_id'],accounts_minor_decimal($n),accounts_minor_decimal($v),accounts_minor_decimal($g),$ol['project_id'],$ol['mixer_id'],$treatment,$released]);
            $jl[]=['account_id'=>(int)$ol['revenue_account_id'],'debit_minor'=>$n,'credit_minor'=>0,'description'=>$reason,'client_id'=>(int)$invoice['client_id'],'project_id'=>$ol['project_id'],'mixer_id'=>$ol['mixer_id']];
            $quantityAudit[]=['invoice_line_id'=>(int)$ol['id'],'quantity_treatment'=>$treatment,'released_m3'=>$released];
        }
        if($vat>0) $jl[]=['account_id'=>billing_account_role($db,'OUTPUT_VAT_PAYABLE'),'debit_minor'=>$vat,'credit_minor'=>0,'description'=>'VAT credit '.billing_ref('CREDIT_NOTE',$ref),'client_id'=>(int)$invoice['client_id']];
        $jl[]=['account_id'=>billing_account_role($db,'TRADE_RECEIVABLES'),'debit_minor'=>0,'credit_minor'=>$gross,'description'=>billing_ref('CREDIT_NOTE',$ref),'client_id'=>(int)$invoice['client_id']];
        $j=accounts_post_journal($db,$user,['transaction_date'=>$date,'description'=>'Credit note '.billing_ref('CREDIT_NOTE',$ref),'source_module'=>'CREDIT_NOTE','source_record_id'=>$cid,'approved_by'=>$user['id']],$jl);
        $db->prepare("UPDATE qbook_credit_notes SET status='ISSUED',journal_id=?,issued_by=?,issued_at=UTC_TIMESTAMP() WHERE id=?")->execute([$j['id'],$user['id'],$cid]);
        $db->prepare("INSERT INTO qbook_credit_note_allocations(credit_note_id,invoice_id,amount)VALUES(?,?,?)")->execute([$cid,$invoice['id'],accounts_minor_decimal($gross)]);
        accounts_audit($db,$user,'CREDIT_NOTE_ISSUED','CREDIT_NOTE',$cid,['invoice_id'=>$invoice['id'],'journal_id'=>$j['id'],'production_quantity'=>$quantityAudit]);
        return ['credit_note'=>['id'=>$cid,'reference'=>billing_ref('CREDIT_NOTE',$ref),'status'=>'ISSUED'],'journal'=>$j];
    });
});
