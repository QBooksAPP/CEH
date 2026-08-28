<?php
declare(strict_types=1);

require_once __DIR__.'/billing_common.php';
require_once __DIR__.'/production_report_common.php';
require_once __DIR__.'/company_regional_common.php';

$user=billing_require_admin();
production_require_method('GET');
$id=(int)($_GET['payment_id']??0);
if($id<=0)qbook_json(['ok'=>false,'error'=>'CLIENT_PAYMENT_REQUIRED'],422);

$db=production_db();
$statement=$db->prepare("SELECT * FROM qbook_customer_receipts WHERE id=? AND status='POSTED'");
$statement->execute([$id]);
$receipt=$statement->fetch();
if(!$receipt)qbook_json(['ok'=>false,'error'=>'POSTED_CLIENT_PAYMENT_NOT_FOUND'],404);
foreach(['company_legal_name_snapshot','company_address_snapshot','tax_identifier_snapshot','received_into_snapshot','pdf_template_version'] as $field){
    if(trim((string)($receipt[$field]??''))==='')qbook_json(['ok'=>false,'error'=>'CLIENT_PAYMENT_SNAPSHOT_MISSING'],409);
}

$statement=$db->prepare("SELECT a.*,i.reference_no invoice_reference_no,i.total_amount invoice_total,
    GROUP_CONCAT(DISTINCT NULLIF(l.project_snapshot,'') ORDER BY l.project_snapshot SEPARATOR ' • ') project_names,
    t.code wht_code,w.rate_snapshot,w.calculation_base_snapshot,w.calculation_base_amount,
    w.accepted_amount,w.certificate_status
    FROM qbook_customer_receipt_allocations a
    JOIN qbook_invoices i ON i.id=a.invoice_id
    LEFT JOIN qbook_invoice_lines l ON l.invoice_id=i.id
    LEFT JOIN qbook_customer_receipt_allocation_wht w ON w.receipt_allocation_id=a.id
    LEFT JOIN qbook_tax_codes t ON t.id=w.tax_code_id
    WHERE a.receipt_id=? GROUP BY a.id ORDER BY a.id");
$statement->execute([$id]);
$allocations=$statement->fetchAll();

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
            $this->Cell(130,5,'CEH Payment Receipt',0,0,'L');
            $this->Cell(50,5,'Page '.$this->getAliasNumPage().' of '.$this->getAliasNbPages(),0,0,'R');
        }
    };
    $pdf->disableGeneratorLink();
    $pdf->SetCreator((string) $receipt['company_legal_name_snapshot']);
    $pdf->SetAuthor((string)$receipt['company_legal_name_snapshot']);
    $pdf->SetTitle('CEH Client Payment Receipt');
    $pdf->SetPrintHeader(false);
    $pdf->SetPrintFooter(true);
    $pdf->SetMargins(15,13,15);
    $pdf->SetAutoPageBreak(true,18);
    $pdf->setCellPaddings(1.8,1.2,1.8,1.2);
    $pdf->AddPage();

    // CEH receipt palette follows the approved monochrome company logo.
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
    $pdf->MultiCell(113,5.6,(string)$receipt['company_legal_name_snapshot'],0,'R',false,1);
    $pdf->SetX(90);
    $pdf->SetFont('dejavusans','',8);
    $pdf->SetTextColor(...$secondary);
    $pdf->MultiCell(105,4.3,(string)$receipt['company_address_snapshot'],0,'R',false,1);
    $pdf->SetX(90);
    $pdf->MultiCell(105,4.3,'TIN: '.(string)$receipt['tax_identifier_snapshot'],0,'R',false,1);
    $headerBottom=max(35.0,$pdf->GetY()+2);
    $pdf->SetDrawColor(...$primary);
    $pdf->SetLineWidth(0.7);
    $pdf->Line(15,$headerBottom,195,$headerBottom);

    $reference=billing_ref('RECEIPT',$receipt['reference_no']);
    $paymentDate=(new DateTimeImmutable($receipt['receipt_date']))->format('d-m-Y');
    $currency=company_document_currency($receipt['currency_code_snapshot']??null);
    $money=static fn($value):string=>company_money($value,$currency);

    $pdf->SetY($headerBottom+6);
    $pdf->SetTextColor(...$primary);
    $pdf->SetFont('dejavusans','B',18);
    $pdf->Cell(105,9,'PAYMENT RECEIPT',0,0,'L');
    $pdf->SetFont('dejavusans','B',10);
    $pdf->SetTextColor(...$secondary);
    $pdf->Cell(75,9,$reference,0,1,'R');
    $pdf->SetFont('dejavusans','',8);
    $pdf->SetTextColor(...$secondary);
    $pdf->Cell(105,5,'Official acknowledgement of Client payment',0,0,'L');
    $pdf->Cell(75,5,'Payment date: '.$paymentDate,0,1,'R');

    $pdf->Ln(5);
    $info=[
        ['Client',(string)$receipt['client_name_snapshot']],
        ['Payment Date',$paymentDate],
        ['Received Into',(string)$receipt['received_into_snapshot']],
        ['Bank Reference',trim((string)($receipt['bank_reference']??''))?:'Not provided'],
    ];
    $infoY=$pdf->GetY();
    $pdf->SetFillColor(...$pale);
    $pdf->RoundedRect(15,$infoY,180,30,2,'1111','DF');
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
    $pdf->SetY(max($infoY+35,$rowY+2));

    $columns=[
        ['INVOICE',29,'L'],['PROJECT / SITE',39,'L'],['INVOICE TOTAL',30,'R'],
        ['CASH APPLIED',28,'R'],['WHT',24,'R'],['SETTLEMENT',30,'R'],
    ];
    $drawAllocationHeader=static function(TCPDF $document) use($columns,$primary): void {
        $document->SetFillColor(...$primary);
        $document->SetTextColor(255,255,255);
        $document->SetFont('dejavusans','B',7.2);
        foreach($columns as [$label,$width,$align])$document->Cell($width,8,$label,0,0,$align,true);
        $document->Ln();
    };
    $pdf->SetTextColor(...$ink);
    $pdf->SetFont('dejavusans','B',10);
    $pdf->Cell(180,7,'Invoice allocation',0,1,'L');
    $drawAllocationHeader($pdf);

    $cashApplied=0.0;
    $wht=0.0;
    foreach($allocations as $index=>$allocation){
        $cashApplied+=(float)$allocation['cash_amount'];
        $wht+=(float)$allocation['wht_amount'];
        $invoice=billing_ref('INVOICE',$allocation['invoice_reference_no']);
        $project=trim((string)($allocation['project_names']??''))?:'Not specified';
        $values=[
            $invoice,$project,$money($allocation['invoice_total']),$money($allocation['cash_amount']),
            $money($allocation['wht_amount']),$money((float)$allocation['cash_amount']+(float)$allocation['wht_amount']),
        ];
        $height=10.0;
        foreach($values as $cellIndex=>$value)$height=max($height,$pdf->getStringHeight($columns[$cellIndex][1]-3,$value)+3.5);
        if($pdf->GetY()+$height>268){
            $pdf->AddPage();
            $pdf->SetTextColor(...$ink);
            $pdf->SetFont('dejavusans','B',10);
            $pdf->Cell(180,7,'Invoice allocation (continued)',0,1,'L');
            $drawAllocationHeader($pdf);
        }
        $fill=$index%2===1;
        if($fill)$pdf->SetFillColor(...$background);
        $pdf->SetTextColor(...$ink);
        $pdf->SetFont('dejavusans','',7.6);
        foreach($values as $cellIndex=>$value){
            [$unused,$width,$align]=$columns[$cellIndex];
            $pdf->MultiCell($width,$height,$value,1,$align,$fill,($cellIndex===count($values)-1?1:0),'','',true,0,false,true,$height,'M');
        }
        if((float)$allocation['wht_amount']>0){
            $detail='WHT '.(string)$allocation['wht_code'].' • '.billing_format_percent($allocation['rate_snapshot'])
                .' • '.str_replace('_',' ',(string)$allocation['calculation_base_snapshot'])
                .' • '.str_replace('_',' ',(string)$allocation['certificate_status']);
            $pdf->SetFont('dejavusans','',7.2);
            $pdf->SetTextColor(...$secondary);
            $pdf->MultiCell(180,5.5,$detail,'LRB','L',false,1);
        }
    }

    $cash=(float)$receipt['cash_amount'];
    $totals=[
        ['Cash Received',$cash],
        ['Cash Applied to Invoices',$cashApplied],
        ['WHT Deducted by Client',$wht],
        ['Total Invoice Settlement',$cashApplied+$wht],
        ['Unallocated Client Credit / Advance',$cash-$cashApplied],
    ];
    $totalsHeight=count($totals)*6.5+9;
    if($pdf->GetY()+$totalsHeight>268)$pdf->AddPage();
    $pdf->Ln(6);
    $pdf->SetX(95);
    $pdf->SetFont('dejavusans','B',9);
    $pdf->SetTextColor(...$primary);
    $pdf->Cell(100,6,'Settlement summary',0,1,'L');
    foreach($totals as [$label,$amount]){
        $highlight=$label==='Total Invoice Settlement';
        $pdf->SetX(95);
        $pdf->SetFillColor(...($highlight?$pale:[255,255,255]));
        $pdf->SetFont('dejavusans',$highlight?'B':'',8.4);
        $pdf->SetTextColor(...($highlight?$primary:$ink));
        $pdf->Cell(63,6.5,$label,$highlight?'TB':'B',0,'L',$highlight);
        $pdf->Cell(37,6.5,$money($amount),$highlight?'TB':'B',1,'R',$highlight);
    }

    if($wht>0){
        $pdf->Ln(5);
        $pdf->SetFillColor(...$pale);
        $pdf->SetTextColor(...$secondary);
        $pdf->SetFont('dejavusans','',7.8);
        $pdf->MultiCell(180,8,'WHT shown above was deducted by the Client and was not cash received by CEH. It is recorded as WHT Receivable.',0,'L',true,1);
    }

    $pdf->SetTextColor(...$secondary);
    $pdf->SetFont('dejavusans','',7.5);
    $pdf->Ln(5);
    $pdf->MultiCell(180,5,'This receipt confirms the payment and settlement allocations shown above.',0,'L',false,1);

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
    error_log('CEH Client Payment PDF failed type='.get_class($error));
    qbook_json(['ok'=>false,'error'=>'CLIENT_PAYMENT_PDF_FAILED'],500);
}
