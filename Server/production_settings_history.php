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

/*
 * Optional filters.
 */
$mixerId = isset($_GET['mixer_id'])
    ? (int)$_GET['mixer_id']
    : 0;

$mixDesignId = isset($_GET['mix_design_id'])
    ? (int)$_GET['mix_design_id']
    : 0;

$limit = isset($_GET['limit'])
    ? (int)$_GET['limit']
    : 100;

if ($limit < 1) {
    $limit = 1;
}

if ($limit > 500) {
    $limit = 500;
}

/*
 * Build query.
 *
 * Historical mix quantities come directly from
 * qbook_production_settings snapshot columns.
 */
$sql = "
    SELECT
        ps.id,
        ps.created_at,

        ps.mixer_id,
        m.code AS mixer_code,
        m.name AS mixer_name,
        m.model AS mixer_model,

        ps.calibration_id,
        ps.calibration_revision_no,

        ps.mix_design_id,
        ps.mix_version_no,
        ps.mix_name,
        ps.client_name,
        ps.project_name,

        ps.cement_kg,
        ps.sand_kg,
        ps.granite_kg,
        ps.design_water_l,

        ps.operator_id,
        u.full_name AS operator_name,

        ps.conveyor_speed,
        ps.m3_per_min,

        ps.sand_gate_cm,
        ps.granite_gate_cm,

        ps.sand_moisture_l,
        ps.granite_moisture_l,

        ps.water_additional_l,
        ps.water_flow_lpm

    FROM qbook_production_settings ps

    LEFT JOIN qbook_mixers m
        ON m.id = ps.mixer_id

    LEFT JOIN qbook_users u
        ON u.id = ps.operator_id

    WHERE 1 = 1
";

$params = [];

if ($mixerId > 0) {
    $sql .= " AND ps.mixer_id = ?";
    $params[] = $mixerId;
}

if ($mixDesignId > 0) {
    $sql .= " AND ps.mix_design_id = ?";
    $params[] = $mixDesignId;
}

$sql .= "
    ORDER BY ps.created_at DESC, ps.id DESC
    LIMIT " . $limit;

$stmt = $db->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll();

$history = [];

/*
 * Load admixture snapshot flows.
 */
$admixStmt = $db->prepare(
    "SELECT
        psa.mix_admixture_id,
        psa.flow_lpm,
        ma.name

     FROM qbook_production_setting_admixtures psa

     LEFT JOIN qbook_mix_admixtures ma
        ON ma.id = psa.mix_admixture_id

     WHERE psa.production_setting_id = ?

     ORDER BY psa.id"
);

foreach ($rows as $row) {

    $admixStmt->execute([(int)$row['id']]);
    $admixRows = $admixStmt->fetchAll();

    $admixtures = [];

    foreach ($admixRows as $admix) {

        $admixtures[] = [
            'id' =>
                (int)$admix['mix_admixture_id'],

            'name' =>
                $admix['name'],

            'flow_lpm' =>
                round((float)$admix['flow_lpm'], 1)
        ];
    }

    $history[] = [
        'setting_id' =>
            (int)$row['id'],

        'applied_at' =>
            $row['created_at'],

        'mixer' => [
            'id' =>
                (int)$row['mixer_id'],

            'code' =>
                $row['mixer_code'],

            'name' =>
                $row['mixer_name'],

            'model' =>
                $row['mixer_model']
        ],

        'calibration_id' =>
            (int)$row['calibration_id'],

        'calibration_revision_no' =>
            (int)$row['calibration_revision_no'],

        'mix_design' => [
            'id' =>
                (int)$row['mix_design_id'],

            'version_no' =>
                (int)$row['mix_version_no'],

            'name' =>
                $row['mix_name'],

            'client_name' =>
                $row['client_name'],

            'project_name' =>
                $row['project_name']
        ],

        /*
         * Historical material snapshot.
         * Whole-number display as agreed.
         */
        'mix' => [
            'cement_kg' =>
                (int)round((float)$row['cement_kg']),

            'sand_kg' =>
                (int)round((float)$row['sand_kg']),

            'granite_kg' =>
                (int)round((float)$row['granite_kg']),

            'water_l' =>
                (int)round((float)$row['design_water_l'])
        ],

        'operator' => [
            'id' =>
                (int)$row['operator_id'],

            'name' =>
                $row['operator_name']
        ],

        'settings' => [
            'conveyor_speed' =>
                (int)round((float)$row['conveyor_speed']),

            'production_rate_m3_per_min' =>
                round((float)$row['m3_per_min'], 2),

            'sand_gate_cm' =>
                round((float)$row['sand_gate_cm'], 1),

            'granite_gate_cm' =>
                round((float)$row['granite_gate_cm'], 1),

            'water_flow_lpm' =>
                round((float)$row['water_flow_lpm'], 1),

            'admixtures' =>
                $admixtures
        ],

        /*
         * Keep moisture details available to ADMIN
         * for troubleshooting.
         */
        'water_details' => [
            'sand_moisture_l' =>
                round((float)$row['sand_moisture_l'], 2),

            'granite_moisture_l' =>
                round((float)$row['granite_moisture_l'], 2),

            'additional_water_l' =>
                round((float)$row['water_additional_l'], 2)
        ]
    ];
}

qbook_json([
    'ok' => true,
    'count' => count($history),
    'history' => $history
]);
