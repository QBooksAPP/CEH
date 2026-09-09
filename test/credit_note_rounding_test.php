<?php
declare(strict_types=1);
// Pure regressions: no credentials, database connection, or filesystem writes.
require_once __DIR__.'/../Server/credit_note_common.php';
set_exception_handler(static function(Throwable $e):void {production_discard_output();fwrite(STDERR,$e->getMessage()."\n");exit(1);});
$checks=0;
function verify(bool $condition,string $message):void {
 global $checks;$checks++;if(!$condition)throw new RuntimeException($message);
}
function rejects(callable $action,string $code):void {
 try{$action();}catch(AccountsApiError $e){verify($e->errorCode===$code,'Unexpected rejection: '.$e->errorCode);return;}
 throw new RuntimeException('Expected '.$code);
}
foreach([[10000,750],[1,1],[99,7],[2000000,150000],[100,0],[0,100],[9999999999999999,749999999999999]] as [$net,$vat]) {
 foreach([1,2,3,7,19,101] as $parts){
  $usedNet=$usedVat=0;$total=$net+$vat;$step=max(1,intdiv($total,$parts));
  while($usedNet+$usedVat<$total){
   $gross=min($step,$total-$usedNet-$usedVat);
   $s=credit_note_split($net,$vat,$usedNet,$usedVat,$gross);
   verify($s['net']>=0&&$s['vat']>=0&&$s['net']+$s['vat']===$gross,'Invalid split');
   $usedNet+=$s['net'];$usedVat+=$s['vat'];
   verify($usedNet<=$net&&$usedVat<=$vat,'Cumulative component over-credit');
  }
  verify($usedNet===$net&&$usedVat===$vat,'Final residual not consumed exactly');
 }
}
// Legacy rounding can have consumed too much or too little VAT proportionally.
foreach([[100,7,10,7],[100,7,100,0],[100,7,25,1]] as [$n,$v,$un,$uv]){
 $s=credit_note_split($n,$v,$un,$uv,$n+$v-$un-$uv);
 verify($s['net']===$n-$un&&$s['vat']===$v-$uv,'Legacy residual mismatch');
}
rejects(fn()=>credit_note_split(100,7,0,0,108),'CREDIT_EXCEEDS_INVOICE_LINE');
rejects(fn()=>credit_note_split(100,7,0,0,0),'CREDIT_EXCEEDS_INVOICE_LINE');
rejects(fn()=>credit_note_split(100,7,101,0,1),'CREDIT_HISTORY_INTEGRITY_ERROR');
$base=['invoice_id'=>1,'credit_date'=>'2026-09-07','reason'=>'QA only'];
rejects(fn()=>credit_note_input($base+['lines'=>[['invoice_line_id'=>1,'gross_amount'=>'1.00'],['invoice_line_id'=>1,'gross_amount'=>'2.00']]]),'DUPLICATE_CREDIT_INVOICE_LINE');
foreach(['0.00','-1.00','1.001'] as $amount)rejects(fn()=>credit_note_input($base+['lines'=>[['invoice_line_id'=>1,'gross_amount'=>$amount]]]),'INVALID_AMOUNT');
$input=credit_note_input($base+['lines'=>[['invoice_line_id'=>2,'gross_amount'=>'2'],['invoice_line_id'=>1,'gross_amount'=>'1.00']]]);
verify($input['lines'][0]['invoice_line_id']===1,'Canonical line order');
verify($input['lines'][1]['gross_amount']==='2.00','Canonical money');
verify($input['lines'][0]['production_releases']===[],'Price-only credit released quantity');
production_discard_output();
echo "CREDIT_NOTE_PURE_REGRESSIONS_PASSED checks=$checks\n";
