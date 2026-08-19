<?php
declare(strict_types=1);

require_once __DIR__ . '/production_log_common.php';

function production_report_reference(int $reportNo): string {
    return 'CEH-PR-' . str_pad((string)$reportNo, 6, '0', STR_PAD_LEFT);
}

/**
 * Return the permanent report number for a SIGNED session, allocating it once
 * while the caller holds the Production Session row lock and transaction.
 */
function production_report_issue(PDO $db, int $sessionId): array {
    $stmt = $db->prepare(
        "SELECT report_no, issued_at
         FROM qbook_production_reports
         WHERE production_session_id = ?
         LIMIT 1"
    );
    $stmt->execute([$sessionId]);
    $report = $stmt->fetch();
    if (!$report) {
        $issuedAt = gmdate('Y-m-d H:i:s');
        $db->prepare(
            "INSERT INTO qbook_production_reports (production_session_id, issued_at)
             VALUES (?, ?)"
        )->execute([$sessionId, $issuedAt]);
        $report = ['report_no' => (int)$db->lastInsertId(), 'issued_at' => $issuedAt];
    }
    $reportNo = (int)$report['report_no'];
    return [
        'report_no' => $reportNo,
        'reference' => production_report_reference($reportNo),
        'issued_at' => (string)$report['issued_at'],
    ];
}

function production_report_local_time(string $utc): string {
    $value = new DateTimeImmutable($utc, new DateTimeZone('UTC'));
    return $value->setTimezone(new DateTimeZone('Africa/Lagos'))
        ->format('d M Y H:i') . ' WAT';
}
