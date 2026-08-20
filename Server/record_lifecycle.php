<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    qbook_json(['ok'=>false,'error'=>'METHOD_NOT_ALLOWED'],405);
}
$input=json_decode(file_get_contents('php://input'),true);
if(!is_array($input)) qbook_json(['ok'=>false,'error'=>'INVALID_JSON'],400);
$type=strtoupper(trim((string)($input['record_type']??'')));
$action=strtoupper(trim((string)($input['action']??'')));
$id=(int)($input['record_id']??0);
$tables=['CLIENT'=>'qbook_clients','PROJECT'=>'qbook_projects',
    'CALIBRATION'=>'qbook_calibrations','MIX_DESIGN'=>'qbook_mix_designs'];
if(!isset($tables[$type])||!in_array($action,['ARCHIVE','RESTORE','DELETE'],true)||$id<=0){
    qbook_json(['ok'=>false,'error'=>'INVALID_LIFECYCLE_REQUEST'],422);
}
$db=qbook_db(); $table=$tables[$type];
$stmt=$db->prepare("SELECT * FROM {$table} WHERE id=?"); $stmt->execute([$id]);
$record=$stmt->fetch();
if(!$record) qbook_json(['ok'=>false,'error'=>'RECORD_NOT_FOUND'],404);

function lifecycle_audit(PDO $db,array $user,string $event,string $type,int $id,array $details):void{
    $stmt=$db->prepare("INSERT INTO qbook_audit_log
        (user_id,event_type,source_type,source_id,details,ip_address)
        VALUES(?,?,?,?,?,?)");
    $stmt->execute([(int)$user['id'],$event,$type,$id,
        json_encode($details,JSON_THROW_ON_ERROR|JSON_INVALID_UTF8_SUBSTITUTE),
        qbook_client_ip()]);
}

try {
    $db->beginTransaction();
    if($action==='ARCHIVE'||$action==='RESTORE'){
        $archiving=$action==='ARCHIVE';
        $activeColumn=$type==='CALIBRATION'?'':', is_active=' . ($archiving?'0':'1');
        $sql="UPDATE {$table} SET archived_at=" . ($archiving?'UTC_TIMESTAMP()':'NULL') .
            ", archived_by=" . ($archiving?'?':'NULL') . $activeColumn . " WHERE id=?";
        $params=$archiving?[(int)$user['id'],$id]:[$id];
        $db->prepare($sql)->execute($params);
        lifecycle_audit($db,$user,$type.'_'.$action,$type,$id,
            ['previous_archived_at'=>$record['archived_at']??null,
             'changed_at_utc'=>gmdate('Y-m-d\TH:i:s\Z')]);
    } else {
        $checks=match($type){
            'CLIENT'=>[['qbook_projects','client_id'],['qbook_calibrations','client_id'],
                ['qbook_mix_designs','client_id'],['qbook_production_sessions','client_id']],
            'PROJECT'=>[['qbook_project_mixers','project_id'],['qbook_calibrations','project_id'],
                ['qbook_mix_designs','project_id'],['qbook_production_sessions','project_id']],
            'CALIBRATION'=>[['qbook_production_settings','calibration_id'],
                ['qbook_calibration_revision_snapshots','calibration_id']],
            'MIX_DESIGN'=>[['qbook_production_settings','mix_design_id']],
        };
        foreach($checks as [$referenceTable,$column]){
            $check=$db->prepare("SELECT 1 FROM {$referenceTable} WHERE {$column}=? LIMIT 1");
            $check->execute([$id]);
            if($check->fetchColumn()) throw new RuntimeException('DELETE_BLOCKED_BY_REFERENCE');
        }
        $allowedChildren=$type==='CALIBRATION'
            ? ['qbook_calibration_trials','qbook_calibration_results']
            : ($type==='MIX_DESIGN'?['qbook_mix_admixtures']:[]);
        $fk=$db->prepare(
            "SELECT DISTINCT TABLE_NAME,COLUMN_NAME FROM information_schema.KEY_COLUMN_USAGE
             WHERE REFERENCED_TABLE_SCHEMA=DATABASE() AND REFERENCED_TABLE_NAME=?
               AND REFERENCED_COLUMN_NAME='id'"
        );
        $fk->execute([$table]);
        foreach($fk->fetchAll() as $reference){
            $referenceTable=(string)$reference['TABLE_NAME'];
            $column=(string)$reference['COLUMN_NAME'];
            if(in_array($referenceTable,$allowedChildren,true))continue;
            if(!preg_match('/^[A-Za-z0-9_]+$/',$referenceTable.$column)){
                throw new RuntimeException('DELETE_BLOCKED_BY_REFERENCE');
            }
            $check=$db->prepare("SELECT 1 FROM `{$referenceTable}` WHERE `{$column}`=? LIMIT 1");
            $check->execute([$id]);
            if($check->fetchColumn())throw new RuntimeException('DELETE_BLOCKED_BY_REFERENCE');
        }
        if($type==='CALIBRATION' && ((string)$record['status']!=='DRAFT'||
            $record['submitted_at']!==null||$record['reviewed_at']!==null)){
            throw new RuntimeException('DELETE_BLOCKED_BY_CALIBRATION_STATUS');
        }
        $audit=$db->prepare(
            "SELECT 1 FROM qbook_audit_log WHERE source_type=? AND source_id=?
             AND event_type NOT IN ('CLIENT_CREATED','CLIENT_UPDATED','CLIENT_ARCHIVE','CLIENT_RESTORE',
               'PROJECT_CREATED','PROJECT_UPDATED','PROJECT_ARCHIVE','PROJECT_RESTORE',
               'MIX_CREATED','MIX_UPDATED','MIX_ACTIVATED','MIX_DEACTIVATED',
               'MIX_DESIGN_ARCHIVE','MIX_DESIGN_RESTORE') LIMIT 1"
        );
        $audit->execute([$type,$id]);
        if($audit->fetchColumn()) throw new RuntimeException('DELETE_BLOCKED_BY_AUDIT_EVIDENCE');
        if($type==='CALIBRATION'){
            $db->prepare('DELETE FROM qbook_calibration_results WHERE calibration_id=?')->execute([$id]);
            $db->prepare('DELETE FROM qbook_calibration_trials WHERE calibration_id=?')->execute([$id]);
        } elseif($type==='MIX_DESIGN'){
            $db->prepare('DELETE FROM qbook_mix_admixtures WHERE mix_design_id=?')->execute([$id]);
        }
        $db->prepare("DELETE FROM {$table} WHERE id=?")->execute([$id]);
        lifecycle_audit($db,$user,$type.'_DELETED',$type,$id,
            ['deleted_record'=>$record,'deleted_at_utc'=>gmdate('Y-m-d\TH:i:s\Z')]);
    }
    $db->commit();
    qbook_json(['ok'=>true,'record_type'=>$type,'record_id'=>$id,'action'=>$action]);
} catch(PDOException $e){
    if($db->inTransaction())$db->rollBack();
    qbook_json(['ok'=>false,'error'=>'DELETE_BLOCKED_BY_REFERENCE'],409);
} catch(RuntimeException $e){
    if($db->inTransaction())$db->rollBack();
    qbook_json(['ok'=>false,'error'=>$e->getMessage()],409);
} catch(Throwable $e){
    if($db->inTransaction())$db->rollBack();
    qbook_json(['ok'=>false,'error'=>'SERVER_ERROR'],500);
}
