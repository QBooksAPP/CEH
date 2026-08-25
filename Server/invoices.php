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
        $s=$db->prepare("SELECT i.*,{$settled} settled,
            COALESCE((SELECT SUM(a.cash_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0) amount_paid,
            COALESCE((SELECT SUM(a.amount) FROM qbook_advance_applications a WHERE a.invoice_id=i.id),0) customer_credit_applied,
            COALESCE((SELECT SUM(a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0) wht_allocated,
            COALESCE((SELECT SUM(ca.amount) FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED' WHERE ca.invoice_id=i.id),0) credit_notes_total,
            j.status posting_status
            FROM qbook_invoices i LEFT JOIN qbook_financial_journals j ON j.id=i.journal_id WHERE i.id=?");
        $s->execute([$id]);$invoice=$s->fetch();if(!$invoice)accounts_fail('INVOICE_NOT_FOUND',404);
        $total=$invoice['total_amount']===null?0:accounts_money_minor($invoice['total_amount'],false);$settledMinor=accounts_money_minor((string)$invoice['settled'],false);
        $invoice['reference']=billing_ref('INVOICE',$invoice['reference_no']);$invoice['outstanding']=accounts_minor_decimal($total-$settledMinor);$invoice['display_status']=billing_display_status($invoice+['outstanding_minor'=>$total-$settledMinor]);
        $ls=$db->prepare("SELECT l.*,a.name revenue_account FROM qbook_invoice_lines l JOIN qbook_accounts_chart a ON a.id=l.revenue_account_id WHERE l.invoice_id=? ORDER BY l.line_no");$ls->execute([$id]);$lines=$ls->fetchAll();
        $ps=$db->prepare("SELECT pa.* FROM qbook_invoice_production_allocations pa JOIN qbook_invoice_lines l ON l.id=pa.invoice_line_id WHERE l.invoice_id=? ORDER BY pa.id");$ps->execute([$id]);$byLine=[];foreach($ps->fetchAll()as$p)$byLine[(int)$p['invoice_line_id']][]=$p;foreach($lines as&$line)$line['production_allocations']=$byLine[(int)$line['id']]??[];unset($line);
        $cs=$db->prepare("SELECT c.id,c.reference_no,c.credit_date,c.reason,c.status,c.total_amount,c.issued_at FROM qbook_credit_notes c WHERE c.invoice_id=? ORDER BY c.id");$cs->execute([$id]);$credits=$cs->fetchAll();foreach($credits as&$credit)$credit['reference']=billing_ref('CREDIT_NOTE',$credit['reference_no']);unset($credit);
        $events=[];
        $cash=$db->prepare("SELECT r.receipt_date event_date,'CUSTOMER_PAYMENT' event_type,a.cash_amount amount,r.reference_no,
            b.name bank_destination,r.bank_reference,NULL tax_code,NULL tax_rate,NULL certificate_status,a.allocated_at event_timestamp
            FROM qbook_customer_receipt_allocations a
            JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED'
            JOIN qbook_bank_accounts b ON b.id=r.bank_account_id
            WHERE a.invoice_id=? AND a.cash_amount>0");
        $cash->execute([$id]);
        foreach($cash->fetchAll() as $event){$event['reference']=billing_ref('RECEIPT',$event['reference_no']);$events[]=$event;}
        $advance=$db->prepare("SELECT DATE(a.applied_at) event_date,'CUSTOMER_CREDIT' event_type,a.amount,r.reference_no,
            NULL bank_destination,NULL bank_reference,NULL tax_code,NULL tax_rate,NULL certificate_status,a.applied_at event_timestamp
            FROM qbook_advance_applications a
            JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED'
            WHERE a.invoice_id=?");
        $advance->execute([$id]);
        foreach($advance->fetchAll() as $event){$event['reference']=billing_ref('RECEIPT',$event['reference_no']);$events[]=$event;}
        $wht=$db->prepare("SELECT r.receipt_date event_date,'WHT' event_type,a.wht_amount amount,r.reference_no,
            NULL bank_destination,NULL bank_reference,t.code tax_code,COALESCE(aw.rate_snapshot,w.rate_snapshot) tax_rate,
            COALESCE(aw.calculation_base_snapshot,w.calculation_base_snapshot) calculation_base,
            aw.calculation_base_amount,
            COALESCE(aw.certificate_status,w.certificate_status) certificate_status,a.allocated_at event_timestamp
            FROM qbook_customer_receipt_allocations a
            JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED'
            LEFT JOIN qbook_customer_receipt_allocation_wht aw ON aw.receipt_allocation_id=a.id
            LEFT JOIN qbook_receipt_wht w ON w.receipt_id=r.id
            JOIN qbook_tax_codes t ON t.id=COALESCE(aw.tax_code_id,w.tax_code_id)
            WHERE a.invoice_id=? AND a.wht_amount>0");
        $wht->execute([$id]);
        foreach($wht->fetchAll() as $event){$event['reference']=billing_ref('RECEIPT',$event['reference_no']);$events[]=$event;}
        $creditEvents=$db->prepare("SELECT c.credit_date event_date,'CREDIT_NOTE' event_type,ca.amount,c.reference_no,
            NULL bank_destination,NULL bank_reference,NULL tax_code,NULL tax_rate,NULL certificate_status,ca.allocated_at event_timestamp
            FROM qbook_credit_note_allocations ca
            JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED'
            WHERE ca.invoice_id=?");
        $creditEvents->execute([$id]);
        foreach($creditEvents->fetchAll() as $event){$event['reference']=billing_ref('CREDIT_NOTE',$event['reference_no']);$events[]=$event;}
        usort($events,static function(array $a,array $b):int{
            $date=strcmp((string)$a['event_date'],(string)$b['event_date']);
            return $date!==0?$date:strcmp((string)$a['event_timestamp'],(string)$b['event_timestamp']);
        });
        return['invoice'=>$invoice,'lines'=>$lines,'credit_notes'=>$credits,'settlement_history'=>$events];
    }
    $where=[];$args=[];if(($client=(int)($_GET['client_id']??0))>0){$where[]='i.client_id=?';$args[]=$client;}
    $outstandingOnly=filter_var($_GET['outstanding_only']??false,FILTER_VALIDATE_BOOL);
    if($outstandingOnly)$where[]="i.status='ISSUED'";
    $projects="COALESCE((SELECT GROUP_CONCAT(DISTINCT p.name ORDER BY p.name SEPARATOR ' • ') FROM qbook_invoice_lines il LEFT JOIN qbook_projects p ON p.id=il.project_id WHERE il.invoice_id=i.id AND p.id IS NOT NULL),'')";
    $sql="SELECT i.*,{$settled} settled,{$projects} project_names FROM qbook_invoices i".($where?' WHERE '.implode(' AND ',$where):'')." ORDER BY COALESCE(i.invoice_date,DATE(i.created_at)) DESC,i.id DESC";
    $s=$db->prepare($sql);$s->execute($args);$out=[];foreach($s->fetchAll()as$row){$total=$row['total_amount']===null?0:accounts_money_minor($row['total_amount'],false);$settledMinor=accounts_money_minor((string)$row['settled'],false);$outstanding=$total-$settledMinor;if($outstandingOnly&&$outstanding<=0)continue;$row['reference']=billing_ref('INVOICE',$row['reference_no']);$row['outstanding']=accounts_minor_decimal($outstanding);$row['display_status']=billing_display_status($row+['outstanding_minor'=>$outstanding]);$out[]=$row;}
    return['invoices'=>$out];
});
