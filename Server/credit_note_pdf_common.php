<?php
declare(strict_types=1);
require_once __DIR__.'/production_report_common.php';
require_once __DIR__.'/company_regional_common.php';

/** Render only frozen document/accounting values; no database reads or posting. */
function credit_note_pdf_bytes(array $note,array $document,string $dateFormat='DD-MM-YYYY'):string {
 $invoice=$document['invoice'];
 foreach(['company_legal_name_snapshot','company_address_snapshot','tax_identifier_snapshot'] as $key){
  if(trim((string)($invoice[$key]??''))==='')throw new RuntimeException('INVOICE_SETTINGS_SNAPSHOT_MISSING');
 }
 $cache=production_report_cache_directory();
 if(!defined('K_PATH_CACHE'))define('K_PATH_CACHE',$cache);
 require_once __DIR__.'/vendor/tcpdf/tcpdf.php';
 if(!class_exists('CehCreditNotePdf',false)){
  final class CehCreditNotePdf extends TCPDF {
   public string $reference='';
   public function suppressAttribution():void{$this->tcpdflink=false;}
   public function Header():void{
    if($this->getPage()<=1)return;
    $this->SetXY(15,5);$this->SetFont('dejavusans','',8);$this->SetTextColor(75,75,75);
    $this->Cell(180,5,'CREDIT NOTE '.$this->reference.' — Continued',0,0,'L');
   }
   public function Footer():void{
    $this->SetY(-13);$this->SetDrawColor(190,190,190);$this->Line(15,$this->GetY(),195,$this->GetY());$this->Ln(2.5);
    $this->SetFont('dejavusans','',7);$this->SetTextColor(90,90,90);
    $this->Cell(130,5,$this->reference,0,0,'L');$this->Cell(50,5,'Page '.$this->getAliasNumPage().' of '.$this->getAliasNbPages(),0,0,'R');
   }
  }
 }
 try{
  $pdf=new CehCreditNotePdf('P','mm','A4',true,'UTF-8',false);
  $pdf->reference=$note['reference'];$pdf->suppressAttribution();$pdf->SetPrintHeader(true);$pdf->SetPrintFooter(true);
  $pdf->SetCreator($invoice['company_legal_name_snapshot']);$pdf->SetAuthor($invoice['company_legal_name_snapshot']);$pdf->SetTitle($note['reference'].' Credit Note');
  $pdf->SetMargins(15,13,15);$pdf->SetAutoPageBreak(true,18);$pdf->setCellPaddings(1.8,1.2,1.8,1.2);$pdf->AddPage();
  $logo=production_report_normalize_png((string)file_get_contents(__DIR__.'/assets/ceh_logo.png'));
  $pdf->Image('@'.$logo,15,13,48,0,'PNG');
  $pdf->SetXY(82,13);$pdf->SetFont('dejavusans','B',11);$pdf->SetTextColor(20,20,20);
  $pdf->MultiCell(113,5.6,$invoice['company_legal_name_snapshot'],0,'R',false,1);
  $pdf->SetX(90);$pdf->SetFont('dejavusans','',8);$pdf->SetTextColor(75,75,75);
  $pdf->MultiCell(105,4.3,$invoice['company_address_snapshot'],0,'R',false,1);$pdf->SetX(90);
  $pdf->MultiCell(105,4.3,'TIN: '.$invoice['tax_identifier_snapshot'],0,'R',false,1);
  $y=max(35.0,$pdf->GetY()+2);$pdf->SetDrawColor(18,18,18);$pdf->SetLineWidth(.7);$pdf->Line(15,$y,195,$y);$pdf->SetY($y+6);
  $pdf->SetTextColor(18,18,18);$pdf->SetFont('dejavusans','B',18);$pdf->Cell(105,9,'CREDIT NOTE',0,0);$pdf->SetFont('dejavusans','B',10);$pdf->Cell(75,9,$note['reference'],0,1,'R');$pdf->Ln(5);
  $date=static fn(string $v):string=>(new DateTimeImmutable($v))->format(match($dateFormat){'MM-DD-YYYY'=>'m-d-Y','YYYY-MM-DD'=>'Y-m-d',default=>'d-m-Y'});
  $e=static fn(mixed $v):string=>htmlspecialchars((string)$v,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');
  $grid=static fn(string $html):string=>str_replace([' border="1"','<td ','<th '],['','<td style="border:0.5pt solid #bebebe;" ','<th style="border:0.5pt solid #bebebe;" '],$html);
  $currency=company_document_currency($invoice['currency_code_snapshot']??null);$money=static fn(mixed $v):string=>company_money($v,$currency);
  $pdf->SetFont('dejavusans','',9);$pdf->SetTextColor(20,20,20);$pdf->SetLineWidth(.2);$pdf->SetDrawColor(190,190,190);
  $meta=['Client'=>$invoice['client_name_snapshot'],'Credit Note date'=>$date($note['credit_date']),
   'Original invoice'=>billing_ref('INVOICE',$invoice['reference_no']),'Invoice date'=>$date($invoice['invoice_date'])];
  $html='<table cellpadding="5" border="1" style="border-color:#bebebe;background-color:#ffffff;">';
  foreach($meta as $label=>$value)$html.='<tr><td width="28%"><b>'.$e($label).'</b></td><td width="72%">'.$e($value).'</td></tr>';
  $pdf->writeHTML($grid($html.'</table>'),true,false,true,false,'');$pdf->Ln(4);
  $html='<table cellpadding="5" border="1" style="border-color:#bebebe;background-color:#ffffff;"><thead><tr style="background-color:#121212;color:#ffffff;"><th width="52%"><b>Credited invoice line / quantity release</b></th><th width="16%" align="right"><b>Net</b></th><th width="14%" align="right"><b>VAT</b></th><th width="18%" align="right"><b>Total credit</b></th></tr></thead><tbody>';
  foreach($document['lines'] as $line){
   $description=$e($line['original']['description']);
   $releases=$line['production_releases']??[];
   foreach($releases as $release){$ref='Production allocation';foreach($line['original']['production_allocations']??[] as $a)if((int)$a['id']===(int)$release['invoice_production_allocation_id'])$ref=$a['report_reference_snapshot'];$description.='<br/><span style="font-size:8pt">'.$e($ref).': '.$e($release['released_m3']).' m³ released</span>';}
   if(!$releases)$description.='<br/><span style="font-size:8pt">Monetary credit - no quantity released</span>';
   $html.='<tr nobr="true" style="background-color:#ffffff;"><td width="52%">'.$description.'</td><td width="16%" align="right">'.$e($money($line['net_amount'])).'</td><td width="14%" align="right">'.$e($money($line['vat_amount'])).'</td><td width="18%" align="right">'.$e($money($line['gross_amount'])).'</td></tr>';
  }
  $pdf->writeHTML($grid($html.'</tbody></table>'),true,false,true,false,'');$pdf->Ln(3);
  $html='<table cellpadding="5" nobr="true">';foreach(['Net credit'=>'net_amount','VAT credit'=>'vat_amount','Total credit'=>'total_amount'] as $label=>$key)$html.='<tr><td width="65%" align="right"><b>'.$label.'</b></td><td width="35%" align="right"><b>'.$e($money($note[$key])).'</b></td></tr>';
  $pdf->writeHTML($html.'</table>',true,false,true,false,'');
  $pdf->writeHTML('<h3>Reason for credit</h3><p>'.$e($note['reason']).'</p>',true,false,true,false,'');
  $pdf->SetFont('dejavusans','',8);$pdf->MultiCell(180,5,'Credit applied to the original invoice. This document does not confirm a cash refund.',0,'L');
  return $pdf->Output('credit-note.pdf','S');
 }finally{production_report_cleanup_cache_directory($cache);}
}
