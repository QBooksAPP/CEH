<?php
// Load the actual endpoint's declared bootstrap without running authentication or a mutation.
declare(strict_types=1);
$endpoint=__DIR__.'/../Server/bank_reconcile.php';
$text=file_get_contents($endpoint);$bootstrap=explode('$user=qbook_require_user()',$text,2)[0];
preg_match_all("~require_once\s+__DIR__\s*\.\s*'([^']+)'\s*;~",$bootstrap,$matches);
if(count($matches[1])<2)throw new RuntimeException('Endpoint dependency declaration changed');
foreach($matches[1] as $path)require_once dirname($endpoint).$path;
production_discard_output();
foreach(['bank_normalize_text','bank_row_available','accounts_transaction','qbook_require_user','qbook_require_role','production_require_method','production_input','production_db','accounts_money_minor','accounts_audit','accounts_endpoint'] as $function){
 if(!function_exists($function)){fwrite(STDERR,'Missing dependency '.$function);exit(1);}
}
if(bank_normalize_text("  BANK\tREFERENCE  ",150)!=='bank reference')exit(1);
echo "BANK_RECONCILE_ENDPOINT_DEPENDENCIES_PASSED checks=12\n";
