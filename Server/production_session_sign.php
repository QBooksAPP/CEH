<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN','OPERATOR']); production_require_method('POST'); $in=production_input();
$sessionId=(int)($in['session_id']??0); $name=production_clean_text($in['representative_name']??'',150,'REPRESENTATIVE_NAME_REQUIRED');
$encoded=(string)($in['signature_base64']??''); $binary=base64_decode($encoded,true);
if ($binary===false || strlen($binary)<100 || strlen($binary)>2000000) qbook_json(['ok'=>false,'error'=>'SIGNATURE_REQUIRED'],422);
$mime=(string)($in['signature_mime']??'image/png');
if ($mime!=='image/png' || substr($binary, 0, 8) !== "\x89PNG\r\n\x1a\n") qbook_json(['ok'=>false,'error'=>'INVALID_SIGNATURE_TYPE'],422);
$db=production_db();
try {
  $db->beginTransaction(); $session=production_session_row($db,$sessionId,true);
  if (!production_can_access($user,$session)) { $db->rollBack(); qbook_json(['ok'=>false,'error'=>'FORBIDDEN'],403); }
  if ($session['status']!=='OPEN') { $db->rollBack(); qbook_json(['ok'=>false,'error'=>'SESSION_ALREADY_SIGNED'],409); }
  $stmt=$db->prepare("SELECT COUNT(*) load_count, COALESCE(SUM(volume_m3),0) total_m3 FROM qbook_production_loads WHERE production_session_id=?"); $stmt->execute([$sessionId]); $totals=$stmt->fetch();
  if ((int)$totals['load_count']<1) { $db->rollBack(); qbook_json(['ok'=>false,'error'=>'LOAD_REQUIRED'],422); }
  $now=gmdate('Y-m-d H:i:s');
  $db->prepare("INSERT INTO qbook_production_signoffs (production_session_id, representative_name, signature_mime, signature_data, signature_sha256, load_count, total_m3, signed_at, signed_by_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")->execute([$sessionId,$name,$mime,$binary,hash('sha256',$binary),(int)$totals['load_count'],$totals['total_m3'],$now,(int)$user['id']]);
  $stmt=$db->prepare("UPDATE qbook_production_sessions SET status='SIGNED', signed_at=? WHERE id=? AND status='OPEN'"); $stmt->execute([$now,$sessionId]);
  if ($stmt->rowCount()!==1) throw new RuntimeException('SIGN_RACE');
  $db->commit(); qbook_audit($user,'PRODUCTION_SESSION_SIGNED','PRODUCTION_SESSION',$sessionId,['load_count'=>(int)$totals['load_count'],'total_m3'=>(float)$totals['total_m3'],'signature_sha256'=>hash('sha256',$binary)]);
  qbook_json(['ok'=>true,'session'=>production_payload($db,production_session_row($db,$sessionId),true)]);
} catch (Throwable $e) { if ($db->inTransaction()) $db->rollBack(); qbook_json(['ok'=>false,'error'=>$e instanceof RuntimeException?'SESSION_ALREADY_SIGNED':'SERVER_ERROR'],$e instanceof RuntimeException?409:500); }
