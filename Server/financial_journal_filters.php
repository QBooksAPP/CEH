<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user();qbook_require_role($user,['ADMIN']);production_require_method('GET');
accounts_endpoint(function():array{
  $db=production_db();
  return [
    'source_types'=>$db->query("SELECT DISTINCT source_module FROM qbook_financial_journals ORDER BY source_module")->fetchAll(PDO::FETCH_COLUMN),
    'projects'=>$db->query("SELECT id,name FROM qbook_projects ORDER BY name")->fetchAll(),
    'equipment'=>$db->query("SELECT id,code AS name FROM qbook_mixers ORDER BY code")->fetchAll(),
    'clients'=>$db->query("SELECT id,name FROM qbook_clients ORDER BY name")->fetchAll(),
    'cost_centres'=>$db->query("SELECT id,CONCAT(code,' — ',name) AS name FROM qbook_cost_centres ORDER BY code")->fetchAll(),
    'users'=>$db->query("SELECT id,full_name AS name FROM qbook_users ORDER BY full_name")->fetchAll(),
  ];
});
