<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();
production_require_method('GET');
accounts_endpoint(function():array{
    $db=production_db();
    $asOf=accounts_date($_GET['as_of']??gmdate('Y-m-d'));
    $asOfDate=new DateTimeImmutable($asOf);
    $stmt=$db->prepare("SELECT i.id,i.reference_no,i.client_id,i.client_name_snapshot,i.invoice_date,i.due_date,i.total_amount,
        COALESCE((SELECT SUM(a.cash_amount+a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0)
        +COALESCE((SELECT SUM(a.amount) FROM qbook_advance_applications a WHERE a.invoice_id=i.id),0)
        +COALESCE((SELECT SUM(ca.amount) FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED' WHERE ca.invoice_id=i.id),0) settled
        FROM qbook_invoices i WHERE i.status='ISSUED' AND i.invoice_date<=? ORDER BY i.client_name_snapshot,i.invoice_date,i.id");
    $stmt->execute([$asOf]);
    $buckets=['CURRENT'=>0,'1_30'=>0,'31_60'=>0,'61_90'=>0,'OVER_90'=>0];
    $rows=[];
    foreach($stmt->fetchAll() as $row){
        $original=accounts_money_minor($row['total_amount'],false);
        $settled=accounts_money_minor((string)$row['settled'],false);
        $outstanding=$original-$settled;
        if($outstanding<=0)continue;
        $invoiceDate=new DateTimeImmutable($row['invoice_date']);
        $daysOutstanding=max(0,(int)$invoiceDate->diff($asOfDate)->format('%r%a'));
        $daysOverdue=0;
        if($row['due_date']!==null){
            $dueDate=new DateTimeImmutable($row['due_date']);
            $daysOverdue=max(0,(int)$dueDate->diff($asOfDate)->format('%r%a'));
        }
        $bucket=$row['due_date']===null||$daysOverdue===0?'CURRENT':($daysOverdue<=30?'1_30':($daysOverdue<=60?'31_60':($daysOverdue<=90?'61_90':'OVER_90')));
        $buckets[$bucket]+=$outstanding;
        $row['reference']=billing_ref('INVOICE',$row['reference_no']);
        $row['original_amount']=accounts_minor_decimal($original);
        $row['payments_credits_applied']=accounts_minor_decimal($settled);
        $row['outstanding']=accounts_minor_decimal($outstanding);
        $row['days_outstanding']=$daysOutstanding;
        $row['days_overdue']=$daysOverdue;
        $row['bucket']=$bucket;
        $rows[]=$row;
    }
    return['as_of'=>$asOf,'buckets'=>array_map('accounts_minor_decimal',$buckets),'invoices'=>$rows];
});
