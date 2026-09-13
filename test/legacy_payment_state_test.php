<?php
declare(strict_types=1);
require_once __DIR__.'/../Server/customer_payment_draft_state.php';
$legacy=['status'=>'DRAFT','journal_id'=>null,'statement_row_id'=>null,'creation_request_key'=>null,'draft_payload'=>null,'draft_revision'=>0];
function check_state(bool $ok):void {if(!$ok)throw new RuntimeException('Draft classification failed');}
check_state(customer_payment_legacy_review_required($legacy));
check_state(!customer_payment_legacy_review_required(array_replace($legacy,['creation_request_key'=>str_repeat('a',64)])));
check_state(!customer_payment_legacy_review_required(array_replace($legacy,['statement_row_id'=>1])));
check_state(!customer_payment_legacy_review_required(array_replace($legacy,['status'=>'POSTED','journal_id'=>1])));
check_state(!customer_payment_legacy_review_required(array_replace($legacy,['status'=>'CANCELLED'])));
check_state(customer_payment_reviewed_intent($legacy)===null);
check_state(customer_payment_reviewed_intent(array_replace($legacy,['draft_payload'=>'{"kind":"LEGACY_REVIEW_V1","allocations":[]}']))!==null);
echo "LEGACY_PAYMENT_STATE_7_CHECKS_PASSED_NO_DATABASE\n";
