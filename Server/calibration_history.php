<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

$user = qbook_require_user();
qbook_require_role($user, ['ADMIN']);

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    qbook_json([
        'ok' => false,
        'error' => 'METHOD_NOT_ALLOWED'
    ], 405);
}

$db = qbook_db();

$mixerId = isset($_GET['mixer_id'])
    ? (int)$_GET['mixer_id']
    : 0;

$status = isset($_GET['status'])
    ? strtoupper(trim((string)$_GET['status']))
    : '';

$limit = isset($_GET['limit'])
    ? (int)$_GET['limit']
    : 100;

if ($limit < 1) {
    $limit = 1;
}

if ($limit > 500) {
    $limit = 500;
}

$allowedStatuses = [
    'DRAFT',
    'SUBMITTED',
    'APPROVED',
    'REJECTED'
];

if ($status !== '' && !in_array($status, $allowedStatuses, true)) {
    qbook_json([
        'ok' => false,
        'error' => 'INVALID_STATUS'
    ], 400);
}

$sql = "
    SELECT
        c.id,
        c.mixer_id,
        c.calibration_date,
        c.calibration_notes,

        c.container_weight_kg,
        c.stone_moisture_pct,
        c.sand_moisture_pct,
        c.cement_safety_factor_pct,

        c.status,
        c.entered_by,
        c.submitted_at,
        c.reviewed_by,
        c.reviewed_at,
        c.rejection_reason,
        c.revision_no,

        c.created_at,
        c.updated_at,

        m.code AS mixer_code,
        m.name AS mixer_name,
        m.model AS mixer_model,
        m.truck_number,

        entered.full_name AS entered_by_name,
        reviewed.full_name AS reviewed_by_name

    FROM qbook_calibrations c

    JOIN qbook_mixers m
        ON m.id = c.mixer_id

    JOIN qbook_users entered
        ON entered.id = c.entered_by

    LEFT JOIN qbook_users reviewed
        ON reviewed.id = c.reviewed_by

    WHERE 1 = 1
";

$params = [];

if ($mixerId > 0) {
    $sql .= " AND c.mixer_id = ?";
    $params[] = $mixerId;
}

if ($status !== '') {
    $sql .= " AND c.status = ?";
    $params[] = $status;
}

$sql .= "
    ORDER BY
        c.calibration_date DESC,
        c.created_at DESC,
        c.id DESC
    LIMIT " . $limit;

$stmt = $db->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll();

$resultStmt = $db->prepare(
    "SELECT
        material,
        gate_cm,
        avg_total_weight_kg,
        avg_counts,
        moisture_pct,
        net_dry_weight_kg,
        kg_per_count,
        calculated_at

     FROM qbook_calibration_results

     WHERE calibration_id = ?

     ORDER BY
        material,
        gate_cm"
);

$snapshotStmt = $db->prepare(
    "SELECT revision_no,status,reason,captured_by,captured_at
     FROM qbook_calibration_revision_snapshots
     WHERE calibration_id=? ORDER BY revision_no DESC"
);

$history = [];

foreach ($rows as $row) {

    $resultStmt->execute([(int)$row['id']]);
    $resultRows = $resultStmt->fetchAll();
    $snapshotStmt->execute([(int)$row['id']]);
    $revisionSnapshots = $snapshotStmt->fetchAll();

    $results = [];

    foreach ($resultRows as $result) {

        $results[] = [
            'material' =>
                $result['material'],

            'gate_cm' =>
                $result['gate_cm'] !== null
                    ? round((float)$result['gate_cm'], 1)
                    : null,

            'avg_total_weight_kg' =>
                $result['avg_total_weight_kg'] !== null
                    ? round((float)$result['avg_total_weight_kg'], 2)
                    : null,

            'avg_counts' =>
                $result['avg_counts'] !== null
                    ? round((float)$result['avg_counts'], 2)
                    : null,

            'moisture_pct' =>
                round((float)$result['moisture_pct'], 2),

            'net_dry_weight_kg' =>
                $result['net_dry_weight_kg'] !== null
                    ? round((float)$result['net_dry_weight_kg'], 2)
                    : null,

            'kg_per_count' =>
                $result['kg_per_count'] !== null
                    ? round((float)$result['kg_per_count'], 2)
                    : null,

            'calculated_at' =>
                $result['calculated_at']
        ];
    }

    $history[] = [
        'calibration_id' =>
            (int)$row['id'],

        'mixer' => [
            'id' =>
                (int)$row['mixer_id'],

            'code' =>
                $row['mixer_code'],

            'name' =>
                $row['mixer_name'],

            'model' =>
                $row['mixer_model'],

            'truck_number' =>
                $row['truck_number']
        ],

        'calibration_date' =>
            $row['calibration_date'],

        'calibration_notes' =>
            $row['calibration_notes'],

        'status' =>
            $row['status'],

        'revision_no' =>
            (int)$row['revision_no'],

        'entered_by' => [
            'id' =>
                (int)$row['entered_by'],

            'name' =>
                $row['entered_by_name']
        ],

        'submitted_at' =>
            $row['submitted_at'],

        'reviewed_by' =>
            $row['reviewed_by'] !== null
                ? [
                    'id' => (int)$row['reviewed_by'],
                    'name' => $row['reviewed_by_name']
                ]
                : null,

        'reviewed_at' =>
            $row['reviewed_at'],

        'rejection_reason' =>
            $row['rejection_reason'],

        'calibration_inputs' => [
            'container_weight_kg' =>
                round((float)$row['container_weight_kg'], 2),

            'stone_moisture_pct' =>
                round((float)$row['stone_moisture_pct'], 2),

            'sand_moisture_pct' =>
                round((float)$row['sand_moisture_pct'], 2),

            'cement_safety_factor_pct' =>
                round((float)$row['cement_safety_factor_pct'], 2)
        ],

        'results' =>
            $results,

        'created_at' =>
            $row['created_at'],

        'updated_at' =>
            $row['updated_at'],

        'revision_snapshots' => array_map(static fn(array $snapshot): array => [
            'revision_no'=>(int)$snapshot['revision_no'],
            'status'=>(string)$snapshot['status'],
            'reason'=>$snapshot['reason'],
            'captured_by'=>(int)$snapshot['captured_by'],
            'captured_at'=>$snapshot['captured_at'],
        ], $revisionSnapshots)
    ];
}

qbook_json([
    'ok' => true,
    'count' => count($history),
    'history' => $history
]);
