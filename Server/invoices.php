<?php
declare(strict_types=1);
require_once __DIR__.'/billing_common.php';
$user=billing_require_admin();
production_require_method('GET');

accounts_endpoint(function():array{
    $db=production_db();
    $id=(int)($_GET['id']??0);
    $settled="COALESCE((SELECT SUM(a.cash_amount+a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(a.amount) FROM qbook_advance_applications a WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(ca.amount) FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED' WHERE ca.invoice_id=i.id),0)";
    if($id>0){
        $s=$db->prepare("SELECT i.*,{$settled} settled,COALESCE((SELECT SUM(a.cash_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0) amount_paid,COALESCE((SELECT SUM(a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0) wht_allocated,j.status posting_status FROM qbook_invoices i LEFT JOIN qbook_financial_journals j ON j.id=i.journal_id WHERE i.id=?");
        $s->execute([$id]);$invoice=$s->fetch();if(!$invoice)accounts_fail('INVOICE_NOT_FOUND',404);
        $total=$invoice['total_amount']===null?0:accounts_money_minor($invoice['total_amount'],false);$settledMinor=accounts_money_minor((string)$invoice['settled'],false);
        $invoice['reference']=billing_ref('INVOICE',$invoice['reference_no']);$invoice['outstanding']=accounts_minor_decimal($total-$settledMinor);$invoice['display_status']=billing_display_status($invoice+['outstanding_minor'=>$total-$settledMinor]);
        $ls=$db->prepare("SELECT l.*,a.name revenue_account FROM qbook_invoice_lines l JOIN qbook_accounts_chart a ON a.id=l.revenue_account_id WHERE l.invoice_id=? ORDER BY l.line_no");$ls->execute([$id]);$lines=$ls->fetchAll();
        $ps=$db->prepare("SELECT pa.* FROM qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id WHERE l.invoice_id=? ORDER BY pa.id");$ps->execute([$id]);$byLine=[];foreach($ps->fetchAll()as$p)$byLine[(int)$p['invoice_line_id']][]=$p;foreach($lines as&$line)$line['production_allocations']=$byLine[(int)$line['id']]??[];unset($line);
        $cs=$db->prepare("SELECT c.id,c.reference_no,c.credit_date,c.reason,c.status,c.total_amount,c.issued_at FROM qbook_credit_notes c WHERE c.invoice_id=? ORDER BY c.id");$cs->execute([$id]);$credits=$cs->fetchAll();foreach($credits as&$credit)$credit['reference']=billing_ref('CREDIT_NOTE',$credit['reference_no']);unset($credit);
        return['invoice'=>$invoice,'lines'=>$lines,'credit_notes'=>$credits];
    }
    $where=[];$args=[];if(($client=(int)($_GET['client_id']??0))>0){$where[]='i.client_id=?';$args[]=$client;}
    $sql="SELECT i.*,{$settled} settled FROM qbook_invoices i".($where?' WHERE '.implode(' AND ',$where):'')." ORDER BY COALESCE(i.invoice_date,DATE(i.created_at)) DESC,i.id DESC";
    $s=$db->prepare($sql);$s->execute($args);$out=[];foreach($s->fetchAll()as$row){$total=$row['total_amount']===null?0:accounts_money_minor($row['total_amount'],false);$settledMinor=accounts_money_minor((string)$row['settled'],false);$row['reference']=billing_ref('INVOICE',$row['reference_no']);$row['outstanding']=accounts_minor_decimal($total-$settledMinor);$row['display_status']=billing_display_status($row+['outstanding_minor'=>$total-$settledMinor]);$out[]=$row;}
    return['invoices'=>$out];
});
