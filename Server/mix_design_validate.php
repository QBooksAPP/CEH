<?php
declare(strict_types=1);
require_once __DIR__ . '/production_log_common.php';
require_once __DIR__ . '/job_context.php';
$user=qbook_require_user(); qbook_require_role($user,['ADMIN']); production_require_method('POST');
$in=production_input(); $id=(int)($in['mix_design_id']??0); $status=strtoupper(trim((string)($in['status']??'')));
if($id<=0 || !in_array($status,['VALIDATED','REQUIRES_REVISION'],true)) qbook_json(['ok'=>false,'error'=>'INVALID_CLIENT_VALIDATION'],422);
$db=production_db(); $s=$db->prepare("SELECT id,design_mode,client_validation_status,cement_kg,sand_kg,granite_kg,water_l,air_pct,cement_sg,sand_sg,granite_sg FROM qbook_mix_designs WHERE id=?"); $s->execute([$id]); $mix=$s->fetch();
if(!$mix) qbook_json(['ok'=>false,'error'=>'MIX_DESIGN_NOT_FOUND'],404);
if($mix['design_mode']!=='CLIENT') qbook_json(['ok'=>false,'error'=>'CLIENT_DESIGN_REQUIRED'],409);
$volume=(float)$mix['cement_kg']/((float)$mix['cement_sg']*1000)+(float)$mix['sand_kg']/((float)$mix['sand_sg']*1000)+(float)$mix['granite_kg']/((float)$mix['granite_sg']*1000)+(float)$mix['water_l']/1000+(float)$mix['air_pct'];
$deviation=qbook_absolute_volume_deviation($volume); $now=gmdate('Y-m-d H:i:s');
$db->prepare("UPDATE qbook_mix_designs SET client_validation_status=?,client_validated_by=?,client_validated_at=?,updated_by=?,updated_at=? WHERE id=?")->execute([$status,(int)$user['id'],$now,(int)$user['id'],$now,$id]);
qbook_audit($user,'CLIENT_MIX_VALIDATION_CHANGED','MIX_DESIGN',$id,['old_status'=>$mix['client_validation_status'],'new_status'=>$status,'absolute_volume_m3'=>round($volume,4),'deviation_m3'=>round($deviation['deviation_m3'],4),'deviation_status'=>$deviation['deviation_status']]);
qbook_json(['ok'=>true,'mix_design_id'=>$id,'client_validation_status'=>$status,'calculated_absolute_volume_m3'=>round($volume,4),'absolute_volume_deviation_m3'=>round($deviation['deviation_m3'],4),'absolute_volume_deviation_status'=>$deviation['deviation_status']]);
