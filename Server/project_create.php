<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST');
$in=production_input(); $clientId=(int)($in['client_id']??0);
$name=production_clean_text($in['name']??'',200,'PROJECT_NAME_REQUIRED'); $db=production_db();
$s=$db->prepare("SELECT id FROM qbook_clients WHERE id=? AND is_active=1"); $s->execute([$clientId]);
if(!$s->fetch()) qbook_json(['ok'=>false,'error'=>'ACTIVE_CLIENT_REQUIRED'],422);
$s=$db->prepare("SELECT id FROM qbook_projects WHERE client_id=? AND LOWER(name)=LOWER(?)"); $s->execute([$clientId,$name]);
if($s->fetch()) qbook_json(['ok'=>false,'error'=>'PROJECT_NAME_EXISTS'],409);
$db->prepare("INSERT INTO qbook_projects(client_id,name,is_active) VALUES(?,?,1)")->execute([$clientId,$name]);
$id=(int)$db->lastInsertId(); qbook_audit($user,'PROJECT_CREATED','PROJECT',$id,['client_id'=>$clientId,'name'=>$name]);
qbook_json(['ok'=>true,'project'=>['id'=>$id,'client_id'=>$clientId,'name'=>$name,'is_active'=>true]],201);
