<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('GET');
accounts_endpoint(function() use($user): array {
    $db=production_db(); $admin=strtoupper((string)$user['role'])==='ADMIN';
    $requested=(int)($_GET['custodian_user_id']??0);
    if(!$admin && $requested>0 && $requested!==(int)$user['id']) accounts_fail('FORBIDDEN',403);
    $params=[];$where="c.is_active=1 AND u.is_active=1";
    if(!$admin||$requested>0){$where.=" AND c.user_id=?";$params[]=!$admin?(int)$user['id']:$requested;}
    $s=$db->prepare("SELECT c.id,c.user_id,u.full_name,u.role FROM qbook_petty_cash_custodians c JOIN qbook_users u ON u.id=c.user_id WHERE $where ORDER BY u.full_name");$s->execute($params);
    $month=new DateTimeImmutable('now',new DateTimeZone('UTC'));
    $periodStart=$month->format('Y-m-01');$periodEnd=$month->modify('first day of next month')->format('Y-m-d');
    $received=$db->prepare("SELECT COALESCE(SUM(f.amount),0) FROM qbook_petty_cash_fundings f JOIN qbook_financial_journals j ON j.id=f.journal_id AND j.status='POSTED' WHERE f.custodian_user_id=? AND f.funding_date>=? AND f.funding_date<?");
    $accounted=$db->prepare("SELECT COALESCE(SUM(e.amount),0) FROM qbook_petty_cash_expenses e JOIN qbook_financial_journals j ON j.id=e.journal_id AND j.status='POSTED' WHERE e.custodian_user_id=? AND e.status IN ('APPROVED','VOIDED') AND e.expense_date>=? AND e.expense_date<?");
    $custodians=[];$total=0;
    foreach($s->fetchAll() as $row){
        $userId=(int)$row['user_id'];$balance=accounts_custodian_balance($db,$userId);$total+=accounts_money_minor($balance['balance'],false);
        $received->execute([$userId,$periodStart,$periodEnd]);$receivedRaw=(string)$received->fetchColumn();
        $accounted->execute([$userId,$periodStart,$periodEnd]);$accountedRaw=(string)$accounted->fetchColumn();
        $custodians[]=['id'=>(int)$row['id'],'user_id'=>$userId,'name'=>$row['full_name'],'role'=>$row['role'],'balance'=>accounts_public_balance($balance),'this_month'=>[
          'period_start'=>$periodStart,'period_end_exclusive'=>$periodEnd,
          'funds_received'=>$receivedRaw==='0'?'0.00':accounts_minor_decimal(accounts_money_minor($receivedRaw,false)),
          'accounted'=>$accountedRaw==='0'?'0.00':accounts_minor_decimal(accounts_money_minor($accountedRaw,false)),
        ]];
    }
    return ['total_petty_cash_outstanding'=>accounts_minor_decimal($total),'total_petty_cash'=>accounts_minor_decimal($total),'reporting_period'=>['type'=>'THIS_MONTH','start'=>$periodStart,'end_exclusive'=>$periodEnd],'custodians'=>$custodians];
});
