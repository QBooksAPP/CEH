<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('GET');
accounts_endpoint(function(): array {
    $rows=production_db()->query("SELECT id,code,name,account_type,parent_id,is_postable,is_active FROM qbook_accounts_chart ORDER BY code")->fetchAll();
    return ['accounts'=>array_map(static fn(array $r): array=>[
        'id'=>(int)$r['id'],'code'=>$r['code'],'name'=>$r['name'],'account_type'=>$r['account_type'],
        'parent_id'=>$r['parent_id']!==null?(int)$r['parent_id']:null,'is_postable'=>(bool)$r['is_postable'],'is_active'=>(bool)$r['is_active'],
    ],$rows)];
});
