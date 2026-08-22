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
    $custodians=[];$total=0;
    foreach($s->fetchAll() as $row){$balance=accounts_custodian_balance($db,(int)$row['user_id']);$total+=accounts_money_minor($balance['balance'],false);$custodians[]=['id'=>(int)$row['id'],'user_id'=>(int)$row['user_id'],'name'=>$row['full_name'],'role'=>$row['role'],'balance'=>accounts_public_balance($balance)];}
    return ['total_petty_cash'=>accounts_minor_decimal($total),'custodians'=>$custodians];
});
