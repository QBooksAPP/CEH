<?php
declare(strict_types=1);
// Executes unmodified endpoint files and their real authentication against only
// the disposable localhost database created by credit_note_mysql_test.php.
final class CreditNoteCgiHarness {
 private string $directory;
 private string $token;
 private PDO $db;
 public function __construct(PDO $db){
  if($db->query('SELECT DATABASE()')->fetchColumn()!=='ceh_credit_note_disposable_test')throw new RuntimeException('Disposable database required');
  $this->db=$db;
  if((int)$db->query("SELECT COUNT(*) FROM mysql.user WHERE User='ceh_cn_local_test'")->fetchColumn()!==0)throw new RuntimeException('Local test account already exists');
  $password=bin2hex(random_bytes(24));
  $db->exec("CREATE USER 'ceh_cn_local_test'@'localhost' IDENTIFIED BY ".$db->quote($password));
  $db->exec("GRANT ALL ON ceh_credit_note_disposable_test.* TO 'ceh_cn_local_test'@'localhost'");
  $this->directory=sys_get_temp_dir().DIRECTORY_SEPARATOR.'ceh-cn-cgi-'.bin2hex(random_bytes(12));
  mkdir($this->directory,0700);
  foreach(glob(__DIR__.'/../Server/*.php') as $source){if(basename($source)==='config.php')continue;copy($source,$this->directory.DIRECTORY_SEPARATOR.basename($source));}
  $config=['db'=>['host'=>'127.0.0.1','port'=>33318,'name'=>'ceh_credit_note_disposable_test','charset'=>'utf8mb4','user'=>'ceh_cn_local_test','password'=>$password],'app'=>['environment'=>'local-test']];
  file_put_contents($this->directory.'/config.php','<?php return '.var_export($config,true).';');
  $this->token=bin2hex(random_bytes(32));
  $db->prepare('INSERT INTO qbook_auth_tokens(user_id,token_hash,expires_at) VALUES(1,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 HOUR))')->execute([hash('sha256',$this->token)]);
 }
 public function start(string $endpoint,array $input):array {
  if(!in_array($endpoint,['credit_note_issue.php','credit_note_quote.php','customer_receipt_post.php','customer_advance_apply.php','invoice_void.php','invoice_issue.php','financial_evidence_upload.php'],true))throw new RuntimeException('Endpoint not allowed');
  $body=json_encode($input,JSON_THROW_ON_ERROR);
  $env=getenv();$env['REDIRECT_STATUS']='1';$env['GATEWAY_INTERFACE']='CGI/1.1';$env['REQUEST_METHOD']='POST';$env['SCRIPT_FILENAME']=$this->directory.'/'.$endpoint;$env['SCRIPT_NAME']='/'.$endpoint;$env['CONTENT_TYPE']='application/json';$env['CONTENT_LENGTH']=(string)strlen($body);$env['HTTP_AUTHORIZATION']='Bearer '.$this->token;$env['SERVER_PROTOCOL']='HTTP/1.1';
  $binary=dirname(PHP_BINARY).DIRECTORY_SEPARATOR.'php-cgi.exe';
  $process=proc_open([$binary,'-d','extension_dir='.ini_get('extension_dir'),'-d','extension=pdo_mysql','-d','extension=mbstring'],[['pipe','r'],['pipe','w'],['pipe','w']],$pipes,$this->directory,$env);
  if(!is_resource($process))throw new RuntimeException('CGI start failed');
  fwrite($pipes[0],$body);fclose($pipes[0]);return [$process,$pipes];
 }
 public function finish(array $running):array {
  [$process,$pipes]=$running;$output=stream_get_contents($pipes[1]);$error=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);$exit=proc_close($process);
  $parts=preg_split('/\r?\n\r?\n/',$output,2);$json=json_decode($parts[1]??'',true);
  if($exit!==0||!is_array($json))throw new RuntimeException('CGI response failed: '.$error.' '.substr($output,0,500));
  if(($json['error']??'')==='SERVER_ERROR')$json['_test_diagnostic']=$error;
  return $json;
 }
 public function call(string $endpoint,array $input):array{return $this->finish($this->start($endpoint,$input));}
 public function close():void {
  $this->db->exec("DROP USER 'ceh_cn_local_test'@'localhost'");
  $resolved=realpath($this->directory);$parent=realpath(sys_get_temp_dir());
  if($resolved===false||dirname($resolved)!==$parent||!str_starts_with(basename($resolved),'ceh-cn-cgi-'))throw new RuntimeException('Unsafe temporary path');
  foreach(glob($resolved.DIRECTORY_SEPARATOR.'*') as $file){if(!is_file($file)||is_link($file))throw new RuntimeException('Unexpected temporary entry');unlink($file);}
  rmdir($resolved);
 }
}
