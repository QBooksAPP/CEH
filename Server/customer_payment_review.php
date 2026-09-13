<?php
declare(strict_types=1);
require_once __DIR__.'/customer_payment_review_common.php';
$user=billing_require_admin();
accounts_endpoint(function()use($user):array {
    $db=production_db();
    if(($_SERVER['REQUEST_METHOD']??'')==='GET'){
        $id=(int)($_GET['receipt_id']??0);
        if($id>0) return customer_payment_review_read($db,$user,$id);
        $page=max(1,(int)($_GET['page']??1));$offset=($page-1)*50;
        $rows=$db->query("SELECT r.id,r.reference_no,r.client_name_snapshot,r.cash_amount,r.receipt_date,r.destination,r.draft_payload,r.draft_revision,r.creation_request_key,r.status,r.journal_id,r.statement_row_id FROM qbook_customer_receipts r WHERE r.status='DRAFT' AND r.statement_row_id IS NULL AND (r.creation_request_key IS NULL OR JSON_UNQUOTE(JSON_EXTRACT(r.draft_payload,'$.kind'))='LEGACY_REVIEW_V1') ORDER BY r.id DESC LIMIT 50 OFFSET $offset")->fetchAll();
        $out=[];
        foreach($rows as $r){
            $r['reference']=billing_ref('RECEIPT',$r['reference_no']);
            $r['review_required']=customer_payment_legacy_review_required($r);
            unset($r['draft_payload'],$r['creation_request_key']);$out[]=$r;
        }
        return ['drafts'=>$out,'page'=>$page,'page_size'=>50];
    }
    production_require_method('POST');
    return customer_payment_review_edit($db,$user,production_input());
});
