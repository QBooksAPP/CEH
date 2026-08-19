<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

const QBOOK_STONE_SIZES = ['3/8"', '1/2"', '3/4 Down'];
const QBOOK_CLIENT_VALIDATION_STATUSES = [
    'PENDING_VALIDATION', 'VALIDATED', 'REQUIRES_REVISION'
];

function qbook_stone_size(mixed $value): string {
    $stoneSize = trim((string)$value);
    if (!in_array($stoneSize, QBOOK_STONE_SIZES, true)) {
        qbook_json(['ok' => false, 'error' => 'INVALID_STONE_SIZE'], 422);
    }
    return $stoneSize;
}
function qbook_active_job_context(PDO $db, int $clientId, int $projectId): array {
    if ($clientId <= 0 || $projectId <= 0) {
        qbook_json(['ok' => false, 'error' => 'CLIENT_PROJECT_REQUIRED'], 422);
    }
    $stmt = $db->prepare(
        "SELECT c.id AS client_id, c.name AS client_name,
                p.id AS project_id, p.name AS project_name
         FROM qbook_clients c
         JOIN qbook_projects p ON p.client_id = c.id
         WHERE c.id = ? AND p.id = ? AND c.is_active = 1 AND p.is_active = 1
         LIMIT 1"
    );
    $stmt->execute([$clientId, $projectId]);
    $context = $stmt->fetch();
    if (!$context) qbook_json(['ok' => false, 'error' => 'ACTIVE_CLIENT_PROJECT_REQUIRED'], 422);
    return $context;
}

function qbook_absolute_volume_deviation(float $absoluteVolume): array {
    $deviation = $absoluteVolume - 1.0;
    if (abs($deviation) < 0.0000005) {
        return ['deviation_m3' => 0.0, 'deviation_status' => 'EXACT'];
    }
    return [
        'deviation_m3' => $deviation,
        'deviation_status' => $deviation < 0 ? 'SHORT' : 'EXCESS',
    ];
}
