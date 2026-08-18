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

$eventType = isset($_GET['event_type'])
    ? trim((string)$_GET['event_type'])
    : '';

$sourceType = isset($_GET['source_type'])
    ? trim((string)$_GET['source_type'])
    : '';

$userId = isset($_GET['user_id'])
    ? (int)$_GET['user_id']
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

$sql = "
    SELECT
        a.id,
        a.user_id,
        a.event_type,
        a.source_type,
        a.source_id,
        a.details,
        a.ip_address,
        a.created_at,

        u.full_name AS user_name,
        u.email AS user_email,
        u.role AS user_role

    FROM qbook_audit_log a

    LEFT JOIN qbook_users u
        ON u.id = a.user_id

    WHERE 1 = 1
";

$params = [];

if ($eventType !== '') {
    $sql .= " AND a.event_type = ?";
    $params[] = $eventType;
}

if ($sourceType !== '') {
    $sql .= " AND a.source_type = ?";
    $params[] = $sourceType;
}

if ($userId > 0) {
    $sql .= " AND a.user_id = ?";
    $params[] = $userId;
}

$sql .= "
    ORDER BY a.created_at DESC, a.id DESC
    LIMIT " . $limit;

$stmt = $db->prepare($sql);
$stmt->execute($params);

$rows = $stmt->fetchAll();

$history = [];

foreach ($rows as $row) {

    $details = null;

    if ($row['details'] !== null && $row['details'] !== '') {
        $decoded = json_decode((string)$row['details'], true);

        if (json_last_error() === JSON_ERROR_NONE) {
            $details = $decoded;
        } else {
            $details = [
                'raw' => $row['details']
            ];
        }
    }

    $history[] = [
        'audit_id' => (int)$row['id'],

        'created_at' => $row['created_at'],

        'user' => $row['user_id'] !== null
            ? [
                'id' => (int)$row['user_id'],
                'name' => $row['user_name'],
                'email' => $row['user_email'],
                'role' => $row['user_role']
            ]
            : null,

        'event_type' => $row['event_type'],

        'source' => [
            'type' => $row['source_type'],
            'id' => $row['source_id'] !== null
                ? (int)$row['source_id']
                : null
        ],

        'details' => $details,

        'ip_address' => $row['ip_address']
    ];
}

qbook_json([
    'ok' => true,
    'count' => count($history),
    'history' => $history
]);