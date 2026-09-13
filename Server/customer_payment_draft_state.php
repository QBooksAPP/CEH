<?php
declare(strict_types=1);

/** Historical destinations are context, never reconstructed allocation intent. */
function customer_payment_legacy_review_required(array $receipt): bool {
    return ($receipt['status'] ?? '') === 'DRAFT'
        && ($receipt['journal_id'] ?? null) === null
        && ($receipt['statement_row_id'] ?? null) === null
        && ($receipt['creation_request_key'] ?? null) === null;
}

function customer_payment_reviewed_intent(array $receipt): ?array {
    $payload = json_decode((string)($receipt['draft_payload'] ?? 'null'), true);
    return is_array($payload) && ($payload['kind'] ?? '') === 'LEGACY_REVIEW_V1'
        ? $payload : null;
}
