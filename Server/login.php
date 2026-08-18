<?php
declare(strict_types=1); require __DIR__.'/bootstrap.php'; require __DIR__.'/auth.php';
if($_SERVER['REQUEST_METHOD']!=='POST') qbook_json(['ok'=>false,'error'=>'METHOD_NOT_ALLOWED'],405);
$b=json_decode(file_get_contents('php://input'),true)?:[];
$e=strtolower(trim((string)($b['email']??''))); $p=(string)($b['password']??'');
if($e===''||$p==='') qbook_json(['ok'=>false,'error'=>'EMAIL_AND_PASSWORD_REQUIRED'],400);
$s=qbook_db()->prepare("SELECT id,full_name,email,phone,role,password_hash,is_active FROM qbook_users WHERE LOWER(email)=? LIMIT 1");
$s->execute([$e]); $u=$s->fetch();
if(!$u||!$u['is_active']||empty($u['password_hash'])||!password_verify($p,$u['password_hash'])) qbook_json(['ok'=>false,'error'=>'INVALID_CREDENTIALS'],401);
$t=bin2hex(random_bytes(32)); $x=gmdate('Y-m-d H:i:s',time()+2592000);
qbook_db()->prepare("INSERT INTO qbook_auth_tokens(user_id,token_hash,expires_at,created_ip,user_agent) VALUES(?,?,?,?,?)")->execute([$u['id'],qbook_token_hash($t),$x,$_SERVER['REMOTE_ADDR']??null,substr($_SERVER['HTTP_USER_AGENT']??'',0,255)]);
unset($u['password_hash']); $u['id']=(int)$u['id']; $u['is_active']=(bool)$u['is_active'];
qbook_json(['ok'=>true,'token'=>$t,'tokenType'=>'Bearer','expiresAt'=>$x.'Z','user'=>$u]);
