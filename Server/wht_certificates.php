<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();
production_require_method('GET');
accounts_endpoint(function():array{
    $db=production_db();
    $status=strtoupper(trim((string)($_GET['status']??'PENDING')));
    if(!in_array($status,['PENDING','RECEIVED','ALL'],true))accounts_fail('INVALID_CERTIFICATE_STATUS');
    $clientId=(int)($_GET['client_id']??0);
    $from=trim((string)($_GET['date_from']??''));$to=trim((string)($_GET['date_to']??''));
    if($from!=='')$from=accounts_date($from);if($to!=='')$to=accounts_date($to);if($from!==''&&$to!==''&&$from>$to)accounts_fail('INVALID_DATE_RANGE');
    $search=trim((string)($_GET['search']??''));
    $rows=[];
    $sql="SELECT x.* FROM (
      SELECT 'RECEIPT' record_type,w.id record_id,w.receipt_id,NULL receipt_allocation_id,w.tax_code_id,w.rate_snapshot,w.calculation_base_snapshot,NULL calculation_base_amount,w.accepted_amount,w.certificate_status,
             (SELECT MIN(e.id) FROM qbook_financial_evidence e WHERE e.source_type='WHT_CERTIFICATE' AND e.source_record_id=w.receipt_id) certificate_evidence_id,
             w.certificate_received_at,w.created_at,r.reference_no,r.client_id,r.client_name_snapshot,r.receipt_date,NULL invoice_id,NULL invoice_reference
      FROM qbook_receipt_wht w JOIN qbook_customer_receipts r ON r.id=w.receipt_id
      UNION ALL
      SELECT 'ALLOCATION',aw.id,r.id,a.id,aw.tax_code_id,aw.rate_snapshot,aw.calculation_base_snapshot,aw.calculation_base_amount,aw.accepted_amount,aw.certificate_status,aw.certificate_evidence_id,aw.certificate_received_at,aw.created_at,r.reference_no,r.client_id,r.client_name_snapshot,r.receipt_date,a.invoice_id,i.reference_no
      FROM qbook_customer_receipt_allocation_wht aw JOIN qbook_customer_receipt_allocations a ON a.id=aw.receipt_allocation_id JOIN qbook_customer_receipts r ON r.id=a.receipt_id JOIN qbook_invoices i ON i.id=a.invoice_id
    ) x WHERE 1=1";
    $params=[];
    if($status!=='ALL'){$sql.=' AND x.certificate_status=?';$params[]=$status==='PENDING'?'CERTIFICATE_PENDING':'CERTIFICATE_RECEIVED';}
    if($clientId>0){$sql.=' AND x.client_id=?';$params[]=$clientId;}
    if($from!==''){$sql.=' AND x.receipt_date>=?';$params[]=$from;}if($to!==''){$sql.=' AND x.receipt_date<=?';$params[]=$to;}
    if($search!==''){$sql.=' AND (CONCAT(\'CEH-RCP-\',LPAD(x.reference_no,6,\'0\')) LIKE ? OR CONCAT(\'CEH-INV-\',LPAD(x.invoice_reference,6,\'0\')) LIKE ? OR x.client_name_snapshot LIKE ?)';$like='%'.$search.'%';array_push($params,$like,$like,$like);}
    $sql.=' ORDER BY x.receipt_date DESC,x.record_id DESC';
    $s=$db->prepare($sql);$s->execute($params);
    foreach($s->fetchAll()as$r){$r['receipt_reference']=billing_ref('RECEIPT',$r['reference_no']);$r['invoice_reference']=$r['invoice_reference']===null?null:billing_ref('INVOICE',$r['invoice_reference']);$rows[]=$r;}
    return['certificates'=>$rows];
});
