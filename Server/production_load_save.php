<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user = qbook_require_user(); qbook_require_role($user, ['ADMIN', 'OPERATOR']); production_require_method('POST');
$in = production_input(); $sessionId = (int)($in['session_id'] ?? 0); $loadId = (int)($in['load_id'] ?? 0); $volume = (float)($in['volume_m3'] ?? 0);
if (!is_finite($volume) || $volume <= 0 || $volume > 100) qbook_json(['ok'=>false, 'error'=>'INVALID_LOAD_VOLUME'], 422);
$volume = round($volume, 2); $db = production_db();
try {
  $db->beginTransaction(); $session = production_session_row($db, $sessionId, true);
  if (!production_can_access($user, $session)) { $db->rollBack(); qbook_json(['ok'=>false, 'error'=>'FORBIDDEN'], 403); }
  if ($session['status'] !== 'OPEN') { $db->rollBack(); qbook_json(['ok'=>false, 'error'=>'SIGNED_SESSION_IMMUTABLE'], 409); }
  if ($loadId > 0) {
    $stmt=$db->prepare("SELECT * FROM qbook_production_loads WHERE id=? AND production_session_id=? FOR UPDATE"); $stmt->execute([$loadId,$sessionId]); $load=$stmt->fetch();
    if (!$load) { $db->rollBack(); qbook_json(['ok'=>false,'error'=>'LOAD_NOT_FOUND'],404); }
    $db->prepare("INSERT INTO qbook_production_load_revisions (production_load_id, old_volume_m3, new_volume_m3, changed_by) VALUES (?, ?, ?, ?)")->execute([$loadId,$load['volume_m3'],$volume,(int)$user['id']]);
    $db->prepare("UPDATE qbook_production_loads SET volume_m3=?, updated_by=? WHERE id=?")->execute([$volume,(int)$user['id'],$loadId]);
    $event='PRODUCTION_LOAD_CORRECTED';
  } else {
    // The locked parent session serialises load numbering for this session.
    $stmt=$db->prepare("SELECT COALESCE(MAX(load_number),0)+1 FROM qbook_production_loads WHERE production_session_id=?"); $stmt->execute([$sessionId]); $number=(int)$stmt->fetchColumn();
    $db->prepare("INSERT INTO qbook_production_loads (production_session_id, load_number, volume_m3, recorded_by) VALUES (?, ?, ?, ?)")->execute([$sessionId,$number,$volume,(int)$user['id']]); $loadId=(int)$db->lastInsertId(); $event='PRODUCTION_LOAD_ADDED';
  }
  $db->commit(); qbook_audit($user,$event,'PRODUCTION_LOAD',$loadId,['session_id'=>$sessionId,'volume_m3'=>$volume]);
  qbook_json(['ok'=>true,'session'=>production_payload($db,production_session_row($db,$sessionId))]);
} catch (Throwable $e) { if ($db->inTransaction()) $db->rollBack(); qbook_json(['ok'=>false,'error'=>'SERVER_ERROR'],500); }
