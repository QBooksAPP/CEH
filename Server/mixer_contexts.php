<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN', 'OPERATOR']);
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json(['ok'=>false,'error'=>'METHOD_NOT_ALLOWED'],405);
}

$db=qbook_db();
$includeHistory=$user['role']==='ADMIN' && ($_GET['include_history']??'')==='1';
$mixers=$db->query("SELECT id,code,name FROM qbook_mixers WHERE is_active=1 ORDER BY code")->fetchAll();
$assignmentStmt=$db->prepare(
    "SELECT pm.project_id,pm.is_active,pm.updated_at,p.name AS project_name,
            c.id AS client_id,c.name AS client_name,p.is_active AS project_active,
            p.archived_at AS project_archived,c.is_active AS client_active,
            c.archived_at AS client_archived
     FROM qbook_project_mixers pm
     JOIN qbook_projects p ON p.id=pm.project_id
     JOIN qbook_clients c ON c.id=p.client_id
     WHERE pm.mixer_id=? ORDER BY pm.is_active DESC,pm.updated_at DESC,pm.project_id DESC"
);

$items=[];
foreach($mixers as $mixer){
    $assignmentStmt->execute([(int)$mixer['id']]);
    $active=[];$history=[];
    foreach($assignmentStmt->fetchAll() as $row){
        $entry=[
            'client_id'=>(int)$row['client_id'],'client_name'=>(string)$row['client_name'],
            'project_id'=>(int)$row['project_id'],'project_name'=>(string)$row['project_name'],
            'is_active'=>(bool)$row['is_active'],'updated_at'=>$row['updated_at'],
        ];
        $operational=(bool)$row['is_active'] && (bool)$row['project_active'] &&
            $row['project_archived']===null && (bool)$row['client_active'] &&
            $row['client_archived']===null;
        if($operational)$active[]=$entry;
        if($includeHistory)$history[]=$entry;
    }
    /* No operator-to-mixer assignment exists: Operators see active allocated mixers. */
    if($user['role']!=='ADMIN' && $active===[])continue;
    $items[]=['id'=>(int)$mixer['id'],'code'=>(string)$mixer['code'],
        'name'=>(string)$mixer['name'],'active_assignments'=>$active,
        'assignment_history'=>$history];
}
qbook_json(['ok'=>true,'mixers'=>$items]);
