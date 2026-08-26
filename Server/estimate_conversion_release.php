<?php
declare(strict_types=1);
require_once __DIR__.'/estimate_common.php';

$user=billing_require_admin();
production_require_method('POST');
accounts_endpoint(function()use($user):array{
    $input=production_json_input();
    $invoiceId=(int)($input['invoice_id']??0);
    $reason=trim((string)($input['reason']??''));
    if($invoiceId<=0)accounts_fail('INVOICE_REQUIRED');
    if($reason==='')accounts_fail('RELEASE_REASON_REQUIRED');
    if(strlen($reason)>500)accounts_fail('RELEASE_REASON_TOO_LONG');
    $db=production_db();
    return accounts_transaction($db,function()use($db,$user,$invoiceId,$reason):array{
        $invoiceStmt=$db->prepare('SELECT id,reference_no,status,origin_estimate_id,journal_id FROM qbook_invoices WHERE id=? FOR UPDATE');
        $invoiceStmt->execute([$invoiceId]);
        $invoice=$invoiceStmt->fetch();
        if(!$invoice)accounts_fail('INVOICE_NOT_FOUND',404);
        if($invoice['status']!=='DRAFT'||$invoice['journal_id']!==null)accounts_fail('ONLY_UNPOSTED_DRAFT_CONVERSION_CAN_BE_RELEASED',409);
        if($invoice['origin_estimate_id']===null)accounts_fail('INVOICE_NOT_FROM_ESTIMATE',409);
        $estimateStmt=$db->prepare('SELECT id FROM qbook_estimates WHERE id=? FOR UPDATE');
        $estimateStmt->execute([(int)$invoice['origin_estimate_id']]);
        if(!$estimateStmt->fetch())accounts_fail('ESTIMATE_NOT_FOUND',404);
        $conversionStmt=$db->prepare("SELECT c.id FROM qbook_estimate_invoice_conversions c JOIN qbook_invoice_lines l ON l.id=c.invoice_line_id WHERE l.invoice_id=? AND c.status='DRAFT' ORDER BY c.id FOR UPDATE");
        $conversionStmt->execute([$invoiceId]);
        $conversionIds=array_column($conversionStmt->fetchAll(),'id');
        if(!$conversionIds)accounts_fail('NO_DRAFT_CONVERSION_TO_RELEASE',409);
        $update=$db->prepare("UPDATE qbook_estimate_invoice_conversions c JOIN qbook_invoice_lines l ON l.id=c.invoice_line_id SET c.status='RELEASED' WHERE l.invoice_id=? AND c.status='DRAFT'");
        $update->execute([$invoiceId]);
        $db->prepare("UPDATE qbook_invoices SET status='VOID' WHERE id=? AND status='DRAFT' AND journal_id IS NULL")->execute([$invoiceId]);
        accounts_audit($db,$user,'ESTIMATE_INVOICE_DRAFT_CONVERSION_RELEASED','INVOICE',$invoiceId,[
            'estimate_id'=>(int)$invoice['origin_estimate_id'],
            'invoice_reference'=>billing_ref('INVOICE',$invoice['reference_no']),
            'conversion_ids'=>array_map('intval',$conversionIds),
            'reason'=>$reason,
        ]);
        return['released'=>true,'invoice_id'=>$invoiceId];
    });
});
