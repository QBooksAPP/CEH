<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('GET');
accounts_endpoint(function() use($user): array {
    $db=production_db();
    $admin=strtoupper((string)$user['role'])==='ADMIN';
    if(!$admin) accounts_custodian($db,(int)$user['id'],true);
    $where=$admin?'':"WHERE account_type='EXPENSE' AND is_postable=1 AND is_active=1";
    $rows=$db->query("SELECT id,code,name,account_type,parent_id,is_postable,is_active FROM qbook_accounts_chart $where ORDER BY code")->fetchAll();
    return ['accounts'=>array_map(static fn(array $r): array=>[
        'id'=>(int)$r['id'],'code'=>$r['code'],'name'=>$r['name'],'account_type'=>$r['account_type'],
        'parent_id'=>$r['parent_id']!==null?(int)$r['parent_id']:null,'is_postable'=>(bool)$r['is_postable'],'is_active'=>(bool)$r['is_active'],
    ],$rows)];
});
