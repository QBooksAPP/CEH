<?php
declare(strict_types=1);
require_once __DIR__.'/../Server/credit_note_common.php';
require_once __DIR__.'/../Server/credit_note_pdf_common.php';
set_exception_handler(static function(Throwable $e):void{production_discard_output();fwrite(STDERR,$e->getMessage()."\n".$e->getTraceAsString());exit(1);});
$kind=$argv[1]??'';$output=$argv[2]??'';
if(!in_array($kind,['partial','multi-line-release'],true)||$output==='')throw new RuntimeException('Usage: partial|multi-line-release output.pdf');
$count=$kind==='partial'?2:12;
$invoice=['reference_no'=>900001,'invoice_date'=>'2026-09-01','client_name_snapshot'=>'QA SAMPLE - Client Engineering Limited (not production data)',
 'company_legal_name_snapshot'=>'Concrete Equipment Hire Limited','company_address_snapshot'=>"12 Agbado Road\nIju Ishaga, Lagos, Nigeria",'tax_identifier_snapshot'=>'QA SAMPLE - NOT A TAX DOCUMENT','currency_code_snapshot'=>'NGN'];
$lines=[];
for($i=1;$i<=$count;$i++){
 $allocation=['id'=>$i,'report_reference_snapshot'=>'QA-PRODUCTION-'.str_pad((string)$i,4,'0',STR_PAD_LEFT)];
 $lines[]=['original'=>['description'=>"QA line $i - Concrete supply adjustment for client-approved site reconciliation, including delivery and project-specific service description.",'production_allocations'=>[$allocation]],
 'net_amount'=>'20000.00','vat_amount'=>'1500.00','gross_amount'=>'21500.00',
 'production_releases'=>$kind==='partial'?[]:[['invoice_production_allocation_id'=>$i,'released_m3'=>'2.00']]];
}
$note=['reference'=>'CEH-CN-900001','credit_date'=>'2026-09-07','reason'=>'QA SAMPLE ONLY - Review document layout. These are synthetic accounting values, not a Credit Note issued to a client.',
 'net_amount'=>accounts_minor_decimal(2000000*$count),'vat_amount'=>accounts_minor_decimal(150000*$count),'total_amount'=>accounts_minor_decimal(2150000*$count)];
$bytes=credit_note_pdf_bytes($note,['invoice'=>$invoice,'lines'=>$lines]);
if(!str_starts_with($bytes,'%PDF-'))throw new RuntimeException('Invalid PDF');
if(file_exists($output)&&($argv[3]??'')!=='--replace')throw new RuntimeException('Preview output exists; use --replace for a deliberate local QA refresh');
if(file_put_contents($output,$bytes)!==strlen($bytes))throw new RuntimeException('PDF write failed');
production_discard_output();echo 'PDF_PREVIEW_CREATED bytes='.strlen($bytes).' sha256='.hash('sha256',$bytes)."\n";
