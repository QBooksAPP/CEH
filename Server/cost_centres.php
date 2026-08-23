<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); production_require_method('GET');
accounts_endpoint(function() use($user): array {
    $db=production_db();
    if(strtoupper((string)$user['role'])!=='ADMIN') accounts_custodian($db,(int)$user['id'],false);
    $rows=$db->query("SELECT id,code,name,description,display_order,is_active FROM qbook_cost_centres WHERE is_active=1 ORDER BY display_order,name")->fetchAll();
    return ['cost_centres'=>array_map(static fn(array $row): array=>[
        'id'=>(int)$row['id'],'code'=>$row['code'],'name'=>$row['name'],'description'=>$row['description'],
        'display_order'=>(int)$row['display_order'],'is_active'=>(bool)$row['is_active'],
    ],$rows)];
});
