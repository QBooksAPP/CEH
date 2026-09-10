<?php
declare(strict_types=1);
require_once __DIR__.'/accounts_common.php';
require_once __DIR__.'/vendor/simplexlsx/SimpleXLSX.php';

function bank_text(mixed $value,int $max,bool $required=false):string {
    if(!is_scalar($value)&&$value!==null)accounts_fail('INVALID_BANK_TEXT');
    $text=trim((string)$value);
    if(!mb_check_encoding($text,'UTF-8')||mb_strlen($text,'UTF-8')>$max||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F]/',$text)||($required&&$text===''))accounts_fail('INVALID_BANK_TEXT');
    return $text;
}
function bank_normalize_text(mixed $value,int $max):string {
    return mb_strtolower(trim((string)preg_replace('/\s+/u',' ',bank_text($value,$max))),'UTF-8');
}
function bank_amount(mixed $value,bool $blankZero=false):int {
    $s=trim((string)$value);
    if($s===''&&$blankZero)return 0;
    $s=preg_replace('/^(?:NGN|₦)\s*/u','',$s);
    if(!preg_match('/^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$/D',$s))accounts_fail('INVALID_BANK_AMOUNT');
    return accounts_money_minor(str_replace(',','',$s),false);
}
function bank_date(mixed $value):string {
    $s=trim((string)$value);
    foreach(['!d/m/Y','!Y-m-d','!Y-m-d H:i:s'] as $format){
        $d=DateTimeImmutable::createFromFormat($format,$s,new DateTimeZone('UTC'));
        $errors=DateTimeImmutable::getLastErrors();
        if($d&&($errors===false||($errors['warning_count']===0&&$errors['error_count']===0)))return $d->format('Y-m-d');
    }
    accounts_fail('INVALID_BANK_DATE');
}
/** Reject active content and bound decompression BEFORE the XLSX library runs. */
function bank_xlsx_guard(string $path):void {
    if(!class_exists('ZipArchive'))accounts_fail('XLSX_RUNTIME_UNAVAILABLE',503);
    $z=new ZipArchive();if($z->open($path)!==true)accounts_fail('INVALID_XLSX');
    try{
        if($z->numFiles>200)accounts_fail('XLSX_LIMIT_EXCEEDED');
        $total=0;
        for($i=0;$i<$z->numFiles;$i++){
            $s=$z->statIndex($i);$name=$s['name'];$total+=$s['size'];
            if($s['size']>8000000||$total>20000000||str_contains($name,'..')||str_contains($name,'\\')||str_starts_with($name,'/')||preg_match('/vbaProject|externalLinks|embeddings/i',$name))accounts_fail('UNSAFE_XLSX');
            if(str_ends_with($name,'.xml')||str_ends_with($name,'.rels')){
                $xml=$z->getFromIndex($i);if($xml===false||preg_match('/<!DOCTYPE|<!ENTITY|TargetMode\s*=\s*["\x27]External/i',$xml))accounts_fail('UNSAFE_XLSX');
                if(preg_match('/<dimension[^>]+ref=["\x27][^"\x27]*[A-Z]+([0-9]+)["\x27]/',$xml,$m)&&(int)$m[1]>12000)accounts_fail('XLSX_LIMIT_EXCEEDED');
                // Cell references, not only the optional dimension, can drive allocations.
                if(str_starts_with($name,'xl/worksheets/')){
                    preg_match_all('/\b(?:r|ref)=["\x27]([A-Z]+)([0-9]+)(?::([A-Z]+)([0-9]+))?["\x27]/',$xml,$refs,PREG_SET_ORDER);
                    foreach($refs as $ref){foreach([[ $ref[1],$ref[2] ],[ $ref[3]??'A',$ref[4]??1 ]] as [$col,$row]){
                        $column=0;foreach(str_split($col) as $letter)$column=$column*26+ord($letter)-64;
                        if($column>20||(int)$row>12000)accounts_fail('XLSX_LIMIT_EXCEEDED');
                    }}
                    if(preg_match('/<row\b[^>]*\br=["\x27]([0-9]{6,})["\x27]/',$xml))accounts_fail('XLSX_LIMIT_EXCEEDED');
                }
            }
        }
    }finally{$z->close();}
}
/** Adapter registry is explicit: a format name is never inferred from a bank name. */
function bank_parse_file(string $path,string $type,string $adapter='ZENITH_ACTIVITY_V1'):array {
    if($adapter!=='ZENITH_ACTIVITY_V1')accounts_fail('UNSUPPORTED_BANK_ADAPTER');
    if(!is_file($path)||filesize($path)===0||filesize($path)>10000000)accounts_fail('STATEMENT_SIZE_LIMIT');
    $sheet='CSV';$all=[];$excluded=[];
    if($type==='XLSX'){
        bank_xlsx_guard($path);$x=\Shuchkin\SimpleXLSX::parse($path);
        if(!$x)accounts_fail('INVALID_XLSX');
        $index=array_search('Activity_Statement',$x->sheetNames(),true);
        if($index===false)accounts_fail('ZENITH_SHEET_REQUIRED');
        $sheet='Activity_Statement';[$cols,$count]=$x->dimension($index);
        $excluded=array_values(array_diff($x->sheetNames(),[$sheet]));
        if($cols>20||$count>12000)accounts_fail('XLSX_LIMIT_EXCEEDED');
        foreach($x->readRowsEx($index) as $row){foreach($row as $cell)if(($cell['f']??'')!=='')accounts_fail('STATEMENT_FORMULAS_NOT_ALLOWED');$all[]=array_column($row,'value');}
    }elseif($type==='CSV'){
        $f=fopen($path,'rb');try{while(($row=fgetcsv($f,0,',','"',''))!==false){if(count($row)>20)accounts_fail('STATEMENT_COLUMN_LIMIT');$all[]=$row;if(count($all)>12000)accounts_fail('STATEMENT_ROW_LIMIT');}}finally{fclose($f);}
        if(isset($all[0][0]))$all[0][0]=preg_replace('/^\xEF\xBB\xBF/','',(string)$all[0][0]);
    }else accounts_fail('UNSUPPORTED_STATEMENT_TYPE');
    return bank_zenith_normalize($all,$sheet)+['adapter'=>$adapter,'excluded_non_statement_sheets'=>$excluded,'file_sha256'=>hash_file('sha256',$path),'byte_size'=>filesize($path)];
}
function bank_zenith_normalize(array $all,string $sheet):array {
    $headers=['create date','effective date','description/payee/memo','debit amount','credit amount','balance','transaction ref'];
    if(array_map(fn($v)=>strtolower(trim((string)$v)),$all[0]??[])!==$headers)accounts_fail('ZENITH_HEADERS_MISMATCH');
    $rows=[];$counts=[];$values=[];$debit=$credit=$dc=$cc=0;$opening=$closing=null;$prior=null;$errors=[];$metadata=[];$dates=[];$footer=false;$declaredClosing=[];$uncleared=false;
    foreach(array_slice($all,1,null,true) as $index=>$raw){
        $source=$index+1;$raw=array_pad($raw,7,'');$first=trim((string)$raw[0]);
        if(count(array_filter($raw,fn($v)=>trim((string)$v)!==''))===0){$metadata[]=['source_row'=>$source,'kind'=>'BLANK'];continue;}
        if(preg_match('/^(Total Debits:|Cleared balance as at:|UNCLEARED ITEMS|No uncleared items|Total Cleared:|Totals \(Cleared|\d+ Debit\(s\)|Total Cheques\/|NGN -)/i',$first)){
            $footer=true;$metadata[]=['source_row'=>$source,'kind'=>'STATEMENT_CONTROL'];
            if(strcasecmp($first,'UNCLEARED ITEMS')===0)$uncleared=true;
            if($uncleared&&preg_match('/^Total Debits: (\d+)\s+Total Credits: (\d+)$/',$first,$m)&&(int)$m[1]+(int)$m[2]>0)$errors[]='UNSUPPORTED_UNCLEARED_ITEMS';
            foreach($raw as $control){if(preg_match('/Cleared balance[^:]*:\s*(?:NGN|₦)\s*(-?[\d,]+(?:\.\d{1,2})?)/i',(string)$control,$closingMatch)){
                try{$declaredClosing[]=bank_amount($closingMatch[1]);}catch(AccountsApiError){$errors[]='INVALID_CLOSING_BALANCE';}
            }}
            if(preg_match('/^Total Debits: (\d+)\s+Total Credits: (\d+)$/',$first,$m)&&$m[1]+$m[2]>0){
                try{if((int)$m[1]!==$dc||(int)$m[2]!==$cc||bank_amount($raw[3])!==$debit||bank_amount($raw[4])!==$credit)$errors[]='FOOTER_TOTAL_MISMATCH';}catch(AccountsApiError){$errors[]='INVALID_FOOTER_TOTAL';}
            }
            continue;
        }
        $r=['source_sheet'=>$sheet,'source_row'=>$source,'outcome'=>'VALID','reason'=>null];
        try{
            if($footer)accounts_fail('UNSUPPORTED_UNCLEARED_OR_TRAILING_ROW');
            $date=bank_date($raw[0]);$value=trim((string)$raw[1])===''?null:bank_date($raw[1]);
            $d=bank_amount($raw[3],true);$c=bank_amount($raw[4],true);
            if($d<0||$c<0||($d>0)==($c>0))accounts_fail('DEBIT_CREDIT_EXCLUSIVITY');
            $amount=$c-$d;$balance=bank_amount($raw[5]);
            if(count($raw)>7&&count(array_filter(array_slice($raw,7),fn($v)=>trim((string)$v)!=='')))accounts_fail('UNEXPECTED_STATEMENT_COLUMNS');
            $memo=bank_text($raw[2],500,true);$ref=bank_text($raw[6],150);
            $fp=hash('sha256',$date.'|'.$amount.'|'.bank_normalize_text($ref,150).'|'.bank_normalize_text($memo,500));
            $ordinal=($counts[$fp]??0)+1;$counts[$fp]=$ordinal;
            $signature=$date.'|'.$amount.'|'.bank_normalize_text($memo,500);$values[$signature]=($values[$signature]??0)+1;
            if($debit>9000000000000000-$d||$credit>9000000000000000-$c)accounts_fail('STATEMENT_TOTAL_LIMIT');
            $debit+=$d;$credit+=$c;$dc+=(int)($d>0);$cc+=(int)($c>0);$dates[]=$date;
            $r+=['date'=>$date,'value_date'=>$value,'amount'=>accounts_minor_decimal($amount),'balance'=>accounts_minor_decimal($balance),'narration'=>$memo,'reference'=>$ref,'fingerprint'=>$fp,'occurrence'=>$ordinal];
        }catch(AccountsApiError $e){$r['outcome']='INVALID';$r['reason']=$e->errorCode;}
        $rows[]=$r;
    }
    if(!$rows)accounts_fail('STATEMENT_ROWS_REQUIRED');
    $ordered=array_filter($rows,fn($r)=>$r['outcome']==='VALID');
    uasort($ordered,fn($a,$b)=>[$a['date'],$a['source_row']]<=>[$b['date'],$b['source_row']]);
    foreach($ordered as $key=>$row){$amount=bank_amount($row['amount']);$balance=bank_amount($row['balance']);if($opening===null)$opening=$balance-$amount;if($prior!==null&&$prior+$amount!==$balance){$rows[$key]['outcome']='INVALID';$rows[$key]['reason']='RUNNING_BALANCE_MISMATCH';}$prior=$closing=$balance;}
    foreach($declaredClosing as $declared)if($declared!==$closing)$errors[]='CLOSING_BALANCE_MISMATCH';
    $invalid=count(array_filter($rows,fn($r)=>$r['outcome']==='INVALID'));
    return ['rows'=>$rows,'metadata_rows'=>$metadata,'summary'=>['total_rows'=>count($rows),'debits_count'=>$dc,'debits_value'=>accounts_minor_decimal($debit),'credits_count'=>$cc,'credits_value'=>accounts_minor_decimal($credit),'repeated_value_rows'=>array_sum(array_map(fn($n)=>$n>1?$n:0,$values)),'invalid_rows'=>$invalid,'opening_balance'=>$opening===null?null:accounts_minor_decimal($opening),'opening_balance_basis'=>'INFERRED_FROM_FIRST_TRANSACTION','balance_check_order'=>'CREATE_DATE_THEN_SOURCE_ROW','closing_balance'=>$closing===null?null:accounts_minor_decimal($closing),'statement_from'=>$dates?min($dates):null,'statement_to'=>$dates?max($dates):null,'errors'=>array_values(array_unique($errors)),'can_import'=>$invalid===0&&$errors===[]]];
}
