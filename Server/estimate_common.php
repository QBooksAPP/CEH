<?php
declare(strict_types=1);
require_once __DIR__ . '/billing_common.php';

function estimate_locked(PDO $db, int $id): array {
    $s=$db->prepare('SELECT * FROM qbook_estimates WHERE id=? FOR UPDATE');$s->execute([$id]);$r=$s->fetch();
    if(!$r)accounts_fail('ESTIMATE_NOT_FOUND',404);return$r;
}
function estimate_display(array $row): array {
    $row['reference']=billing_ref('ESTIMATE',$row['reference_no']);
    $row['expired_warning']=$row['status']==='SENT' && $row['valid_until']!==null && $row['valid_until']<gmdate('Y-m-d');
    return$row;
}
function estimate_lines(PDO $db,array $input,int $clientId,string $vatMode,?array $tax): array {
    $copy=$input;$raw=$input['lines']??[];$copy['lines']=[];
    foreach($raw as $line){if(!is_array($line))accounts_fail('INVALID_ESTIMATE_LINE');$line['source_type']='MANUAL';$copy['lines'][]=$line;}
    return billing_invoice_lines($db,$copy,$clientId,$vatMode,$tax);
}
function estimate_require_sent_snapshots(array $estimate): void {
    foreach(['company_legal_name_snapshot','company_address_snapshot','tax_identifier_snapshot','terms_snapshot','pdf_template_version'] as$field){
        if(trim((string)($estimate[$field]??''))==='')accounts_fail('ESTIMATE_SETTINGS_SNAPSHOT_MISSING',409);
    }
}
