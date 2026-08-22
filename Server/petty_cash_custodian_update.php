<?php
declare(strict_types=1);
require_once __DIR__ . '/accounts_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST'); $input=production_input();
accounts_endpoint(function() use($user,$input): array {
    $target=(int)($input['user_id']??0); if($target<=0) accounts_fail('USER_REQUIRED');
    $active=filter_var($input['is_active']??true,FILTER_VALIDATE_BOOLEAN,FILTER_NULL_ON_FAILURE); if($active===null) accounts_fail('INVALID_ACTIVE_STATUS');
    $db=production_db();
    return accounts_transaction($db,function() use($db,$user,$target,$active): array {
        $s=$db->prepare("SELECT id,full_name,is_active FROM qbook_users WHERE id=? AND role IN('ADMIN','OPERATOR') FOR UPDATE");$s->execute([$target]);$u=$s->fetch();
        if(!$u || !(bool)$u['is_active']) accounts_fail('ACTIVE_USER_REQUIRED');
        $s=$db->prepare("SELECT id FROM qbook_petty_cash_custodians WHERE user_id=? FOR UPDATE");$s->execute([$target]);$id=$s->fetchColumn();
        if($id){$db->prepare("UPDATE qbook_petty_cash_custodians SET is_active=?,updated_by=? WHERE id=?")->execute([$active?1:0,(int)$user['id'],(int)$id]);}
        else{$db->prepare("INSERT INTO qbook_petty_cash_custodians(user_id,is_active,designated_by,updated_by) VALUES(?,?,?,?)")->execute([$target,$active?1:0,(int)$user['id'],(int)$user['id']]);$id=(int)$db->lastInsertId();}
        accounts_audit($db,$user,'PETTY_CASH_CUSTODIAN_UPDATED','PETTY_CASH_CUSTODIAN',(int)$id,['user_id'=>$target,'is_active'=>$active]);
        return ['custodian'=>['id'=>(int)$id,'user_id'=>$target,'name'=>$u['full_name'],'is_active'=>$active]];
    });
});
