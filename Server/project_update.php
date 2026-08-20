<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST');
$in=production_input(); $id=(int)($in['project_id']??0);
$name=production_clean_text($in['name']??'',200,'PROJECT_NAME_REQUIRED');
$active=filter_var($in['is_active']??null,FILTER_VALIDATE_BOOL,FILTER_NULL_ON_FAILURE);
if($id<=0||$active===null) qbook_json(['ok'=>false,'error'=>'INVALID_PROJECT'],422);
$db=production_db(); $s=$db->prepare("SELECT id,client_id,name,is_active FROM qbook_projects WHERE id=?"); $s->execute([$id]); $before=$s->fetch();
if(!$before) qbook_json(['ok'=>false,'error'=>'PROJECT_NOT_FOUND'],404);
$s=$db->prepare("SELECT id FROM qbook_projects WHERE client_id=? AND LOWER(name)=LOWER(?) AND id<>?"); $s->execute([(int)$before['client_id'],$name,$id]);
if($s->fetch()) qbook_json(['ok'=>false,'error'=>'PROJECT_NAME_EXISTS'],409);
$db->prepare("UPDATE qbook_projects SET name=?,is_active=?,
 archived_at=IF(?=1,NULL,UTC_TIMESTAMP()),archived_by=IF(?=1,NULL,?) WHERE id=?")
 ->execute([$name,$active?1:0,$active?1:0,$active?1:0,(int)$user['id'],$id]);
qbook_audit($user,'PROJECT_UPDATED','PROJECT',$id,['old_name'=>$before['name'],'name'=>$name,'old_is_active'=>(bool)$before['is_active'],'is_active'=>$active]);
qbook_json(['ok'=>true,'project'=>['id'=>$id,'client_id'=>(int)$before['client_id'],'name'=>$name,'is_active'=>$active]]);
