<?php
declare(strict_types=1);

require_once __DIR__.'/estimate_common.php';
require_once __DIR__.'/production_report_common.php';
require_once __DIR__.'/company_regional_common.php';

$user=billing_require_admin();
production_require_method('GET');
$id=(int)($_GET['estimate_id']??0);
$db=production_db();
$statement=$db->prepare("SELECT * FROM qbook_estimates WHERE id=? AND status<>'DRAFT'");
$statement->execute([$id]);
$estimate=$statement->fetch();
if(!$estimate)qbook_json(['ok'=>false,'error'=>'SENT_ESTIMATE_NOT_FOUND'],404);
estimate_require_sent_snapshots($estimate);
$statement=$db->prepare('SELECT * FROM qbook_estimate_lines WHERE estimate_id=? ORDER BY line_no');
$statement->execute([$id]);
$lines=$statement->fetchAll();

try{
    $cache=production_report_cache_directory();
    $logo=production_report_normalize_png((string)file_get_contents(__DIR__.'/assets/ceh_logo.png'));
    if(!defined('K_PATH_CACHE'))define('K_PATH_CACHE',$cache);
    require_once __DIR__.'/vendor/tcpdf/tcpdf.php';

    $pdf=new class('P','mm','A4',true,'UTF-8',false) extends TCPDF {
        public function disableGeneratorLink(): void {
            $this->tcpdflink=false;
        }

        public function Footer(): void {
            $this->SetY(-13);
            $this->SetDrawColor(190,190,190);
            $this->Line(15,$this->GetY(),195,$this->GetY());
            $this->Ln(2.5);
            $this->SetTextColor(90,90,90);
            $this->SetFont('dejavusans','',7);
            $this->Cell(130,5,'CEH Estimate',0,0,'L');
            $this->Cell(50,5,'Page '.$this->getAliasNumPage().' of '.$this->getAliasNbPages(),0,0,'R');
        }
    };
    $pdf->disableGeneratorLink();
    $pdf->SetCreator((string)$estimate['company_legal_name_snapshot']);
    $pdf->SetAuthor((string)$estimate['company_legal_name_snapshot']);
    $pdf->SetTitle('CEH Estimate');
    $pdf->SetPrintHeader(false);
    $pdf->SetPrintFooter(true);
    $pdf->SetMargins(15,13,15);
    $pdf->SetAutoPageBreak(true,18);
    $pdf->setCellPaddings(1.8,1.2,1.8,1.2);
    $pdf->AddPage();

    // CEH Estimate palette follows the approved monochrome company logo.
    $ink=[20,20,20];
    $primary=[18,18,18];
    $secondary=[75,75,75];
    $pale=[245,245,245];
    $background=[250,250,250];
    $border=[190,190,190];
    $pdf->SetTextColor(...$ink);
    $pdf->SetDrawColor(...$border);

    $pdf->Image('@'.$logo,15,13,48,0,'PNG');
    $pdf->SetXY(82,13);
    $pdf->SetFont('dejavusans','B',11);
    $pdf->MultiCell(113,5.6,(string)$estimate['company_legal_name_snapshot'],0,'R',false,1);
    $pdf->SetX(90);
    $pdf->SetFont('dejavusans','',8);
    $pdf->SetTextColor(...$secondary);
    $pdf->MultiCell(105,4.3,(string)$estimate['company_address_snapshot'],0,'R',false,1);
    $pdf->SetX(90);
    $pdf->MultiCell(105,4.3,'TIN: '.(string)$estimate['tax_identifier_snapshot'],0,'R',false,1);
    $headerBottom=max(35.0,$pdf->GetY()+2);
    $pdf->SetDrawColor(...$primary);
    $pdf->SetLineWidth(0.7);
    $pdf->Line(15,$headerBottom,195,$headerBottom);

    $reference=billing_ref('ESTIMATE',$estimate['reference_no']);
    $estimateDate=(new DateTimeImmutable($estimate['estimate_date']))->format('d-m-Y');
    $validUntil=(new DateTimeImmutable($estimate['valid_until']))->format('d-m-Y');
    $currency=company_document_currency($estimate['currency_code_snapshot']??null);
    $money=static fn($value):string=>company_money($value,$currency);

    $pdf->SetY($headerBottom+6);
    $pdf->SetTextColor(...$primary);
    $pdf->SetFont('dejavusans','B',18);
    $pdf->Cell(105,9,'ESTIMATE',0,0,'L');
    $pdf->SetFont('dejavusans','B',10);
    $pdf->SetTextColor(...$secondary);
    $pdf->Cell(75,9,$reference,0,1,'R');
    $pdf->SetFont('dejavusans','',8);
    $pdf->Cell(105,5,'Commercial estimate',0,0,'L');
    $pdf->Cell(75,5,'Estimate date: '.$estimateDate,0,1,'R');

    $pdf->Ln(5);
    $info=[
        ['Client',(string)$estimate['client_name_snapshot']],
        ['Estimate Date',$estimateDate],
        ['Valid Until',$validUntil],
        ['Status',ucwords(strtolower(str_replace('_',' ',(string)$estimate['status'])))],
    ];
    $infoY=$pdf->GetY();
    $rowY=$infoY+3;
    foreach($info as [$unused,$value])$rowY+=max(6.0,$pdf->getStringHeight(134,$value)+1);
    $panelHeight=max(30.0,$rowY-$infoY+2);
    $pdf->SetFillColor(...$pale);
    $pdf->SetDrawColor(...$border);
    $pdf->RoundedRect(15,$infoY,180,$panelHeight,2,'1111','DF');
    $rowY=$infoY+3;
    foreach($info as [$label,$value]){
        $pdf->SetXY(20,$rowY);
        $pdf->SetFont('dejavusans','B',7.5);
        $pdf->SetTextColor(...$secondary);
        $pdf->Cell(34,5,strtoupper($label),0,0,'L');
        $pdf->SetFont('dejavusans','',9);
        $pdf->SetTextColor(...$ink);
        $pdf->MultiCell(134,5,$value,0,'L',false,1);
        $rowY=max($rowY+6,$pdf->GetY());
    }
    $pdf->SetY($infoY+$panelHeight+5);

    $columns=[
        ['DESCRIPTION / PROJECT',65,'L'],['QUANTITY',24,'R'],['RATE',31,'R'],
        ['NET',30,'R'],['VAT',30,'R'],
    ];
    $drawLineHeader=static function(TCPDF $document) use($columns,$primary): void {
        $document->SetFillColor(...$primary);
        $document->SetTextColor(255,255,255);
        $document->SetFont('dejavusans','B',7.2);
        foreach($columns as [$label,$width,$align])$document->Cell($width,8,$label,0,0,$align,true);
        $document->Ln();
    };
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans','B',10);
    $pdf->Cell(180,7,'Estimate lines',0,1,'L');
    $drawLineHeader($pdf);

    foreach($lines as $index=>$line){
        $description=(string)$line['description'];
        if(trim((string)($line['project_snapshot']??''))!=='')$description.="\nProject / Site: ".(string)$line['project_snapshot'];
        $quantity=$line['quantity']===null?'—':number_format((float)$line['quantity'],2).' '.(trim((string)($line['unit_name']??''))?:'unit');
        $rate=$line['unit_price']===null?'—':$money($line['unit_price']);
        $values=[$description,$quantity,$rate,$money($line['net_amount']),$money($line['vat_amount'])];
        $height=10.0;
        foreach($values as $cellIndex=>$value)$height=max($height,$pdf->getStringHeight($columns[$cellIndex][1]-3,$value)+3.5);
        if($pdf->GetY()+$height>242){
            $pdf->AddPage();
            $pdf->SetTextColor(...$ink);
            $pdf->SetFont('dejavusans','B',10);
            $pdf->Cell(180,7,'Estimate lines (continued)',0,1,'L');
            $drawLineHeader($pdf);
        }
        $fill=$index%2===1;
        if($fill)$pdf->SetFillColor(...$background);
        $pdf->SetDrawColor(...$border);
        $pdf->SetTextColor(...$ink);
        $pdf->SetFont('dejavusans','',7.6);
        foreach($values as $cellIndex=>$value){
            [$unused,$width,$align]=$columns[$cellIndex];
            $pdf->MultiCell($width,$height,$value,1,$align,$fill,($cellIndex===count($values)-1?1:0),'','',true,0,false,true,$height,'M');
        }
    }

    $totals=[
        ['Net',$estimate['net_amount']],
        ['VAT '.billing_format_percent($estimate['vat_rate_snapshot']??0),$estimate['vat_amount']],
        ['TOTAL',$estimate['total_amount']],
    ];
    if($pdf->GetY()+38>265)$pdf->AddPage();
    $pdf->Ln(6);
    $pdf->SetX(95);
    $pdf->SetFont('dejavusans','B',9);
    $pdf->SetTextColor(...$primary);
    $pdf->Cell(100,6,'Estimate summary',0,1,'L');
    foreach($totals as [$label,$amount]){
        $highlight=$label==='TOTAL';
        $pdf->SetX(95);
        $pdf->SetFillColor(...($highlight?$pale:[255,255,255]));
        $pdf->SetFont('dejavusans',$highlight?'B':'',8.7);
        $pdf->SetTextColor(...($highlight?$primary:$ink));
        $pdf->Cell(63,7,$label,$highlight?'TB':'B',0,'L',$highlight);
        $pdf->Cell(37,7,$money($amount),$highlight?'TB':'B',1,'R',$highlight);
    }

    $terms=trim((string)$estimate['terms_snapshot']."\n".(string)($estimate['notes']??''));
    $termsHeight=max(12.0,$pdf->getStringHeight(176,$terms)+5);
    if($pdf->GetY()+$termsHeight+25>265)$pdf->AddPage();
    $pdf->Ln(6);
    $pdf->SetTextColor(...$primary);
    $pdf->SetFont('dejavusans','B',9);
    $pdf->Cell(180,6,'TERMS / NOTES',0,1,'L');
    $pdf->SetFillColor(...$pale);
    $pdf->SetDrawColor(...$border);
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans','',8.5);
    $pdf->MultiCell(180,5,$terms,1,'L',true,1);

    $disclaimer='This Estimate is a non-accounting commercial document and does not constitute an invoice or proof of payment.';
    if($pdf->GetY()+18>265)$pdf->AddPage();
    $pdf->Ln(5);
    $pdf->SetTextColor(...$secondary);
    $pdf->SetFont('dejavusans','I',7.8);
    $pdf->MultiCell(180,5,$disclaimer,0,'L',false,1);

    $bytes=$pdf->Output($reference.'.pdf','S');
    production_report_cleanup_cache_directory($cache);
    production_discard_output();
    header('Content-Type: application/pdf');
    header('Content-Length: '.strlen($bytes));
    header('Content-Disposition: attachment; filename="'.$reference.'.pdf"');
    header('Cache-Control: private, no-store');
    header('X-Content-Type-Options: nosniff');
    echo $bytes;
    exit;
}catch(Throwable $error){
    if(isset($cache))production_report_cleanup_cache_directory($cache);
    error_log('CEH Estimate PDF failed type='.get_class($error));
    qbook_json(['ok'=>false,'error'=>'ESTIMATE_PDF_FAILED'],500);
}
