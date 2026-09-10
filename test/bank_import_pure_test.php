<?php
declare(strict_types=1);
require_once __DIR__.'/../Server/bank_import_common.php';
production_discard_output();restore_exception_handler();
set_exception_handler(function(Throwable $e):never{fwrite(STDERR,$e->getMessage().' at '.$e->getLine()."\n");exit(1);});
$checks=0;
function bi_check(bool $ok,string $why):void{global $checks;$checks++;if(!$ok)throw new RuntimeException($why);}
function bi_reject(callable $f,string $code):void{try{$f();}catch(AccountsApiError $e){bi_check($e->errorCode===$code,'Wrong error '.$e->errorCode);return;}throw new RuntimeException('Expected '.$code);}
function bi_rows():array{return [['Create Date',' Effective Date',' Description/Payee/Memo',' Debit Amount',' Credit Amount',' Balance',' Transaction Ref'],['01/09/2026','01/09/2026','Transfer charge','50','','950',''],['01/09/2026','01/09/2026','Transfer charge','50','','900',''],['01/09/2026','01/09/2026','VAT and charge','53.75','','846.25','REUSED'],['01/09/2026','01/09/2026','VAT and charge','53.75','','792.50','REUSED']];}
$p=bank_zenith_normalize(bi_rows(),'Activity_Statement');
bi_check($p['summary']['can_import']&&count($p['rows'])===4,'Repeated charges lost');
bi_check(array_column($p['rows'],'occurrence')===[1,2,1,2],'Occurrence identity');
bi_check(array_column($p['rows'],'source_row')===[2,3,4,5],'Source row identity');
bi_check($p['summary']['debits_value']==='207.50'&&$p['summary']['repeated_value_rows']===4,'Totals');
bi_check($p['summary']['opening_balance']==='1000.00'&&$p['summary']['closing_balance']==='792.50','Balances');
foreach(['50','50.00','NGN 50.00','₦50.00','1,250.50','-50.00'] as $v)bi_check(is_int(bank_amount($v)),'Currency parser');
foreach(['1,00','abc','1.001','1e3','--50','NaN'] as $v)bi_reject(fn()=>bank_amount($v),'INVALID_BANK_AMOUNT');
bi_reject(fn()=>bank_date('31/02/2026'),'INVALID_BANK_DATE');
foreach([['50','10'],['0','0'],['-50',''],['abc','']] as [$d,$c]){$r=bi_rows();$r[1][3]=$d;$r[1][4]=$c;$p=bank_zenith_normalize($r,'CSV');bi_check(!$p['summary']['can_import']&&$p['rows'][0]['outcome']==='INVALID','Bad debit/credit accepted');}
$r=bi_rows();$r[2][5]='899';bi_check(!bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Balance mismatch accepted');
$r=bi_rows();$r[]=['Total Debits: 4 Total Credits: 0','','','NGN 207.50','NGN 0','',''];bi_check(bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Valid footer');
$r[5][3]='NGN 208.00';bi_check(!bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Footer mismatch');
$r=bi_rows();$r[0][0]='Unknown date';bi_reject(fn()=>bank_zenith_normalize($r,'CSV'),'ZENITH_HEADERS_MISMATCH');
bi_reject(fn()=>bank_admin(['role'=>'OPERATOR']),'FORBIDDEN');
bi_check(function_exists('bank_normalize_text'),'Reconciliation helper unavailable');
$r=bi_rows();$r[1][6]='UNIQUE-1';$r[2][6]='UNIQUE-2';$p=bank_zenith_normalize($r,'CSV');
bi_check($p['summary']['can_import']&&count($p['rows'])===4&&$p['rows'][0]['fingerprint']!==$p['rows'][1]['fingerprint'],'Distinct references retained');
$r=bi_rows();$r[1][2]=str_repeat('x',501);$p=bank_zenith_normalize($r,'CSV');bi_check($p['rows'][0]['reason']==='INVALID_BANK_TEXT','Long text must become explicit invalid row');
$r=bi_rows();$r[1][2]="bad\0text";bi_check(!bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Control characters accepted');
$r=bi_rows();$r[]=['Total Debits: 4 Total Credits: 0','','','207.50','0','Cleared balance: NGN 792.50',''];
bi_check(bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Declared closing balance');
$r[5][5]='Cleared balance: NGN 792.51';bi_check(in_array('CLOSING_BALANCE_MISMATCH',bank_zenith_normalize($r,'CSV')['summary']['errors'],true),'Bad closing balance accepted');
$r=bi_rows();$r[]=['UNCLEARED ITEMS'];$r[]=['Total Debits: 1 Total Credits: 0','','','50','0'];bi_check(!bank_zenith_normalize($r,'CSV')['summary']['can_import'],'Uncleared activity accepted');
$r=bi_rows();$r[1][0]='02/09/2026';$r[1][5]='792.50';$r[2][5]='950';$r[3][5]='896.25';$r[4][5]='842.50';
$p=bank_zenith_normalize($r,'CSV');bi_check($p['summary']['can_import']&&array_column($p['rows'],'source_row')===[2,3,4,5],'Booking order changed physical row identity');
$tmp=tempnam(sys_get_temp_dir(),'ceh-parser-');
try{
 $f=fopen($tmp,'wb');foreach(bi_rows() as $r)fputcsv($f,$r,',','"','');fclose($f);
 $p=bank_parse_file($tmp,'CSV');bi_check($p['file_sha256']===hash_file('sha256',$tmp),'Server file hash');
 bi_check($p['byte_size']===filesize($tmp)&&$p['summary']['can_import'],'CSV import');
 bi_reject(fn()=>bank_parse_file($tmp,'CSV','UNKNOWN'),'UNSUPPORTED_BANK_ADAPTER');
 foreach(['<worksheet><dimension ref="A1:XFD1048576"/></worksheet>','<worksheet><sheetData><row r="1"><c r="XFD1"/></row></sheetData></worksheet>','<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]><worksheet/>'] as $xml){
  unlink($tmp);$z=new ZipArchive();$z->open($tmp,ZipArchive::CREATE);$z->addFromString('xl/worksheets/sheet1.xml',$xml);$z->close();
  try{bank_xlsx_guard($tmp);throw new RuntimeException('Unsafe workbook accepted');}catch(AccountsApiError $e){bi_check(in_array($e->errorCode,['XLSX_LIMIT_EXCEEDED','UNSAFE_XLSX'],true),'Workbook guard');}
 }
}finally{if(is_file($tmp))unlink($tmp);}
echo "BANK_IMPORT_PURE_PASSED checks=$checks\n";
