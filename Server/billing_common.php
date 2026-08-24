<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';

function billing_require_admin(): array { $u=qbook_require_user(); qbook_require_role($u,['ADMIN']); return $u; }
function billing_ref(string $type, mixed $number): string {
    $prefix=['INVOICE'=>'CEH-INV','RECEIPT'=>'CEH-RCP','CREDIT_NOTE'=>'CEH-CN'][$type]??null;
    $n=(int)$number; if($prefix===null||$n<=0) accounts_fail('INVALID_BILLING_REFERENCE',500);
    return $prefix.'-'.str_pad((string)$n,6,'0',STR_PAD_LEFT);
}
function billing_allocate_reference(PDO $db,string $table): int {
    if(!in_array($table,['qbook_invoice_references','qbook_customer_receipt_references','qbook_credit_note_references'],true)) accounts_fail('INVALID_REFERENCE_TABLE',500);
    $db->exec("INSERT INTO {$table}() VALUES()"); return (int)$db->lastInsertId();
}
function billing_account_role(PDO $db,string $role): int {
    $s=$db->prepare("SELECT r.account_id FROM qbook_financial_account_roles r JOIN qbook_accounts_chart a ON a.id=r.account_id AND a.is_active=1 AND a.is_postable=1 WHERE r.role_code=? AND r.is_active=1");
    $s->execute([$role]); $id=$s->fetchColumn(); if(!$id) accounts_fail('ACCOUNT_ROLE_NOT_CONFIGURED',409); return (int)$id;
}
function billing_client(PDO $db,mixed $id): array {
    $s=$db->prepare("SELECT id,name FROM qbook_clients WHERE id=? AND is_active=1"); $s->execute([(int)$id]); $r=$s->fetch(); if(!$r) accounts_fail('ACTIVE_CLIENT_REQUIRED',409); return $r;
}
function billing_tax_code(PDO $db,mixed $id,string $type,string $date): array {
    $s=$db->prepare("SELECT * FROM qbook_tax_codes WHERE id=? AND tax_type=? AND is_active=1 AND effective_from<=? AND (effective_to IS NULL OR effective_to>=?)");
    $s->execute([(int)$id,$type,$date,$date]); $r=$s->fetch(); if(!$r) accounts_fail('EFFECTIVE_TAX_CODE_REQUIRED',409); return $r;
}
function billing_multiply_divide_round_half_up(int $multiplicand,int $multiplier,int $divisor): int {
    if($multiplicand<0||$multiplier<0||$divisor<=0)accounts_fail('INVALID_TAX_RATE',500);
    $quotient=0;$remainder=0;$partQuotient=intdiv($multiplicand,$divisor);$partRemainder=$multiplicand%$divisor;
    while($multiplier>0){
        if(($multiplier%2)===1){
            if($partQuotient>PHP_INT_MAX-$quotient)accounts_fail('TAX_AMOUNT_OVERFLOW',500);
            $quotient+=$partQuotient;
            if($remainder>=$divisor-$partRemainder){
                $remainder-=($divisor-$partRemainder);
                if($quotient===PHP_INT_MAX)accounts_fail('TAX_AMOUNT_OVERFLOW',500);
                $quotient++;
            }else{$remainder+=$partRemainder;}
        }
        $multiplier=intdiv($multiplier,2);if($multiplier===0)break;
        $carry=$partRemainder>=$divisor-$partRemainder?1:0;
        $partRemainder=$carry===1?$partRemainder-($divisor-$partRemainder):$partRemainder+$partRemainder;
        if($partQuotient>intdiv(PHP_INT_MAX-$carry,2))accounts_fail('TAX_AMOUNT_OVERFLOW',500);
        $partQuotient=$partQuotient*2+$carry;
    }
    if($remainder>=$divisor-$remainder){
        if($quotient===PHP_INT_MAX)accounts_fail('TAX_AMOUNT_OVERFLOW',500);
        $quotient++;
    }
    return $quotient;
}
function billing_rate_millionths(string $rate): int {
    if(!preg_match('/\A(\d{1,3})(?:\.(\d{1,6}))?\z/',$rate,$parts))accounts_fail('INVALID_TAX_RATE',500);
    return (int)$parts[1]*1000000+(int)str_pad($parts[2]??'',6,'0');
}
function billing_percent_amount(int $baseMinor,string $rate): int {
    return billing_multiply_divide_round_half_up($baseMinor,billing_rate_millionths($rate),100000000);
}
function billing_inclusive_net(int $grossMinor,string $rate): int {
    $millionths=billing_rate_millionths($rate); return billing_multiply_divide_round_half_up($grossMinor,100000000,100000000+$millionths);
}
function billing_format_percent(mixed $rate): string {
    if (!is_numeric($rate)) return '0.00%';
    return number_format((float)$rate, 2, '.', '').'%';
}
function billing_invoice_lines(PDO $db,array $input,int $clientId,string $vatMode,?array $tax): array {
    $raw=$input['lines']??null; if(!is_array($raw)||$raw===[]||count($raw)>100) accounts_fail('INVOICE_LINES_REQUIRED'); $out=[];
    foreach(array_values($raw) as $i=>$line){ if(!is_array($line)) accounts_fail('INVALID_INVOICE_LINE');
        $account=(int)($line['revenue_account_id']??0); $s=$db->prepare("SELECT id FROM qbook_accounts_chart WHERE id=? AND account_type='INCOME' AND is_active=1 AND is_postable=1");$s->execute([$account]);if(!$s->fetch())accounts_fail('REVENUE_ACCOUNT_REQUIRED');
        $project=accounts_nullable_id($line['project_id']??null);$mixer=accounts_nullable_id($line['mixer_id']??null);accounts_validate_dimensions($db,$clientId,$project,$mixer);$projectSnapshot=null;$mixerSnapshot=null;if($project!==null){$d=$db->prepare("SELECT name FROM qbook_projects WHERE id=?");$d->execute([$project]);$x=$d->fetch();$projectSnapshot=$x?(string)$x['name']:null;}if($mixer!==null){$d=$db->prepare("SELECT code,name FROM qbook_mixers WHERE id=?");$d->execute([$mixer]);$x=$d->fetch();$mixerSnapshot=$x?trim((string)$x['code'].' - '.(string)$x['name']):null;}
        $entered=accounts_money_minor($line['amount']??'');$qty=trim((string)($line['quantity']??''));$price=trim((string)($line['unit_price']??''));if(($qty==='')!==($price===''))accounts_fail('QUANTITY_UNIT_PRICE_PAIR_REQUIRED');
        if($qty!==''){if(!preg_match('/\A\d{1,10}(?:\.\d{1,4})?\z/',$qty)||(float)$qty<=0)accounts_fail('INVALID_QUANTITY');$pm=accounts_money_minor($price);if((int)round((float)$qty*$pm)!==$entered)accounts_fail('LINE_QUANTITY_TOTAL_MISMATCH');}
        $taxable=($line['taxable']??true)!==false && (string)($line['taxable']??'1')!=='0'; $net=$entered;$vat=0;$gross=$entered;
        if($taxable&&$vatMode!=='NONE'){if(!$tax)accounts_fail('VAT_CODE_REQUIRED');if($vatMode==='VAT_EXCLUSIVE'){$vat=billing_percent_amount($entered,(string)$tax['rate_percent']);$gross=$entered+$vat;}else{$net=billing_inclusive_net($entered,(string)$tax['rate_percent']);$vat=$entered-$net;}}
        $source=strtoupper((string)($line['source_type']??'MANUAL'));if(!in_array($source,['PRODUCTION_REPORT','SERVICE','EQUIPMENT_HIRE','MANUAL'],true))accounts_fail('INVALID_INVOICE_SOURCE');
        $out[]=['line_no'=>$i+1,'source_type'=>$source,'description'=>production_clean_text($line['description']??'',500,'LINE_DESCRIPTION_REQUIRED'),'quantity'=>$qty===''?null:number_format((float)$qty,4,'.',''),'unit_name'=>production_clean_text($line['unit_name']??'',30,'INVALID_UNIT',false)?:null,'unit_price_minor'=>$price===''?null:accounts_money_minor($price),'entered_minor'=>$entered,'taxable'=>$taxable?1:0,'net_minor'=>$net,'vat_minor'=>$vat,'gross_minor'=>$gross,'revenue_account_id'=>$account,'project_id'=>$project,'project_snapshot'=>$projectSnapshot,'mixer_id'=>$mixer,'mixer_snapshot'=>$mixerSnapshot,'production'=>$line['production']??null];
    } return $out;
}
function billing_totals(array $lines): array { $n=$v=$g=0;foreach($lines as$l){$n+=$l['net_minor'];$v+=$l['vat_minor'];$g+=$l['gross_minor'];}return['net'=>$n,'vat'=>$v,'gross'=>$g]; }
function billing_invoice_outstanding(PDO $db,int $invoiceId,bool $lock=false): array {
    $s=$db->prepare("SELECT i.*, COALESCE((SELECT SUM(a.cash_amount+a.wht_amount) FROM qbook_customer_receipt_allocations a JOIN qbook_customer_receipts r ON r.id=a.receipt_id AND r.status='POSTED' WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(a.amount) FROM qbook_advance_applications a WHERE a.invoice_id=i.id),0)+COALESCE((SELECT SUM(ca.amount) FROM qbook_credit_note_allocations ca JOIN qbook_credit_notes c ON c.id=ca.credit_note_id AND c.status='ISSUED' WHERE ca.invoice_id=i.id),0) AS settled FROM qbook_invoices i WHERE i.id=?".($lock?' FOR UPDATE':''));
    $s->execute([$invoiceId]);$r=$s->fetch();if(!$r)accounts_fail('INVOICE_NOT_FOUND',404);$total=$r['total_amount']===null?0:accounts_money_minor($r['total_amount'],false);$settled=accounts_money_minor((string)$r['settled'],false);$r['outstanding_minor']=$total-$settled;return$r;
}
function billing_display_status(array $invoice): string {
    if($invoice['status']==='VOID')return'VOID';if($invoice['status']==='DRAFT')return'DRAFT';$out=(int)$invoice['outstanding_minor'];$total=accounts_money_minor($invoice['total_amount'],false);if($out<=0)return'PAID';if($out<$total)return'PART_PAID';if($invoice['due_date']&&$invoice['due_date']<gmdate('Y-m-d'))return'OVERDUE';return'ISSUED';
}
